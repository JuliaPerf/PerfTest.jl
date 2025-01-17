"""
  MPI extension of PerfTest.jl

  Includes new behaviour to account for the presence of several ranks
"""

module PerfTest_MPIExt

using STREAMBenchmark: add_allthreads
using LinearAlgebra: peakflops
using MPI
using PerfTest
using LinearAlgebra
using STREAMBenchmark
using BenchmarkTools


mpi_rank = 0
mpi_size = 1

function PerfTest.MPISetup(::Type{PerfTest.MPIMode},global_ctx :: Dict{Symbol,Any}) :: Nothing
    MPI.Init()
    global_ctx[:is_main_rank] = ((global_ctx[:mpi_rank] = MPI.Comm_rank(MPI.COMM_WORLD)) == 0)
    global_ctx[:comm_size] = MPI.Comm_size(MPI.COMM_WORLD)
    mpi_rank = 0
    mpi_size = 1
    @info "MPI PerfTest is enabled"
end


#  Will gather results in the dictionaries of the main rank
function MPICommunicateResults!(results::Union{Number,Dict{Int64,Number}}, rank, size)
    if rank != 0
        MPI.Send(results, MPI.COMM_WORLD; dest = 0)
    else
        for i in 1:(size-1)
            results[i] = MPI.Recv(typeof(results[0]), MPI.COMM_WORLD; source=i)
        end
    end
end

op_sum(acc, new, _...) = acc + new
op_avg(acc, new, num) = acc + new/num
op_max(acc, new, _...) = max(acc,new)
op_min(acc, new, _...) = min(acc,new)

function MPIShareAndReduce!(value::Union{Number,Dict{Int64,Number}}, reduction_op :: Function, rank, size)::Number

    if rank != 0
        local_value = value
    else # TODO ASSUMES MAIN RANK IS 0
        local_value = Dict{Int64,Number}()
        local_value[0] = value
        # Local value in main process will hold all values as well
    end

    MPICommunicateResults!(local_value, rank, size)

    if rank == 0
        # Reduction of all values
        acc = 0
        for i in 0:(size-1)
            acc = reduction_op(acc, local_value[i], size)
        end

        @show acc
        return acc
    end
    return value
end

# MEM MW MPI BEGIN
using Base.Threads
# Synchonize the local kernels at the end just in case they took turns doing the transfer, the important is the total transfer of data not the local
# CAUTION adds overhead
copy_kernel(C,A;kwargs...) = begin STREAMBenchmark.copy_nthreads(C,A;kwargs...); MPI.Barrier(MPI.COMM_WORLD) end
add_kernel(C,A,B;kwargs...) = begin STREAMBenchmark.add_nthreads(C,A,B;kwargs...); MPI.Barrier(MPI.COMM_WORLD) end

function _run_kernels(copy, add;
                      verbose = true,
                      N,
                      evals_per_sample = 5,
                      write_allocate = true,
                      nthreads = Threads.nthreads(),
                      init = :parallel)
    α = write_allocate ? 24 : 16
    β = write_allocate ? 32 : 24

    f = t -> N * α / t
    g = t -> N * β / t

    # N / nthreads if necessary
    thread_indices = STREAMBenchmark._threadidcs(N, nthreads)

    # initialize memory
    if init == :parallel
        A = Vector{Float64}(undef, N)
        B = Vector{Float64}(undef, N)
        C = Vector{Float64}(undef, N)
        s = rand()

        # fill in parallel (important for NUMA mapping / first-touch policy)
        @threads :static for tid in 1:nthreads
            @inbounds for i in thread_indices[tid]
                A[i] = 0.0
                B[i] = 0.0
                C[i] = 0.0
            end
        end
    else
        A = zeros(N)
        B = zeros(N)
        C = zeros(N)
        s = rand()
    end

    # COPY
    t_copy = @belapsed $copy($C, $A; nthreads = $nthreads, thread_indices = $thread_indices) samples=10 evals=evals_per_sample setup=begin MPI.Barrier(MPI.COMM_WORLD) end
    bw_copy = f(t_copy)
    verbose && println("╟─ $(MPI.Comm_rank(MPI.COMM_WORLD)) COPY:  ", round(bw_copy; digits = 1), "B/s")

    # ADD
    t_add = @belapsed $add($C, $A, $B; nthreads = $nthreads,
                           thread_indices = $thread_indices) samples=10 evals=evals_per_sample setup=begin MPI.Barrier(MPI.COMM_WORLD) end
    bw_add = g(t_add)
    verbose && println("╟─ $(MPI.Comm_rank(MPI.COMM_WORLD)) ADD:   ", round(bw_add; digits=1), "B/s")

    # statistics
    values = [bw_copy, bw_add]
    calc = f -> round(f(values); digits = 1)

    return (median = calc(median), minimum = calc(minimum), maximum = calc(maximum))
