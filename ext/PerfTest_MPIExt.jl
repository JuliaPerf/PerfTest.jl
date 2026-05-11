"""
  MPI extension of PerfTest.jl

  Includes new behaviour to account for the presence of several ranks
"""

module PerfTest_MPIExt

using MPI
using PerfTest
using LinearAlgebra
using BenchmarkTools
using Base.Threads

# Module-level MPI state
mpi_rank = 0
mpi_size = 1
mpi_initialized = false

function PerfTest.MPISetup(::Type{PerfTest.MPIMode})::Nothing
    if !mpi_initialized
        MPI.Init()
    end
    global mpi_rank = MPI.Comm_rank(MPI.COMM_WORLD)
    global mpi_size = MPI.Comm_size(MPI.COMM_WORLD)
    global mpi_initialized = true

    PerfTest.addLog("machine", "[MPI] PerfTest MPI extension enabled - Rank $mpi_rank of $mpi_size")
    return nothing
end

# Override main_rank and ranks for MPI mode
function PerfTest.main_rank(mode::Type{PerfTest.MPIMode})::Bool
    return mpi_rank == 0
end

function PerfTest.mpi_rank(mode::Type{PerfTest.MPIMode})::Int
    return mpi_rank
end

function PerfTest.ranks(mode::Type{PerfTest.MPIMode})::Int
    return mpi_size
end

# MPI Communication utilities
const MAIN_RANK = 0

"""
    gather_to_main(value::N; comm=MPI.COMM_WORLD, root=MAIN_RANK) where {N}

Gather a scalar `value` from every rank into a `Dict{Int64, N}` on the main rank,
keyed by the source rank. Non-main ranks receive an empty `Dict{Int64, N}`.

`N` must be a type natively supported by MPI (e.g. a `Number` / `isbits` type).
"""
function gatherToMain(value::N; comm::MPI.Comm=MPI.COMM_WORLD,
    root::Integer=MAIN_RANK) where {N}
    rank = MPI.Comm_rank(comm)
    nproc = MPI.Comm_size(comm)

    # Pack the local scalar in a length-1 buffer so MPI.Gather can move it.
    sendbuf = N[value]

    if rank == root
        recvbuf = Vector{N}(undef, nproc)
        MPI.Gather!(sendbuf, MPI.UBuffer(recvbuf, 1), comm; root=root)
        return Dict{Int64,N}(Int64(r) => recvbuf[r+1] for r in 0:(nproc-1))
    else
        MPI.Gather!(sendbuf, nothing, comm; root=root)
        return Dict{Int64,N}()
    end
end

"""
    gather_to_main(value::Vector{N}; comm=MPI.COMM_WORLD, root=MAIN_RANK) where {N}

Vector dispatch: each rank contributes a `Vector{N}` (lengths may differ between
ranks). On the main rank, returns a `Dict{Int64, Vector{N}}` keyed by source rank.
Other ranks receive an empty dict.
"""
function gatherToMain(value::Vector{N}; comm::MPI.Comm=MPI.COMM_WORLD,
    root::Integer=MAIN_RANK) where {N}
    rank = MPI.Comm_rank(comm)
    nproc = MPI.Comm_size(comm)

    # First, communicate per-rank lengths so the root can build a VBuffer.
    local_len = Cint(length(value))
    counts = if rank == root
        Vector{Cint}(undef, nproc)
    else
        nothing
    end
    MPI.Gather!(Cint[local_len],
        rank == root ? MPI.UBuffer(counts, 1) : nothing,
        comm; root=root)

    if rank == root
        total = sum(counts)
        recvbuf = Vector{N}(undef, total)
        MPI.Gatherv!(value, MPI.VBuffer(recvbuf, counts), comm; root=root)

        out = Dict{Int64,Vector{N}}()
        offset = 0
        for r in 0:(nproc-1)
            n = Int(counts[r+1])
            out[Int64(r)] = recvbuf[(offset+1):(offset+n)]
            offset += n
        end
        return out
    else
        MPI.Gatherv!(value, nothing, comm; root=root)
        return Dict{Int64,Vector{N}}()
    end
end

"""
    reduce_to_main(op, value; comm=MPI.COMM_WORLD, root=MAIN_RANK)

Gather every rank's `value` onto the main rank using [`gather_to_main`](@ref) and
then apply the reduction `op` to the collected values.

- On the **main rank** returns the reduced value (a scalar for the scalar
  dispatch, a `Vector{N}` for the vector dispatch — whatever `op` produces).
- On **other ranks** returns the original local `value` unchanged.

`op` is any callable accepting a single iterable, e.g. `sum`, `minimum`,
`maximum`, `prod`, or `vs -> reduce(+, vs)`.
"""
function reduceToMain(value::N, op::Function; comm::MPI.Comm=MPI.COMM_WORLD,
    root::Integer=MAIN_RANK) where {N}
    gathered = gatherToMain(value; comm=comm, root=root)
    if MPI.Comm_rank(comm) == root
        ordered = [gathered[Int64(r)] for r in 0:(MPI.Comm_size(comm)-1)]
        return op(ordered)
    else
        return value
    end
