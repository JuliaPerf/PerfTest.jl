module PerfTest

__precompile__(false) # Temporary workaround to avoid error

export @perftest, @on_perftest_exec, @on_perftest_ignore, @perftest_config,
    @define_eff_memory_throughput, @define_metric, @roofline

using MacroTools
include("structs.jl")
include("auxiliar.jl")
include("macros.jl")

include("config.jl")

include("perftest/structs.jl")
include("perftest/data_handling.jl")

include("benchmarking.jl")

include("prints.jl")

include("metrics.jl")

include("methodologies/regression.jl")
include("methodologies/effective_memory_throughput.jl")
include("methodologies/roofline.jl")

include("prefix.jl")
include("suffix.jl")
include("rules.jl")


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
                #perftest_scope_assignment_macro_rule,
                #perftest_dot_interpolation_rule,
                #perftest_scope_arg_macro_rule,
                #perftest_scope_vecf_arg_macro_rule,
                #perftest_begin_macro_rule,
                #perftest_end_macro_rule,

                back_macro_rule,
                prefix_macro_rule,

                config_macro_rule,

                on_perftest_exec_rule,
                on_perftest_ignore_rule,

                define_memory_throughput_rule,
                define_metric_rule,
                auxiliary_metric_rule,

                roofline_macro_rule,
                ]


# Main transform routine

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
            if rule.condition(x)
                return rule.modifier(x, context)
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

    global ctx = Context()
    ctx.original_file_path = path

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

    return MacroTools.prettify(module_full)
end

transform = treeRun


end # module perftest
