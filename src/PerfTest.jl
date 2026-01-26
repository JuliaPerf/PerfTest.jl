module PerfTest

export @perftest, @on_perftest_exec, @on_perftest_ignore, @perftest_config, @export_vars,
    @define_eff_memory_throughput, @define_metric, @roofline, @define_test_metric, magnitudeAdjust, @perfcompare, @perfcmp

using Test
using MacroTools
using MLStyle.Modules.AST
using Configurations
using Printf

using BenchmarkTools
using STREAMBenchmark
using LinearAlgebra
using CpuId

var"@capture" = MacroTools.var"@capture"

abstract type NormalMode end
struct MPIMode <: NormalMode end

mode = NormalMode


### PARSING TIME

# Data structures used in the parse and transform procedures
include("transform/datastruct.jl")

# Structures and defaults of the package configuration
include("transform/configuration.jl")     # NOTE

# Formatting
include("printing.jl")
include("logs.jl")

# General validation
include("transform/validation/errors.jl")
include("transform/validation/formula.jl")
include("transform/validation/macro.jl")
include("transform/validation/export_vars.jl")

# Metric transformation
include("transform/metrics/primitives.jl")
include("transform/metrics/custom.jl")

# Methodology transformation
include("transform/methodologies/common.jl")
include("transform/methodologies/regression.jl")
include("transform/methodologies/manual.jl")
include("transform/methodologies/mem_bandwidth.jl")
include("transform/methodologies/roofline.jl")

include("transform/prefix.jl")
include("transform/suffix.jl")


# TODO: Separate Macro definitions
include("execution/macros/perftest.jl")
include("execution/macros/perfcompare.jl")
include("execution/macros/roofline.jl")
include("execution/macros/exec_ignore.jl")
include("execution/macros/customs.jl")
include("execution/macros/configuration.jl")

include("execution/structs.jl")
include("execution/testset.jl")


# Machine features extraction
include("execution/machine_benchmarking.jl")


# Rules of the ruleset
include("transform/parsing/hierarchy_transform_test_region.jl")
include("transform/parsing/hierarchy_transform_benchmark_region.jl")
include("transform/parsing/hierarchy_transform.jl")
include("transform/parsing/target_transform.jl")
include("transform/parsing/formula_transform.jl")
include("transform/parsing/rules.jl")

# Additional
include("transform/auxiliar.jl")

# Functions used by the generated suites
include("execution/printing.jl")
include("execution/data_handling.jl")
include("execution/units.jl")
include("execution/misc.jl")

# Bencher Interface
include("bencher/BencherREST.jl")

# Base active rules
rules = ASTRule[testset_macro_rule,
                test_macro_rule,
                test_throws_macro_rule,
                test_logs_macro_rule,
                inferred_macro_rule,
                test_deprecated_macro_rule,
                test_warn_macro_rule,
                test_nowarn_macro_rule,
    test_broken_macro_rule,
    test_skip_macro_rule,
    perftest_macro_rule,
    back_macro_rule,
    prefix_macro_rule,
    suffix_macro_rule,
    config_macro_rule,
    on_perftest_exec_rule,
    on_perftest_ignore_rule,
    define_memory_throughput_rule,
    define_metric_rule,
    define_benchmark_rule,
    export_vars_rule,
    auxiliary_metric_rule, roofline_macro_rule,
    manual_macro_rule,
    recursive_rule
]


# Transform routines in target_transform.jl
perftest_expression_ruleset = [
    perftest_scope_assignment_macro_rule,
    perftest_scope_arg_macro_rule,
    perftest_scope_vecf_arg_macro_rule,
    perftest_dot_interpolation_rule,
]

function parseTarget(expr :: Expr, context::Context)::Expr
    return MacroTools.prewalk(ruleSet(context, perftest_expression_ruleset), expr)
end


"""
This method builds what is known as a rule set. Which is a function that will evaluate if an expression triggers a rule in a set and if that is the case apply the rule modifier. See the ASTRule documentation for more information.

WARNING: the rule set will apply the FIRST rule that matches with the expression, therefore other matches will be ignored

# Arguments
 - `context` the context structure of the tree run, it will be ocassinally used by some rules on the set.
 - `rules` the collection of rules that will belong to the resulting set.
"""
function ruleSet(context::Context, rules :: Vector{ASTRule})
    function _ruleSet(x)
        for rule in rules
            if rule.match(x)
                info = rule.validation(x, context)
                return rule.transformation(x, context, info)
            end
        end
        return x
    end

    return _ruleSet
end


"""
This method gets a input julia expression, and a context register and executes a transformation of the input that converts a recipe script (input) into a fully-fledged testing suite (return value).

# Arguments
 - `input_expr` the recipe/source expression. (internally, a.k.a source code space)
 - `context` a register that will store information useful for the transformation over its run over the AST of the input

"""
function _treeRun(input_expr::Expr, context::Context, args...)

    return MacroTools.prewalk(ruleSet(context, rules), input_expr)
end


ctx = nothing
function setupContext(path :: AbstractString)

    global ctx = Context(GlobalContext(path, VecErrorCollection(), formula_symbols))
    ctx._global.original_file_path = path
end

"""
This method implements the transformation that converts a recipe script into a fully-fledged testing suite.
The function will return a Julia expression with the resulting performance testing suite. This can be then executed or saved in a file for later usage.
# Arguments
 - `path` the path of the script to be transformed.

"""
function treeRun(path::AbstractString)

    @warn "IF YOU SEE THIS PLEASE CONTACT VEGARD@USI.CH AND TELL HIM HE MERGED A DEVELOPMENT VERSION INTO MAIN"
    # Set log directory
    setLogFolder()
    # Clear logs
    #clearLogs()
    # Load configuration
    config = Configuration.load_config()

    if config["general"]["verbose"]
        verboseOutput()
    end

    # Load original
    input_expr = loadFileAsExpr(path)

    setupContext(path)

    # Run through AST and build new expressions
    full = _treeRun(input_expr, ctx)

    # Insert suffix
    #full = MacroTools.postwalk(ruleSet(ctx, [suffix_macro_rule]), full)

    # Mount inside a module environment
    module_full = Expr(:toplevel,
                       Expr(:module, true, :__PERFTEST__,
                            Expr(:block, full.args...)))

    if num_errors(ctx._global.errors) > 0
        printErrors(ctx._global.errors)
        return quote @warn "Parsing failed" end
    end


    if config["general"]["verbose"]
        saveLogFolder()
    end

    return MacroTools.prettify(module_full)
end

"""
  In order for the suite to be MPI aware, this function has to be called. Calling it again will disable this feature.
"""
function toggleMPI()
    if mode == NormalMode
        global mode = MPIMode
    else
        global mode = NormalMode
    end
end

transform = treeRun

MPItransform(path) = (toggleMPI(); transform(path); toggleMPI())

function __init__()
    # Precompile the transformation
    Configuration.load_dummy_config()
    x = PerfTest.transform(joinpath(dirname(pathof(PerfTest)), "transform/dummy.jl"))
end

end
