using Test
using PerfTest

@perftest_config "
[general]
recursive = true
[memory_bandwidth]
default_threshold = 0.75
"

@testset "BEFORE" begin
    @define_eff_memory_throughput begin
        1.0
    end
    @perftest sum(1:10)
end

# Its configuration must apply only inside it
include("ex15-recursive-config-inner.jl")

@testset "AFTER" begin
    @define_eff_memory_throughput begin
        1.0
    end
    @perftest sum(1:10)
end
