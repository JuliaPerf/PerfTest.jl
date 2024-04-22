using BenchmarkTools

mutable struct DepthRecord
    depth_name::String
    depth_flag::Bool

    DepthRecord(name) = new(name, false)
end

mutable struct ASTWalkDepthRecord
    depth_name::Union{String,Expr}
    depth_test_count::Int
    on_for::Union{Nothing, Pair{Any, Any}}

    ASTWalkDepthRecord(name) = new(name, 0, nothing)
end

struct FloatRange
    left::Float64
    right::Float64
    center::Float64

    FloatRange(left, right, center) = right >= center >= left ? new(left, right, center) : error("Invalid float range")
end

"""
  Saves data needed during one specific execution of the test generation process.
"""
mutable struct Context
    depth::AbstractArray
    test_number::Integer
    original_file_path::AbstractString
    inside_target::Bool

    test_tree_expr_builder::AbstractArray

    Context() = new([],0,"",false,[])
end



"""
  Used by the tree traverser to check for expressions that match "condition",
  if they do then "modifier" will be applied to the expression.
"""
struct ASTRule
    condition::Function
    modifier::Function
end




### AUXILIARY PROCEDURES
## FloatRange

function symmetricFloatRange(center, offset)
    return FloatRange(center - offset, center + offset, center)
end

function inRange(range::FloatRange, x::Float64)
    return x >= range.left && x <= range.right ? true : false
end

## DepthRecord
# Auxiliar by index Dict access function
function by_index(dict::Union{Dict,BenchmarkGroup}, idx::Vector{DepthRecord})
    e = dict
    for idx_elem in idx
        e = Expr(:ref, e, idx_elem.depth_name)
    end

    return eval(e)
end

## Auxiliar methods
"""
  Runs over an array of expressions trying to match the desired one.
  If not found returns "Nothing".

  "sym" should follow the MacroTools nomenclature for the @capture macro
"""
function meta_get(expr_array :: AbstractVector, sym :: Symbol)

    for expr in expr_array
        if eval(:(@capture($(:($expr)), $sym)))
            return expr
        end
    end

    return Nothing
end


function meta_get_string(expr_array::AbstractVector)

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
