using Test
using PerfTest

# Only known when the generated suite executes
tag = string("run", 1 + 1)

@perftest_config "
[general]
save_folder = 'results_$(tag)'
max_saved_results = 4
[regression]
dedicated_reference_file = 'ref_$(tag).JLD2'
"

# Must not carry the interpolated keys above into the suite
@perftest_config "
[roofline]
default_threshold = 0.3
"

@on_perftest_exec begin
    # Records the configuration seen by the executing suite in its working directory
    dumpConfig(name) = open(io -> PerfTest.TOML.print(io, PerfTest.Configuration.CONFIG), "config_$(name).toml", "w")
end

@testset "INTERPOLATION" begin
    @on_perftest_exec begin
        dumpConfig("INTERPOLATION")
    end
    @perftest samples = 1 sin(1.0)
end
