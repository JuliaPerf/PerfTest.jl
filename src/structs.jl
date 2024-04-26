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
mutable struct EnvironmentFlags
    inside_target::Bool
    inside_config::Bool

    EnvironmentFlags() = new(false, false)
end

mutable struct Context
    depth::AbstractArray
    test_number::Integer
    original_file_path::AbstractString

    env_flags::EnvironmentFlags

    test_tree_expr_builder::AbstractArray

    Context() = new([],0,"", EnvironmentFlags(),[])
end


"""
  Used by the tree traverser to check for expressions that match "condition",
  if they do then "modifier" will be applied to the expression.
"""
struct ASTRule
    condition::Function
    modifier::Function
end


