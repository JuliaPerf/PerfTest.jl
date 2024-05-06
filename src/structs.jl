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

struct CustomMetric
    name::AbstractString
    calculation::Expr

    # Some methodologies will seek specific requirements to accept a metric
    flags::Set{Symbol}
end

"""
  Saves important state information when going through the AST of an expression.
"""
mutable struct Context
    # To register the current testset tree depth
    depth::AbstractArray
    # For name generation
    test_number::Integer
    # Useful data:
    original_file_path::AbstractString

    # Used to detect if the AST walk is in a specific region where rules behave
    # differently
    env_flags::EnvironmentFlags

    # To build the expression that holds new testsets and the metrics
    test_tree_expr_builder::AbstractArray

    # Expression to add the globally defined custom metrics
    custom_metrics::Expr
    # Used to add code before a test once, used by locally defined metrics
    local_injection::Expr

    Context() = new([], 0, "", EnvironmentFlags(), [], :(begin end), :(begin end))
end


"""
  Used by the tree traverser to check for expressions that match "condition",
  if they do then "modifier" will be applied to the expression.
"""
struct ASTRule
    condition::Function
    modifier::Function
end


