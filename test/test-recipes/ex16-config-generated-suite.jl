using Test
using PerfTest

# No @perftest_config, the configuration is the one of the perftest_config.toml present at generation

@on_perftest_exec begin
    # Records the configuration seen by the executing suite in its working directory
    dumpConfig(name) = open(io -> PerfTest.TOML.print(io, PerfTest.Configuration.CONFIG), "config_$(name).toml", "w")
end

@testset "GENERATED" begin
    @on_perftest_exec begin
        dumpConfig("GENERATED")
    end
    @perftest samples = 1 sin(1.0)
end
