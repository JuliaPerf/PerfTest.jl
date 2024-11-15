
using Configurations, YAML

@option "BoundaryConfig" struct BoundConfig
    worse::Float64 = 0.2
    better::Union{Nothing,Float64} = nothing
end

@option "RegressionConfig" struct RegrConfig
    enabled::Bool = true
    save_failed_tests::Bool = false

    general_boundary::BoundConfig
    custom_metrics_boundary::Union{Nothing,BoundConfig} = nothing
end

@option "FixedThresholdConfig" struct FTConfig
    enabled::Bool = true

    general_boundary::BoundConfig
    custom_metrics_boundary::Union{Nothing,BoundConfig} = nothing
end

@option "RooflineConfig" struct RooflineConfig
    enabled::Bool = true
    full_roofline::Bool = true
    plotting::Bool = true

    boundary::BoundConfig = BoundConfig(0.0, nothing)
end

@option "GeneralConfig" struct GeneralConfig
    autoflops::Bool = true

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
