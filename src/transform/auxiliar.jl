using MacroTools: ismatch

"""
  Function that generates a test name if needed, it is used to name
  test targets to distinguish them if several go in the same testset.
"""
function genTestName!(state::Context)
    v = (last(state.depth).depth_test_count += 1)
    return "Test $v"
end


"""
  Function used to register a new test set in the hierarchy record of the context, where `name` is the name of the test set.
"""
function testsetUpdate!(state::Context, name::String)
    push!(state.depth, ASTWalkDepthRecord(name))
end

"""
  Utility to get an expression from a Julia file stored at `path`
"""
function loadFileAsExpr(path::AbstractString)
    file = open(path, "r")
    str = read(file, String)
    return Meta.parse("begin $str end")
end

"""
  Utility to save an expression (`expr`) to a Julia file stored at `path`

  Requires a :toplevel symbol to be the head of the expression.
"""
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

"""
Pops `expr` which has a head that is :block or :quote and returns array of nested expressions which are the arguments of such head.

"""
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


"""
This function is useful to move expressions to the toplevel when they are enclosed inside a block
"""
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

"""
 Useful to correct operations limited by the tree walking
 Will remove quote blocks inside the main block without recursion and push
 their expressions into the main block
"""
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

"""
This method interpolates the `inside_expr` into `outside_expr` anywhere it finds the token `substitution_token`, which is a symbol. The `outside_expr` has to be a block or a quote block. It has the particularity that it will remove block heads from the `inside_expr` and add the nested elements onto the location where the token it.

# Example:

outside_expr = :(:A; 4)

inside_expr = :(begin 2;3 end)

substitution_token = :A

returns = :(2;3;4)

"""
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

"""
  
"""
function metaGetString(expr_array::AbstractVector)

    for expr in expr_array
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

"""
  From a string, it will divide it by lines and retrieve the ones that match the regular expression provided.
"""
function grepOutput(output :: String, regex_or_string :: Union{Regex, String}):: Vector{SubString{String}}
    lines = split(output, '\n')

    # Remove any empty lines
    cleaned_lines = filter(line -> !isempty(line) && occursin(regex_or_string, line), lines)

    return cleaned_lines
end

"""
From a string (`field`), it will parse the first number it finds as a Float
"""
function getNumber(field :: String)::Float64
    clean = replace(field, r"[^0-9.]" => "")


    return parse(Float64, clean)
end

"""
  Given a string `output`, it will retrieve the first number in the first line that contains the string `string`.
"""
function grepOutputXGetNumber(output :: String, string ::String)::Float64

    return getNumber(String(grepOutput(output, string)[1]))
end

using Pkg

function install_deps()
    Pkg.add("BenchmarkTools")
    Pkg.add("CountFlops")
    Pkg.add("HDF5")
    Pkg.add("STREAMBenchmark")
    Pkg.add("Suppressor")
end
