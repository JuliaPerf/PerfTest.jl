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
function PerfTest.main_rank(mode :: Type{PerfTest.MPIMode})::Bool
    return mpi_rank == 0
end

function PerfTest.mpi_rank(mode :: Type{PerfTest.MPIMode}) :: Int
    return mpi_rank
end

function PerfTest.ranks(mode :: Type{PerfTest.MPIMode})::Int
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

"""
Run STREAM benchmark kernels with MPI synchronization
"""
function _run_kernels_mpi(copy, add;
                          verbose=false,
                          N,
                          evals_per_sample=10,
                          write_allocate=true,
                          nthreads=Threads.nthreads(),
                          init=:parallel)
    α = write_allocate ? 24 : 16
    β = write_allocate ? 32 : 24

    f = t -> N * α / t
    g = t -> N * β / t

    thread_indices = STREAMBenchmark._threadidcs(N, nthreads)

    # Initialize memory
    if init == :parallel
        A = Vector{Float64}(undef, N)
        B = Vector{Float64}(undef, N)
        C = Vector{Float64}(undef, N)

        # Fill in parallel (important for NUMA mapping / first-touch policy)
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
    end

    # COPY benchmark with MPI barrier setup
    t_copy = @belapsed $copy($C, $A; nthreads=$nthreads, thread_indices=$thread_indices) setup = begin
        MPI.Barrier(MPI.COMM_WORLD)
    end samples = 10 evals = evals_per_sample
    bw_copy = f(t_copy)
    
    if verbose
        println("╟─ Rank $(MPI.Comm_rank(MPI.COMM_WORLD)) COPY: ", round(bw_copy; digits=1), " B/s")
    end

    # ADD benchmark with MPI barrier setup
    t_add = @belapsed $add($C, $A, $B; nthreads=$nthreads, thread_indices=$thread_indices) setup = begin
        MPI.Barrier(MPI.COMM_WORLD)
    end samples = 10 evals = evals_per_sample
    bw_add = g(t_add)
    
    if verbose
        println("╟─ Rank $(MPI.Comm_rank(MPI.COMM_WORLD)) ADD:  ", round(bw_add; digits=1), " B/s")
    end

    return (bw_copy, bw_add)
end


# Override core measurement functions for MPI mode
function PerfTest.getMachineInfo(::Type{PerfTest.MPIMode}, _PRFT_GLOBALS::PerfTest.GlobalSuiteData)::Expr
    if Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"] == 0
        return quote
            size = try
                CpuId.cachesize()
            catch
                addLog("machine", "[MACHINE/MPI] CpuId failed, using default cache size")
                [1024 * 1024 * 16]
            end
            _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = size

            addLog("machine", "[MACHINE/MPI] Memory buffer size for benchmarking = $(size ./ 1024 ./ 1024) [MB]")
        end
    else
	return quote
        _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = [$(Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"])]

	    addLog("machine", "[MACHINE/MPI] Set by config, benchmark buffer size = $(_PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES]  ./ 1024 ./ 1024) [MB]")
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
    N = _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES][end] 
    rank = mpi_rank
    size = mpi_size
    
    # Run MPI-synchronized STREAM benchmarks
    bench_data = _run_kernels_mpi(copy_kernel_mpi, add_kernel_mpi; N=N, verbose=false)
    
    # Each rank's bandwidth, multiplied by number of ranks for aggregate
    local_copy_bw = bench_data[1]
    local_add_bw = bench_data[2]
    
    PerfTest.addLog("machine", "[MACHINE/MPI] (Rank $rank) max stream $bench_data")
    # Sum bandwidth across all ranks
    total_copy_bw = MPIShareAndReduce!(local_copy_bw, op_sum, rank, size)
    total_add_bw = MPIShareAndReduce!(local_add_bw, op_sum, rank, size)
    
    _PRFT_GLOBALS.builtins[:MEM_STREAM] = (total_copy_bw, total_add_bw)
    _PRFT_GLOBALS.builtins[:MEM_STREAM_COPY] = total_copy_bw
    _PRFT_GLOBALS.builtins[:MEM_STREAM_ADD] = total_add_bw
    if PerfTest.main_rank(PerfTest.MPIMode) 
        PerfTest.addLog("machine", "[MACHINE/MPI] CPU max attainable bandwidth (sum of $size ranks) = $(_PRFT_GLOBALS.builtins[:MEM_STREAM]) [Byte/s]")
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

function PerfTest.clean(mode :: Type{PerfTest.MPIMode})
    PerfTest.toggleMPI()
end

end # module PerfTest_MPIExt