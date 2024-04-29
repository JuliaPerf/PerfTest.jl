
using MacroTools
include("structs.jl")

# CONFIG STRUCTURE DEFINITION
# FOR DEFAULTS SEE BELOW COMMENT "DEFAULTCONFIG":
OPTIONAL_Float = Union{Nothing, Float64}


@kwdef mutable struct Struct_Regression_Tolerance
    overperform_percentage::OPTIONAL_Float = nothing
    underperform_percentage::OPTIONAL_Float = nothing
end

@kwdef mutable struct Struct_Regression
    enabled::Bool

    save_failed::Bool

    general_regression_threshold::Struct_Regression_Tolerance


    """
    Can be:
        - :latest    The reference will be the latest saved result
        - :average The reference will be the average of all saved results
    """
    regression_calculation::Symbol
end

@kwdef mutable struct Struct_Metric_Config
    enabled::Bool

    regression_threshold::Struct_Regression_Tolerance
end

@kwdef mutable struct Struct_Metrics
    median_time::Struct_Metric_Config
    min_time::Struct_Metric_Config
    median_memory::Struct_Metric_Config
    min_memory::Struct_Metric_Config
    median_memory_allocs::Struct_Metric_Config
    min_memory_allocs::Struct_Metric_Config
    memory_throughput::Struct_Metric_Config
end

# DEFAULTCONFIG

""" Where the regression tests are saved """
save_folder = ".perftests"

verbose = false

max_saved_results = 10

""" Regression testing configuration """
regression = Struct_Regression(
    enabled = true,

    save_failed = false,

    general_regression_threshold = Struct_Regression_Tolerance(
        overperform_percentage = 1.5,
        underperform_percentage = 0.8
    ),

    regression_calculation = :latest,
)

""" Metrics configuration """
metrics = Struct_Metrics(
    median_time = Struct_Metric_Config(
        enabled = true,
        regression_threshold = Struct_Regression_Tolerance(),
    ),
    min_time=Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Regression_Tolerance(),
    ),
    median_memory = Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Regression_Tolerance(),
    ),
    min_memory=Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Regression_Tolerance(),
    ),
    median_memory_allocs = Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Regression_Tolerance(),
    ),
    min_memory_allocs=Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Regression_Tolerance(),
    ),
    memory_throughput = Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Regression_Tolerance(),
    )
)

# MACROS
# Perftest_config macro, used to set customised configuration
macro perftest_config(expr)
    # It deletes the contents and does nothing since this macro wont
    # be evaluated during performance testing but during functional testing
    # The contents are used by parsing them during the test translation
    return nothing
end

# AST MODIFIERS
# Perftest_config AST Manipulation
function perftestConfigEnter(expr :: Expr, context :: Context)::Expr
    block = escCaptureGetblock(expr, Symbol("@perftest_config"))

    # TODO Enable environment flag
    # context.inside_config = true

    eval(block)

    return quote
	      nothing
    end
end

function perftestConfigExit(_ :: Expr, context :: Context)::Expr
    # TODO
    # Disable environment flag
    context.inside_config = false

    return quote
	      nothing
    end
end

function perftestConfigParseField(expr :: Expr, context::Context)::Expr
    #TODO
end
