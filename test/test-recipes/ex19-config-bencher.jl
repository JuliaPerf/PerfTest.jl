using Test
using PerfTest

# The [bencher] section is read from the configuration file of the directory where the suite executes

@on_perftest_exec begin
    # Records the configuration seen by the executing suite in its working directory
    dumpConfig(name) = open(io -> PerfTest.TOML.print(io, PerfTest.Configuration.CONFIG), "config_$(name).toml", "w")
end

@testset "BENCHER_FILE" begin
    @on_perftest_exec begin
        dumpConfig("BENCHER_FILE")
    end
    @perftest samples = 1 sin(1.0)
end

# Takes priority over the file from here on
@perftest_config "
[bencher]
project_name = 'from_recipe'
"

@on_perftest_exec begin
    dumpConfig("BENCHER_RECIPE")
end
