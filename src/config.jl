
using MacroTools
include("structs.jl")

# CONFIG STRUCTURE DEFINITION
# FOR DEFAULTS SEE BELOW COMMENT "DEFAULTCONFIG":

@kwdef mutable struct Struct_Regression
    enabled::Bool

    save_failed::Bool

    general_regression_threshold::Struct_Tolerance


    """
    Can be:
        - :latest    The reference will be the latest saved result
        - :average The reference will be the average of all saved results
    """
    regression_calculation::Symbol
end

@kwdef mutable struct Struct_Eff_Mem_Throughput
    enabled::Bool
    tolerance::Struct_Tolerance
end

@kwdef mutable struct Struct_Roofline_Config
    enabled::Bool

    autoflops::Bool

    plotting::Bool

    tolerance_around_memcpu_intersection::Struct_Tolerance
end

@kwdef mutable struct Struct_Metric_Config
    enabled::Bool

    regression_threshold::Struct_Tolerance
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

save_test_results = true

verbose = false

max_saved_results = 10

""" MPI, CUDA, ROC options """
# Will be set to true if the MPI is detected, but it can be triggered manually if needed
mpi_enabled = false

# Options:
#   :single
#      just one of the processes will actually test the others just
#      execute the code as many times as neccessary for the test to work
#   :all
#      all processes will execute the test
mpi_test_mode = :single


""" Tested expressions output handling """
suppress_output = true

""" Regression testing configuration """
regression = Struct_Regression(
    enabled = true,

    save_failed = false,

    general_regression_threshold = Struct_Tolerance(
        max_percentage = 1.5,
        min_percentage = 0.8
    ),

    regression_calculation = :latest,
)

effective_memory_throughput = Struct_Eff_Mem_Throughput(
    enabled = true,

    tolerance = Struct_Tolerance(
        min_percentage = 0.0,
        max_percentage = 1.0
    )
)

roofline = Struct_Roofline_Config(
    enabled = true,

    plotting = true,

    autoflops = false,

    tolerance_around_memcpu_intersection = Struct_Tolerance(
        max_percentage = 2.0,
        min_percentage = 0.7
    )
)

""" Metrics configuration """
metrics = Struct_Metrics(
    median_time = Struct_Metric_Config(
        enabled = true,
        regression_threshold = Struct_Tolerance(),
    ),
    min_time=Struct_Metric_Config(
        enabled = true,
        regression_threshold = Struct_Tolerance(),
    ),
    median_memory = Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Tolerance(),
    ),
    min_memory=Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Tolerance(),
    ),
    median_memory_allocs = Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Tolerance(),
    ),
    min_memory_allocs=Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Tolerance(),
    ),
    memory_throughput = Struct_Metric_Config(
        enabled = false,
        regression_threshold = Struct_Tolerance(),
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

# CONFIG UTILS

"""
  A little automatism to jump to defaults if the configuration provided is absent
  Kind can be:
       :regression
"""
function configFallBack(config_element, kind::Symbol)
    if config_element isa Struct_Tolerance
        if kind == :regression
            tol = Struct_Tolerance(
                min_percentage = regression.general_regression_threshold.min_percentage,
                max_percentage = regression.general_regression_threshold.max_percentage
            )
            if !(isnothing(config_element.min_percentage))
                tol.min_percentage = config_element.min_percentage
            end
            if !(isnothing(config_element.max_percentage))
                tol.max_percentage = config_element.max_percentage
            end

            return tol
        else
            error("ConfigFallBack: Unsupported element")
        end
    else
        error("ConfigFallBack: Unsupported element")
    end
end