end

function reduceToMain(value::Vector{N}, op::Function; comm::MPI.Comm=MPI.COMM_WORLD,
    root::Integer=MAIN_RANK) where {N}
    gathered = gatherToMain(value; comm=comm, root=root)
    if MPI.Comm_rank(comm) == root
        ordered = [gathered[Int64(r)] for r in 0:(MPI.Comm_size(comm)-1)]
        reduced = []
        for i in 1:length(value)
            push!(reduced, op(v[i] for v in ordered))
        end
        return reduced
    else
        return value
    end
end

"""
    Share values of a dictionary from the main rank to all ranks. Value must be a isbits type.
"""
function bcastFromMain(val::N; comm::MPI.Comm=MPI.COMM_WORLD,
    root::Integer=MAIN_RANK) where {N}
    nbuf = N[val]
    MPI.Bcast!(nbuf, comm; root=root)
    return nbuf[1]
end

function bcastFromMain(vals::Vector{N}; comm::MPI.Comm=MPI.COMM_WORLD,
    root::Integer=MAIN_RANK) where {N}
    if MPI.Comm_rank(comm) == root
        nbuf = vals
    else
        nbuf = Vector{N}(undef, length(vals))
    end
    MPI.Bcast!(nbuf, comm; root=root)
    return nbuf
end

# Reduction operations
op_sum(vals) = sum(vals)
op_avg(vals) = sum(vals) / length(vals)
op_max(vals) = maximum(vals)
op_min(vals) = minimum(vals)


# MPI-synchronized bandwidth benchmark kernels
# Synchronize the local kernels at the end to ensure coordinated memory transfer measurement
using DataFrames
using BandwidthBenchmark
init_kernel = BandwidthBenchmark.init_kernel
copy_kernel = BandwidthBenchmark.copy_kernel
update_kernel = BandwidthBenchmark.update_kernel
triad_kernel = BandwidthBenchmark.triad_kernel
daxpy_kernel = BandwidthBenchmark.daxpy_kernel
striad_kernel = BandwidthBenchmark.striad_kernel
sdaxpy_kernel = BandwidthBenchmark.sdaxpy_kernel
allocate = BandwidthBenchmark.allocate




