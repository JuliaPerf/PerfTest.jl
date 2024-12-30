

#using MPI
using LinearAlgebra
using CpuId
# Memory and CPU benchmarks used by different methodologies

"""
  This method is used to generate the code responsible for sampling the maximum memory bandwith in every resulting suite.
"""
function setupMemoryBandwidthBenchmark()::Expr
    # TODO MPI extra behaviour
    #println("="^26 * "Maximum memory throughput calculation" * "="^26)
    if false # TODO mpi_enabled
        ret = quote
            # Begin probing the maximum memory throughput
            if (p_mpi_rank == 0)
                global bench_data = STREAMBenchmark.benchmark()
            else
                global bench_data = STREAMBenchmark.benchmark()
            end

            MPI.Barrier()

            local_MT_reference = bench_data.multi.maximum / 1e3

            # Create a buffer on root process to hold the gathered data
            if rank == 0
                recv_buffer = Array{Int64}(undef, size)
            else
                recv_buffer = nothing
            end

            # Gather values from all processes to the root process
            MPI.Gather(my_value, recv_buffer, 0, comm)

            # Root process sums up the gathered data
            if rank == 0
                total = sum(recv_buffer)
                println("Total memory bandwith: ", total)
            end
        end
    else
        ret = quote
            # Begin probing the maximum memory throughput
            global bench_data = STREAMBenchmark.benchmark(N = 1024 * 256 * 540)
            peakbandwidth = bench_data.multi.maximum / 1e3
        end
    end
    #println("="^26 * "=====================================" * "="^26)

    return ret
end


function getMachineInfo()::Expr
    quote
        size = try
            CpuId.cachesize()[end]
        catch
            # Default assumes 25MB (usually too much)
            12 * 1024 * 1024
        end
        global _PRFT_GLOBAL[:machine][:approx_cache_size] = size
    end
end

function measureCPUPeakFlops()::Expr
    quote
        using LinearAlgebra
        LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
        # In Flop/s
        global _PRFT_GLOBAL[:machine][:empirical][:peakflops] = LinearAlgebra.peakflops(; parallel=true)
    end
end

function measureMemBandwidth()::Expr
    quote
        bench_data = STREAMBenchmark.benchmark(N = div(_PRFT_GLOBAL[:machine][:cache_sizes][end], 2))
        # In B/s
        peakbandwidth = bench_data.multi.maximum * 1e6
        global _PRFT_GLOBAL[:machine][:empirical][:peakmemBW] = peakbandwidth
    end
end


function machineBenchmarks()::Expr
    quote
	      # Block to create a separated scope
        let
            _PRFT_GLOBAL[:machine] = Dict{Symbol,Any}()
            _PRFT_GLOBAL[:machine][:empirical] = Dict{Symbol,Any}()
            $(getMachineInfo())
            $(measureCPUPeakFlops())
            $(measureMemBandwidth())
        end
    end
end

"""
  This method is used to generate the code responsible for sampling the maximum CPU FLOPS based on the avaiable threads in every resulting suite.
"""
function setupCPUPeakFlopBenchmark()::Expr

    # mpi_enabled
    return true ? quote
            if (p_mpi_rank == 0)
                using LinearAlgebra
                global peakflops = LinearAlgebra.peakflops() / 1e9
            end
    end :
           quote
        using LinearAlgebra
        LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
        global peakflops = LinearAlgebra.peakflops(; parallel=true) / 1e9
        end
end
