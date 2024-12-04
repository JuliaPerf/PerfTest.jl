
using Configurations, YAML

@option "BoundaryConfig" struct BoundConfig
    worse::Float64 = 0.2
    better::Maybe{Float64} = nothing
end

@option "RegressionConfig" struct RegrConfig
    enabled::Bool = true
    save_failed_tests::Bool = false

    general_boundary::BoundConfig
    custom_metrics_boundary::Maybe{BoundConfig} = nothing
end

@option "FixedThresholdConfig" struct FTConfig
    enabled::Bool = true

    general_boundary::BoundConfig
    custom_metrics_boundary::Maybe{BoundConfig} = nothing
end

@option "RooflineConfig" struct RooflineConfig
    enabled::Bool = true
    full_roofline::Bool = true
    plotting::Bool = true

    boundary::BoundConfig = BoundConfig(0.0, nothing)
end

@option "MachineConfig" struct MachineConfig

    memtest_buffer_size :: Maybe{Int}
end

@option "GeneralConfig" struct GeneralConfig
    autoflops::Bool = true

    recursive::Bool = true

    save_folder::AbstractString = ".perftests"
    save_test_results::Bool = false
    max_saved_results::Int = 10

    verbose::Bool = true

    suppress_output :: Bool = true

    regression :: RegrConfig = RegrConfig(general_boundary=BoundConfig())
    fixed_threshold :: FTConfig = FTConfig(general_boundary=BoundConfig())
    roofline :: RooflineConfig = RooflineConfig(boundary=BoundConfig())
end

CONFIG = GeneralConfig()


"""
  This function will update the configuration if there is a yaml file in the WD
"""
function tryImportConfig() :: GeneralConfig
    filename = "./perftest_config.yaml"

    if isfile(filename)
        c = nothing
        try
            c = from_dict(GeneralConfig, YAML.load_file(filename))
        catch
            @debug "No config file found, default pakage config will be used"
            return CONFIG
        end
        @debug "Config file found, applying changes"
        return c
    end
end

"""
  Will create a file on the WD that holds the current configuration
"""
function generateConfigFile()

    filename = "./perftest_config.yaml"

    if !isfile(filename)
        raw = YAML.dump(to_dict(GeneralConfig, CONFIG))
        open(filename, "w") do file
            write(file, "# Default configuration of the PerfTest package
# ~ == nothing, empty value, used commonly for optional parameters
$raw
")
        end
    end
end
