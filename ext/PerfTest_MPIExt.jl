"""
  MPI extension of PerfTest.jl

  Includes new behaviour to account for the presence of several ranks
"""

module PerfTest_MPIExt

using MPI
using PerfTest
using LinearAlgebra
using STREAMBenchmark
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
    PerfTest.toggleMPI()
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

"""
Gather results from all ranks to the main rank (rank 0)
"""
function MPICommunicateResults!(results::Number, rank, size)
    if rank != 0
        MPI.Send(results, MPI.COMM_WORLD; dest=0)
        return Dict{Int64,Number}(rank => results)
    else
        gathered = Dict{Int64,Number}()
        gathered[0] = results
        for i in 1:(size-1)
            gathered[i] = MPI.Recv(typeof(results), MPI.COMM_WORLD; source=i)
        end
        return gathered
    end
end

function MPICommunicateResults!(results::Dict{Int64,Number}, rank, size)
    if rank != 0
        MPI.Send(results[rank], MPI.COMM_WORLD; dest=0)
    else
        for i in 1:(size-1)
            results[i] = MPI.Recv(Number, MPI.COMM_WORLD; source=i)
        end
    end
    return results
end

# Reduction operations
op_sum(acc, new, _...) = acc + new
op_avg(acc, new, num) = acc + new / num
op_max(acc, new, _...) = max(acc, new)
op_min(acc, new, _...) = min(acc, new)

"""
Share values across all ranks and reduce them on the main rank
"""
function MPIShareAndReduce!(value::Number, reduction_op::Function, rank, size)::Number
    gathered = MPICommunicateResults!(value, rank, size)

    if rank == 0
        acc = 0.0
        for i in 0:(size-1)
            acc = reduction_op(acc, gathered[i], size)
        end
        return acc
    end
    return value
end

function MPIShareAndReduce!(values::Vector{Number}, reduction_op::Function, rank, size)::Vector{Number}
    gathered = MPICommunicateResults!(Dict(i => values[i] for i in 0:(size-1)), rank, size)

    if rank == 0
        acc = zeros(length(values))
        for i in 0:(size-1)
            for j in eachindex(values)
                acc[j] = reduction_op(acc[j], gathered[i][j], size)
            end
        end
        return acc
    end
    return values

end

# MPI-synchronized STREAM benchmark kernels
# Synchronize the local kernels at the end to ensure coordinated memory transfer measurement
function copy_kernel_mpi(C, A; kwargs...)
    STREAMBenchmark.copy_nthreads(C, A; kwargs...)
    MPI.Barrier(MPI.COMM_WORLD)
end

function add_kernel_mpi(C, A, B; kwargs...)
    STREAMBenchmark.add_nthreads(C, A, B; kwargs...)
    MPI.Barrier(MPI.COMM_WORLD)
end

import BandwidthBenchmark: copy_kernel, add_kernel, update_kernel, triad_kernel, daxpy_kernel, striad_kernel, sdaxpy_kernel, validate
import DataFrames


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
    times = zeros(NBENCH, niter)
    for k in 1:niter
        times[1, k] = @elapsed (init_kernel(b, scalar; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
        times[2, k] = @elapsed (copy_kernel(c, a; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
        times[3, k] = @elapsed (update_kernel(a, scalar; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
        times[4, k] = @elapsed (triad_kernel(a, b, c, scalar; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
        times[5, k] = @elapsed (daxpy_kernel(a, b, scalar; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
        times[6, k] = @elapsed (striad_kernel(a, b, c, d; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
        times[7, k] = @elapsed (sdaxpy_kernel(a, b, c; nthreads=nthreads, kwargs...); MPI.Barrier(MPI.COMM_WORLD))
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
    for j in 1:NBENCH
        # ignore the first run because of compilation
        mintime = @views minimum(times[j, 2:end])
        maxtime = @views maximum(times[j, 2:end])
        avgtime = @views mean(times[j, 2:end])
        if write_allocate
            bytes = BENCHMARKS[j].words * BENCHMARKS[j].write_alloc_factor * sizeof(Float64) * N
        else
            bytes = BENCHMARKS[j].words * sizeof(Float64) * N
        end
        flops = BENCHMARKS[j].flops * N
        data_rate = 1.0e-06 * bytes / mintime
        flop_rate = 1.0e-06 * flops / mintime
        push!(
            results, [BENCHMARKS[j].label, data_rate, flop_rate, avgtime, mintime, maxtime]
        )
    end
    verbose && pretty_table(results)

    # validation
    validate(a, b, c, d, N, niter)

    return results
end


# Override core measurement functions for MPI mode
function PerfTest.machineBenchmarks(mode::Type{PerfTest.MPIMode}, ctx :: Context) :: Expr
    quote
	      # Block to create a separated scope
        let
            PerfTest.Topology.getMachineTopology!()
            # First element L3, second element L2, third element L1
            _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = PerfTest.Topology.getCacheSizes()
            $(ctx._global.uses_benchmarks == Set{Symbol}() ? quote 
            end : quote
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
    _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK] = MPIShareAndReduce!(local_peakflops, op_sum, rank, size)

    if PerfTest.main_rank(PerfTest.MPIMode)
        PerfTest.addLog("machine", "[MACHINE/MPI] CPU max attainable flops (sum of $size ranks) = $(_PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]) [FLOP/S]")
    end
end

function PerfTest.measureMemBandwidth!(::Type{PerfTest.MPIMode}, _PRFT_GLOBALS::PerfTest.GlobalSuiteData)
    def = Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"]
    if def == 0
        N = _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES][1] * 4
    else
        N = Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"]
    end
    rank = mpi_rank
    size = mpi_size
    # Run MPI-synchronized bandwidth benchmarks
    bench_data = _run_kernels_mpi(N=N, verbose=false)
    peakbandwidth_local = bench_data[!, 2] * 10^6  # Convert from MB/s to Byte/s
    
    peakbandwidth = MPIShareAndReduce!(peakbandwidth_local, op_sum, rank, size)
    # in Bytes/sec
    # "Init"
    # "Copy"
    # "Update"
    # "Triad"
    # "Daxpy"
    # "STriad"
    # "SDaxpy"
    if PerfTest.main_rank(PerfTest.MPIMode)
        _PRFT_GLOBALS.builtins[:MEM_BENCH] = peakbandwidth
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

        addLog("machine", "[MACHINE/MPI] CPU max attainable bandwidth (sum of $size ranks) = $(_PRFT_GLOBALS.builtins[:MEM_BENCH]) [Byte/s]")
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

function PerfTest.buildPrimitiveMetrics!(::Type{PerfTest.MPIMode},
    ts::PerfTest.PerfTestSet,
    test_result::PerfTest.Test_Result)
    rank = mpi_rank
    size = mpi_size

    # MEDIAN TIME - use MAX across ranks (slowest determines overall time)
    local_median_time = median(ts.benchmarks[test_result.name]).time / 1e9
    test_result.primitives[:median_time] = MPIShareAndReduce!(local_median_time, op_max, rank, size)

    # MIN TIME - use MIN across ranks
    local_min_time = minimum(ts.benchmarks[test_result.name]).time / 1e9
    test_result.primitives[:min_time] = MPIShareAndReduce!(local_min_time, op_min, rank, size)

    # Iterator count - should be equal among all ranks
    test_result.primitives[:iterator] = ts.iterator

    test_result.primitives[:autoflop] = MPIShareAndReduce!(test_result.primitives[:autoflop], op_sum, rank, size)
end

function PerfTest.clean(mode::Type{PerfTest.MPIMode})
    PerfTest.toggleMPI()
end

end # module PerfTest_MPIExt