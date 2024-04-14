module PerfTests

# Possibly redundant
using MacroTools: blockunify
include("structs.jl")
include("auxiliar.jl")
include("prints.jl")
include("macros.jl")

include("prefix.jl")
include("suffix.jl")
include("rules.jl")

# Active rules
rules = ASTRule[testset_macro_rule,
                test_macro_rule,
                perftest_macro_rule,
                back_macro_rule,
                prefix_macro_rule]


# Main transform routine

function ruleSet(context :: Context)
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


function _treeRun(input_expr :: Expr, context :: Context, args...)

    return MacroTools.prewalk(ruleSet(context), input_expr)
end



function treeRun(path :: AbstractString)

    # Load original
    input_expr = load_file_as_expr(path)

    global ctx = Context([], 1, path, [])

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

    return  module_full # MacroTools.prettify(module_full)
end


end # module perftests
