
# Function that generates a test name if needed
function gen_test_name!(state::Context)
    v = (last(state.depth).depth_test_count += 1)
    return "Test $v"
end

function testset_update!(state::Context, name::String)
    push!(state.depth, ASTWalkDepthRecord(name))
end

### EXPRESSION LOADER
function load_file_as_expr(path ::AbstractString)
    file = open(path, "r")
    str = read(file, String)
    return Meta.parse("begin $str end")
end

## Pops expr block or quote and returns array of nested expressions
function removeBlock(expr::Expr)::Vector
    result = []

    if expr.head == :block || expr.head == :quote
        for arg in expr.args
            push!(result, arg)
        end
    else
        push!(result, expr)
    end

    return result
end


### Useful to move expressions to the toplevel
function unblockAndConcat(exprs::Vector{Expr})::Expr

    result = Expr(:toplevel)

    for expr in exprs
        args = removeBlock(expr)
        for arg in args
            push!(result.args, arg)
        end
    end

    return result
end


### Useful to correct operations limited by the tree walking
# Will remove quote blocks inside the main block without recursion and push
# their expressions into the main block
function popQuoteBlocks(expr::Expr)::Expr
    result = []

    if expr.head == :block || expr.head == :quote
        for arg in expr.args
            if typeof(arg) == Expr && arg.head == :quote
                # Pop quote
                for quotearg in arg.args
                    push!(result, quotearg)
                end
            else
                push!(result, arg)
            end
        end

        return Expr(expr.head, result...)
    else
        return expr
    end
end


function flattenedInterpolation(outside_expr::Expr,
    inside_expr::Expr,
    substitution_token::Symbol)::Expr

    result = []

    if outside_expr.head == :block || outside_expr.head == :quote
        for arg in outside_expr.args
            if arg == substitution_token
                # Inject inside expression
                for inside_arg in inside_expr.args
                    push!(result, inside_arg)
                end
            else
                push!(result, arg)
            end
        end

        return Expr(outside_expr.head, result...)
    else
        error("Invalid argument for flattenedInterpolation")
    end
end

# WARNING Unused Recursive
function trimNothings(expr::Any)::Expr
    # If block then run over args and delete nothings
    if typeof(expr) == Expr && (expr.head == :block || expr.head == :quote)
        newargs = []
        for arg in expr.args
            if typeof(arg) != Nothing
                push!(newargs, trimNothings(arg))
            end
        end
        return Expr(expr.head, newargs...)
    else
        # Recursion tail
        return expr
    end
end
