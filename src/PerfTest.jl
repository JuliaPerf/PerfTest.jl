module PerfTest

export @perftest, @on_perftest_exec, @on_perftest_ignore, @perftest_config,
    @define_eff_memory_throughput, @define_metric, @roofline, @define_test_metric, magnitudeAdjust

using MacroTools
using MLStyle.Modules.AST
using Configurations
using Printf

using BenchmarkTools

var"@capture" = MacroTools.var"@capture"

### PARSING TIME

# Data structures used in the parse and transform procedures
include("datastruct.jl")

# Structures and defaults of the package configuration
include("configuration.jl")     # NOTE

# Formatting
include("printing.jl")

# General validation
include("validation/errors.jl")  #DONE
include("validation/formula.jl") #DONE
include("validation/macro.jl")   #DONE

# Macro definitions
include("macros/perftest.jl")
include("macros/roofline.jl")
include("macros/exec_ignore.jl")
include("macros/customs.jl")

# Machine features extraction
include("machine_benchmarking.jl") #1ST DONE

# Metric transformation
include("metrics/primitives.jl") #DONE
include("metrics/custom.jl")    #DONE

# Methodology transformation
include("methodologies/regression.jl") #DONE
include("methodologies/manual.jl")
include("methodologies/mem_bandwidth.jl")
include("methodologies/roofline.jl") #DONE

include("prefix.jl") # Basic DONE
include("suffix.jl") # DONE

# Rules of the ruleset
include("parsing/hierarchy_transform_test_region.jl") #DONE
include("parsing/hierarchy_transform_benchmark_region.jl") #DONE
include("parsing/target_transform.jl")    #DONE
include("parsing/formula_transform.jl")   #DONE
include("parsing/rules.jl")               #DONE

# Additional
include("auxiliar.jl")

# Functions used by the generated suites
include("generated_space_functions/structs.jl")
include("generated_space_functions/printing.jl")
include("generated_space_functions/data_handling.jl")
include("generated_space_functions/units.jl")

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
    test_skip_macro_rule, perftest_macro_rule, back_macro_rule,
    prefix_macro_rule,
    config_macro_rule,
    on_perftest_exec_rule,
    on_perftest_ignore_rule,
    define_memory_throughput_rule,
    define_metric_rule,
    auxiliary_metric_rule, roofline_macro_rule,
    raw_macro_rule,
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



"""
This method implements the transformation that converts a recipe script into a fully-fledged testing suite.
The function will return a Julia expression with the resulting performance testing suite. This can be then executed or saved in a file for later usage.
# Arguments
 - `path` the path of the script to be transformed.

"""
function treeRun(path :: AbstractString)

    # Load original
    input_expr = loadFileAsExpr(path)

    global ctx = Context(GlobalContext(path, VecErrorCollection(), formula_symbols))
    ctx._global.original_file_path = path

    # Run through AST and build new expressions
    middle = _treeRun(input_expr, ctx)

    # Assemble
    full = quote
            a
            b
    end

    full = flattenedInterpolation(full, middle, :a)
    full = flattenedInterpolation(full, perftextsuffix(ctx), :b)

    # Mount inside a module environment
    module_full = Expr(:toplevel,
                       Expr(:module, true, :__PERFTEST__,
                            Expr(:block, full.args...)))

    if num_errors(ctx._global.errors) > 0
        printErrors(ctx._global.errors)
        return quote @warn "Parsing failed" end
    end

    return MacroTools.prettify(module_full)
end



transform = treeRun


include("execution.jl")

end
