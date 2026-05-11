#using MPI
using Test,PerfTest

@perftest_config "
[regression]
enabled = false
[general]
verbose = 3
"

@testset "MPI Mem bandwidth" begin

    @testset "This should pass" begin
        @on_perftest_exec begin
            s = _PRFT_GLOBALS.builtins[:MEM_BENCH_SDAXPY]
        end

        @define_metric name = "space" units = "Bytes" begin
            s
        end
        time = 0.1

        @define_eff_memory_throughput ratio = 0.97 mem_benchmark="MEM_BENCH_SDAXPY" begin
            :space
        end
        @perftest samples = 5 sleep(time)
    end
end