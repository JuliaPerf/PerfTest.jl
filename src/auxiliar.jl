include("structs.jl")
include("perftest/structs.jl")
include("config.jl")

# Function that generates a test name if needed
function genTestName!(state::Context)
    v = (last(state.depth).depth_test_count += 1)
    return "Test $v"
end

function testsetUpdate!(state::Context, name::String)
    push!(state.depth, ASTWalkDepthRecord(name))
end

### EXPRESSION LOADER
function loadFileAsExpr(path ::AbstractString)
    file = open(path, "r")
    str = read(file, String)
    return Meta.parse("begin $str end")
end

### EXPRESSION PRINTER
function saveExprAsFile(expr::Expr, path = "out.jl" :: AbstractString)

    #Get the module
    if expr.head == :toplevel
        open(path, "w") do file
            write(file, string(expr.args[1]))
        end
    else
        @error "Malformed perftest expression on save_expr_as_file."
    end

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


# WHEN MACROTOOLS CAPTURE GIVES PROBLEMS
# Returns whatever comes after the macrocall
function captureMacro(expr,
                       macro_symbol,
                       return_ast::Base.RefValue{Vector{Any}}) :: Bool

    return_ast[] = []
    if isa(expr, Expr) && expr.head == :macrocall
        if expr.args[1] == macro_symbol
            for arg in [expr.args[i] for i in 2:length(expr.args)]
                push!(return_ast[], arg)
            end
            return true
        else
            return false
        end
    else
        return false
    end
end

# Gets the first block expression from an array of expressions
function getBlock(expr_vec::Vector)::Union{Nothing, Expr}

    for expr in expr_vec
        if isa(expr, Expr) && expr.head == :block
            return expr
        end
    end
    return nothing
end

function escCaptureGetblock(input, macro_symbol)
    return_ast = Ref([])
    captureMacro(input, macro_symbol, return_ast)
    val = getBlock(return_ast[])
    return val
end

function escCapture(input, macro_symbol)
    return_ast = Ref([])
    bool = captureMacro(input, macro_symbol, return_ast)
    return bool
end


"""
  Runs over an array of expressions trying to match the desired one.
  If not found returns "Nothing".

  "sym" should follow the MacroTools nomenclature for the @capture macro
"""
function metaGet(expr_array :: AbstractVector, sym :: Symbol)

    for expr in expr_array
        if eval(:(@capture($(:($expr)), $sym)))
            return expr
        end
    end

    return Nothing
end


function metaGetString(expr_array::AbstractVector)

    for expr in expr_array
        print(typeof(expr))
        if typeof(expr) == String
            return expr
        end
        if (typeof(expr) == Expr && expr.head == :string)
            return expr
        end
    end

    return "EMPTY"
end

macro inRange(min, max, value)
    return :($min < $value < $max)
end