end


function PerfTest.measureMemBandwidth!(::Type{PerfTest.MPIMode}, _PRFT_GLOBAL::Dict{Symbol, Any})

    N = div(_PRFT_GLOBAL[:machine][:cache_sizes][end], 2)
    # In B/s

    _PRFT_GLOBAL[:machine][:empirical][:peakmemBW] = _run_kernels(copy_kernel, add_kernel; N=N)[1]
end

# MEM BW MPI END

function PerfTest.measureCPUPeakFlops!(::Type{PerfTest.MPIMode}, _PRFT_GLOBAL :: Dict{Symbol, Any})
        LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
        # MPI Barrier
        # In Flop/s
        MPI.Barrier(MPI.COMM_WORLD)
        peakflops = LinearAlgebra.peakflops(; parallel=true)

        _PRFT_GLOBAL[:machine][:empirical][:peakflops] = MPIShareAndReduce!(peakflops, op_sum, _PRFT_GLOBAL[:mpi_rank], _PRFT_GLOBAL[:comm_size])
end


function PerfTest.newMetricResult(::Type{PerfTest.MPIMode}; name, units, value, auxiliary=false, magnitude_prefix="", magnitude_mult=0, reduct="Sum")

    return PerfTest.Metric_Result(name,units,value,auxiliary, magnitude_prefix, magnitude_mult, PerfTest.MPI_MetricInfo(MPI.Comm_size(MPI.COMM_WORLD), reduct))
end

function PerfTest.buildPrimitiveMetrics!(::Type{PerfTest.MPIMode}, _PRFT_LOCAL :: Dict, _PRFT_GLOBAL :: Dict{Symbol, Any})

    # MEAN TIME MAX
    _PRFT_LOCAL[:primitives][:median_time] = MPIShareAndReduce!(median(_PRFT_LOCAL[:suite]).time / 1e9,
        op_max, _PRFT_GLOBAL[:mpi_rank], _PRFT_GLOBAL[:comm_size])
    # MIN TIME MIN
    _PRFT_LOCAL[:primitives][:min_time] =MPIShareAndReduce!(minimum(_PRFT_LOCAL[:suite]).time / 1e9,
        op_min, _PRFT_GLOBAL[:mpi_rank], _PRFT_GLOBAL[:comm_size])
    # FLOPS SUM
    _PRFT_LOCAL[:primitives][:autoflop_MPI] = MPIShareAndReduce!(_PRFT_LOCAL[:additional][:autoflop],
        op_sum, _PRFT_GLOBAL[:mpi_rank], _PRFT_GLOBAL[:comm_size])

    # Equal among all ranks
    _PRFT_LOCAL[:primitives][:iterator] = _PRFT_LOCAL[:additional][:iterator]
    # Cannot be collected from other ranks
    _PRFT_LOCAL[:primitives][:ret_value] = _PRFT_LOCAL[:additional][:ret_value]
    _PRFT_LOCAL[:primitives][:printed_output] = _PRFT_LOCAL[:additional][:printed_output]
end

# End of extension
end
