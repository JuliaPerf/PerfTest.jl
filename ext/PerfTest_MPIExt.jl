"""
  MPI extension of PerfTest.jl

  Includes new behaviour to account for the presence of several ranks
"""

module PerfTest_MPIExt

using MPI
using PerfTest

mpi_rank = 0
mpi_size = 1

function MPI_setup(global_ctx :: Dict{Symbol,Any}) :: Nothing
    MPI.Init()
    global_ctx[:is_main_rank] = (MPI.Comm_rank(MPI.COMM_WORLD) == 0)
    global_ctx[:comm_size] = MPI.Comm_size(MPI.COMM_WORLD)
    mpi_rank = 0
    mpi_size = 1
    @info "MPI PerfTest is enabled"
end
PerfTest.MPI_setup = MPI_setup

function MPIMeasureMemBandwidth()::Expr
    quote
        MPI.Barrier()
        bench_data = STREAMBenchmark.benchmark(N = div(_PRFT_GLOBAL[:machine][:cache_sizes][end], 2))
        # In B/s
        peakbandwidth = bench_data.multi.maximum * 1e6
        if !(_PRFT_GLOBAL[:is_main_rank])
            _PRFT_GLOBAL[:machine][:empirical][:peakmemBW_MPI] = peakbandwidth
        else
            _PRFT_GLOBAL[:machine][:empirical][:peakmemBW_MPI] = Dict{Int64,Number}()
            _PRFT_GLOBAL[:machine][:empirical][:peakmemBW_MPI][0] = peakbandwidth
        end
        MPICommunicateResults(_PRFT_GLOBAL[:machine][:empirical][:peakmemBW_MPI], _PRFT_GLOBAL[:mpi_rank], _PRFT_GLOBAL[:mpi_size])

        if _PRFT_GLOBAL[:is_main_rank]
            sum = 0
            for i in 0:(_PRFT_GLOBAL[:mpi_size] - 1)
                sum +=  _PRFT_GLOBAL[:machine][:empirical][:peakmemBW_MPI][i]
            end
            global _PRFT_GLOBAL[:machine][:empirical][:peakmemBW] = sum
        end
    end
end
PerfTest.measureMemBandwidth = MPIMeasureMemBandwidth

function MPI_measureCPUPeakFlops()::Expr
    quote
        using LinearAlgebra
        LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
        # MPI Barrier
        # In Flop/s
        MPI.Barrier()
        global _PRFT_GLOBAL[:machine][:empirical][:peakflops] = LinearAlgebra.peakflops(; parallel=true)
        # In B/s
        peakflops = bench_data.multi.maximum * 1e6
        if !(_PRFT_GLOBAL[:is_main_rank]) 
            _PRFT_GLOBAL[:machine][:empirical][:peakflops_MPI] = peakflops
        else
            _PRFT_GLOBAL[:machine][:empirical][:peakflops_MPI] = Dict{Int64,Number}()
            _PRFT_GLOBAL[:machine][:empirical][:peakflops_MPI][0] = peakflops
        end
        MPICommunicateResults(_PRFT_GLOBAL[:machine][:empirical][:peakflops_MPI], _PRFT_GLOBAL[:mpi_rank], _PRFT_GLOBAL[:mpi_size])

        if _PRFT_GLOBAL[:is_main_rank]
            sum = 0
            for i in 0:(_PRFT_GLOBAL[:mpi_size] - 1)
                sum +=  _PRFT_GLOBAL[:machine][:empirical][:peakflops_MPI][i]
            end
            global _PRFT_GLOBAL[:machine][:empirical][:peakflops] = sum
        end
    end
end
PerfTest.measureCPUPeakFlops = MPI_measureCPUPeakFlops


function MPInewMetricResult(;name, units, value, auxiliary=false, magnitude_prefix="", magnitude_mult=0, reduct="")
    return Metric_Result(name,units,value,auxiliary,magnitude_prefix,magnitude_mult, true, MPI.Comm_size(MPI.COMM_WORLD),)
