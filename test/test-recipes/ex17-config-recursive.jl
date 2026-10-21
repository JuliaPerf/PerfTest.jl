using Test
using PerfTest

@perftest_config "
[general]
max_saved_results = 11
"

@on_perftest_exec begin
    # Records the configuration seen by the executing suite in its working directory
    dumpConfig(name) = open(io -> PerfTest.TOML.print(io, PerfTest.Configuration.CONFIG), "config_$(name).toml", "w")
end

@testset "OUTER" begin
    @on_perftest_exec begin
        dumpConfig("BEFORE")
    end
    @perftest samples = 1 sin(1.0)

    # Its configuration must apply only to its part of the suite
    include("ex17-config-recursive-inner.jl")

    @testset "AFTER" begin
        @on_perftest_exec begin
            dumpConfig("AFTER")
        end
        @perftest samples = 1 sin(1.0)
    end
end

@on_perftest_exec begin
    dumpConfig("END")
end
