using Test
using PerfTest

@perftest_config "
[memory_bandwidth]
default_threshold = 0.25
[regression]
default_threshold = 2.5
"

@testset "INNER" begin
    @define_eff_memory_throughput begin
        1.0
    end
    @perftest sum(1:10)
end