end
PerfTest.newMetricResult = MPInewMetricResult

#  Will gather results in the dictionaries of the main rank
function MPICommunicateResults!(results :: Union{Number, Dict{Int64, Number}}, rank, size)
    if rank != 0
        MPI.Send(results, comm; dest = 0) 
    else
        for i in 1:(size-1)
            results[i] = MPI.Recv(typeof(results[0]), comm; source=i)
        end
    end
end
PerfTest.MPICommunicateResults = MPICommunicateResults


function MPI_buildPrimitiveMetrics()::Expr
    return quote
        if !(_PRFT_GLOBAL[:is_main_rank])
            _PRFT_LOCAL[:primitives][:median_time] = median(_PRFT_LOCAL[:suite]).time / 1e9
            _PRFT_LOCAL[:primitives][:min_time] = minimum(_PRFT_LOCAL[:suite]).time / 1e9
            _PRFT_LOCAL[:primitives][:autoflop] = _PRFT_LOCAL[:additional][:autoflop]
            _PRFT_LOCAL[:primitives][:ret_value] = _PRFT_LOCAL[:additional][:ret_value]
            _PRFT_LOCAL[:primitives][:printed_output] = _PRFT_LOCAL[:additional][:printed_output]
            _PRFT_LOCAL[:primitives][:iterator] = _PRFT_LOCAL[:additional][:iterator]
        else # TODO ASSUMES MAIN RANK IS 0
            _PRFT_LOCAL[:primitives][:median_time_MPI] = Dict{Int64, Number}()
            _PRFT_LOCAL[:primitives][:min_time_MPI] = Dict{Int64, Number}()
            _PRFT_LOCAL[:primitives][:autoflop_MPI] = Dict{Int64, Number}()
            _PRFT_LOCAL[:primitives][:median_time_MPI][0] = median(_PRFT_LOCAL[:suite]).time / 1e9
            _PRFT_LOCAL[:primitives][:min_time_MPI][0] = minimum(_PRFT_LOCAL[:suite]).time / 1e9
            _PRFT_LOCAL[:primitives][:autoflop_MPI][0] = _PRFT_LOCAL[:additional][:autoflop]
 
            MPICommunicateResults(_PRFT_LOCAL[:primitives][:median_time_MPI], _PRFT_GLOBAL[:comm_size], 0)
            MPICommunicateResults(_PRFT_LOCAL[:primitives][:min_time_MPI], _PRFT_GLOBAL[:comm_size], 0)
            MPICommunicateResults(_PRFT_LOCAL[:primitives][:autoflop_MPI], _PRFT_GLOBAL[:comm_size], 0)

            # Reduction of all values
            _PRFT_LOCAL[:primitives][:median_time] = 0
            _PRFT_LOCAL[:primitives][:min_time] = 0
            _PRFT_LOCAL[:primitives][:autoflop] = 0
            for i in 0:(_PRFT_GLOBAL[:comm_size]-1)
                _PRFT_LOCAL[:primitives][:median_time] += _PRFT_LOCAL[:primitives][:median_time_MPI][i]
                _PRFT_LOCAL[:primitives][:min_time] += _PRFT_LOCAL[:primitives][:min_time_MPI][i]
                _PRFT_LOCAL[:primitives][:autoflop] += _PRFT_LOCAL[:primitives][:autoflop_MPI][i]
            end

            # Equal among all ranks
            _PRFT_LOCAL[:primitives][:iterator] = _PRFT_LOCAL[:additional][:iterator]
            # Cannot be collected from other ranks
            _PRFT_LOCAL[:primitives][:ret_value] = _PRFT_LOCAL[:additional][:ret_value]
            _PRFT_LOCAL[:primitives][:printed_output] = _PRFT_LOCAL[:additional][:printed_output]
        end
    end
end
PerfTest.buildPrimitiveMetrics = MPI_buildPrimitiveMetrics

end