"""
Run STREAM benchmark kernels with MPI synchronization, shamelessly borrowed from the original STREAMBenchmark.bwbench function
"""
function _run_kernels_mpi(;
    N::Integer=120_000_000,
    niter::Integer=10,
    verbose::Bool=false,
    nthreads::Integer=Threads.nthreads(),
    alignment::Integer=64,
    write_allocate::Bool=false,
)

    # check arguments
    1 ≤ N || throw(ArgumentError("N must be ≥ 1."))
    1 ≤ niter || throw(ArgumentError("niter must be ≥ 1."))
    ispow2(alignment) || throw(ArgumentError("alignment $alignment is not a power of 2"))
    alignment ≥ sizeof(Float64) ||
        throw(ArgumentError("alignment $alignment is not a multiple of $(sizeof(Float64))"))
    1 ≤ nthreads ≤ Threads.nthreads() || throw(
        ArgumentError(
            "nthreads $nthreads must ≥ 1 and ≤ $(Threads.nthreads()). If you want more threads, start Julia with a higher number of threads.",
        ),
    )

    # compute thread_indices
    # use only first `nthreads` threads, i.e. @threads for tid in 1:nthreads + manual splitting
    Nperthread = floor(Int, N / nthreads)
    rest = rem(N, nthreads)
    thread_indices = collect(Iterators.partition(1:N, Nperthread))
    if rest != 0
        # last thread compensates for the nonzero remainder
        thread_indices[end-1] = thread_indices[end-1].start:thread_indices[end].stop
    end


    # allocate data
    a = allocate(Float64, N, alignment)
    b = allocate(Float64, N, alignment)
    c = allocate(Float64, N, alignment)
    d = allocate(Float64, N, alignment)
    scalar = 3.0

    # initialize data in parallel (important for NUMA / first-touch policy)
    @threads :static for tid in 1:nthreads
        @inbounds for i in thread_indices[tid]
            a[i] = 2.0
            b[i] = 2.0
            c[i] = 0.5
            d[i] = 1.0
        end
    end

    # print information
    if verbose
        nthreads > 1 && println("Threading enabled, using $nthreads (of $(Threads.nthreads())) Julia threads")
        alloc = 4.0 * sizeof(Float64) * N * 1.0e-06
        println("Total allocated datasize: $(alloc) MB")
    end

    # perform measurement
    times = zeros(7, niter)
    for k in 1:niter
        times[1, k] = @elapsed (init_kernel(b, scalar; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
        times[2, k] = @elapsed (copy_kernel(c, a; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
        times[3, k] = @elapsed (update_kernel(a, scalar; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
        times[4, k] = @elapsed (triad_kernel(a, b, c, scalar; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
        times[5, k] = @elapsed (daxpy_kernel(a, b, scalar; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
        times[6, k] = @elapsed (striad_kernel(a, b, c, d; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
        times[7, k] = @elapsed (sdaxpy_kernel(a, b, c; nthreads=nthreads, thread_indices=thread_indices); MPI.Barrier(MPI.COMM_WORLD))
    end

    # analysis / table output of results
    results = DataFrame(;
        Function=String[],
        var"Rate (MB/s)"=Float64[],
        var"Rate (MFlop/s)"=Float64[],
        var"Avg time"=Float64[],
        var"Min time"=Float64[],
        var"Max time"=Float64[],
    )
    for j in 1:7
        # ignore the first run because of compilation
        mintime = @views minimum(times[j, 2:end])
        maxtime = @views maximum(times[j, 2:end])
        avgtime = @views mean(times[j, 2:end])
        if write_allocate
            bytes = BandwidthBenchmark.BENCHMARKS[j].words * BandwidthBenchmark.BENCHMARKS[j].write_alloc_factor * sizeof(Float64) * N
        else
            bytes = BandwidthBenchmark.BENCHMARKS[j].words * sizeof(Float64) * N
        end
        flops = BandwidthBenchmark.BENCHMARKS[j].flops * N
        data_rate = 1.0e-06 * bytes / mintime
        flop_rate = 1.0e-06 * flops / mintime
        push!(
            results, [BandwidthBenchmark.BENCHMARKS[j].label, data_rate, flop_rate, avgtime, mintime, maxtime]
        )
    end
    verbose && pretty_table(results)

    # validation
    BandwidthBenchmark.validate(a, b, c, d, N, niter)

    return results
end


# Override core measurement functions for MPI mode
function PerfTest.machineBenchmarks(mode::Type{PerfTest.MPIMode}, ctx::PerfTest.Context)::Expr
    quote
        # Block to create a separated scope
        let
            PerfTest.Topology.getMachineTopology!()
            # First element L3, second element L2, third element L1
            _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = PerfTest.Topology.getCacheSizes()
            $(ctx._global.uses_benchmarks == Set{Symbol}() ? quote end : quote
                measureCPUPeakFlops!($mode, _PRFT_GLOBALS)
                measureMemBandwidth!($mode, _PRFT_GLOBALS)
            end)
        end
    end
end

function PerfTest.measureCPUPeakFlops!(::Type{PerfTest.MPIMode}, _PRFT_GLOBALS::PerfTest.GlobalSuiteData)
    LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())

    # Synchronize all ranks before measurement
    MPI.Barrier(MPI.COMM_WORLD)

    rank = mpi_rank
    size = mpi_size
    # Local peak flops measurement
    local_peakflops = LinearAlgebra.peakflops(; parallel=true)
    PerfTest.addLog("machine", "[MACHINE/MPI] (Rank $rank) max flops $local_peakflops")


    # Sum peak flops across all ranks
    _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK] = reduceToMain(local_peakflops, op_sum)

    if PerfTest.main_rank(PerfTest.MPIMode)
        PerfTest.addLog("machine", "[MACHINE/MPI] CPU max attainable flops (sum of $size ranks) = $(_PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]) [FLOP/S]")
    end
end

function PerfTest.measureMemBandwidth!(::Type{PerfTest.MPIMode}, _PRFT_GLOBALS::PerfTest.GlobalSuiteData)
    def = PerfTest.Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"]
    if def == 0
        N = _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES][1] * 4
    else
        N = PerfTest.Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"]
    end
    rank = mpi_rank
    size = mpi_size
    # Run MPI-synchronized bandwidth benchmarks
    bench_data = _run_kernels_mpi(N=N, verbose=false)
    peakbandwidth_local = bench_data[!, 2] * 10^6  # Convert from MB/s to Byte/s

    peakbandwidth = reduceToMain(peakbandwidth_local, op_sum)
    # in Bytes/sec
    # "Init"
    # "Copy"
    # "Update"
    # "Triad"
    # "Daxpy"
    # "STriad"
    # "SDaxpy"
    if PerfTest.main_rank(PerfTest.MPIMode)
        _PRFT_GLOBALS.builtins[:MEM_BENCH] = Float64.(peakbandwidth)
        _PRFT_GLOBALS.builtins[:MEM_BENCH_INIT] = peakbandwidth[1]
        _PRFT_GLOBALS.builtins[:MEM_BENCH_COPY] = peakbandwidth[2]
        _PRFT_GLOBALS.builtins[:MEM_BENCH_UPDATE] = peakbandwidth[3]
        _PRFT_GLOBALS.builtins[:MEM_BENCH_TRIAD] = peakbandwidth[4]
        _PRFT_GLOBALS.builtins[:MEM_BENCH_DAXPY] = peakbandwidth[5]
        _PRFT_GLOBALS.builtins[:MEM_BENCH_STRIAD] = peakbandwidth[6]
        _PRFT_GLOBALS.builtins[:MEM_BENCH_SDAXPY] = peakbandwidth[7]

        # COMPAT symbols for benchmarks:
        _PRFT_GLOBALS.builtins[:MEM_STREAM_COPY] = peakbandwidth[2]
        _PRFT_GLOBALS.builtins[:MEM_STREAM_ADD] = peakbandwidth[4]
        _PRFT_GLOBALS.builtins[:MEM_STREAM_STRIAD] = peakbandwidth[6]

        PerfTest.addLog("machine", "[MACHINE/MPI] CPU max attainable bandwidth (sum of $size ranks) = $(_PRFT_GLOBALS.builtins[:MEM_BENCH]) [Byte/s]")
    else
        # Non-main ranks set the benchmark values to zero to avoid confusion
        _PRFT_GLOBALS.builtins[:MEM_BENCH] = zeros(Float64, 7)
        _PRFT_GLOBALS.builtins[:MEM_BENCH_INIT] = 0
        _PRFT_GLOBALS.builtins[:MEM_BENCH_COPY] = 0
        _PRFT_GLOBALS.builtins[:MEM_BENCH_UPDATE] = 0
        _PRFT_GLOBALS.builtins[:MEM_BENCH_TRIAD] = 0
        _PRFT_GLOBALS.builtins[:MEM_BENCH_DAXPY] = 0
        _PRFT_GLOBALS.builtins[:MEM_BENCH_STRIAD] = 0
        _PRFT_GLOBALS.builtins[:MEM_BENCH_SDAXPY] = 0

        _PRFT_GLOBALS.builtins[:MEM_STREAM_COPY] = 0
        _PRFT_GLOBALS.builtins[:MEM_STREAM_ADD] = 0
        _PRFT_GLOBALS.builtins[:MEM_STREAM_STRIAD] = 0
    end
    for (k, v) in _PRFT_GLOBALS.builtins
        if typeof(v) in [Number, Vector{Number}, Char, Bool]
            _PRFT_GLOBALS.builtins[k] = bcastFromMain(v; comm=MPI.COMM_WORLD)
        end
    end
end

# Override metric creation for MPI mode

function PerfTest.newMetricResult(::Type{PerfTest.MPIMode};
    name,
    units,
    value,
    auxiliary=false,
    magnitude_prefix="",
    magnitude_mult=1,
    reduct="Sum")
    mpi_info = PerfTest.MPI_MetricInfo(MPI.Comm_size(MPI.COMM_WORLD), reduct)
    return PerfTest.Metric_Result(name, units, value, auxiliary, magnitude_prefix, magnitude_mult, mpi_info)
end

# Build primitive metrics with MPI reduction
function PerfTest.buildPrimitiveMetrics!(::Type{PerfTest.MPIMode}, ts::PerfTest.PerfTestSet, test_result::PerfTest.Test_Result)
    rank = mpi_rank
    size = mpi_size

    # MEDIAN TIME - use MAX across ranks (slowest determines overall time)
    local_median_time = median(ts.benchmarks[test_result.name]).time / 1e9
    test_result.primitives[:median_time] = reduceToMain(local_median_time, op_max)

    # MIN TIME - use MIN across ranks
    local_min_time = minimum(ts.benchmarks[test_result.name]).time / 1e9
    test_result.primitives[:min_time] = reduceToMain(local_min_time, op_min)

    # Iterator count - should be equal among all ranks
    test_result.primitives[:iterator] = ts.iterator

    test_result.primitives[:autoflop] = reduceToMain(test_result.primitives[:autoflop], op_sum)
end

# Nothing to do here (YET)
function PerfTest.clean(mode::Type{PerfTest.MPIMode})
end

end # module PerfTest_MPIExt