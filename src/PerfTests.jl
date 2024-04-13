module PerfTests

# Possibly redundant
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


function _tree_run(input_expr :: Expr, context :: Context, args...)

    return MacroTools.prewalk(ruleSet(context), input_expr)
end


function tree_run(path :: AbstractString)

    input_expr = load_file_as_expr(path)

    global ctx = Context([], 1, path, [])

    middle = _tree_run(input_expr, ctx)

    full = quote
        $middle
        $(perftextsuffix(ctx))
    end

    # For the using keyword to work
    full.head = :toplevel

    return MacroTools.prettify(full)
end


end # module perftests
