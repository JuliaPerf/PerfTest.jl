
#using MPI
using LinearAlgebra
# Memory and CPU benchmarks used by different methodologies

"""
  This method is used to generate the code responsible for sampling the maximum memory bandwith in every resulting suite.
"""
function setupMemoryBandwidthBenchmark()::Expr
    # TODO MPI extra behaviour
    #println("="^26 * "Maximum memory throughput calculation" * "="^26)
    if mpi_enabled
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


"""
  This method is used to generate the code responsible for sampling the maximum CPU FLOPS based on the avaiable threads in every resulting suite.
"""
function setupCPUPeakFlopBenchmark()::Expr

    return mpi_enabled ? quote
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
