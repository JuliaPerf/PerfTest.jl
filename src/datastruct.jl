
"""
Used by the AST walker to check for expressions that match `condition`,
if they do then `modifier` will be applied to the expression.

This is the basic building block of the code transformer, a set of these rules compounds to all the needed manipulations to create the testing suite.

"""
struct ASTRule
    match::Function
    validation::Function
    transformation::Function

    ASTRule(match, validation :: Function, transformation) = new(match, validation, transformation)
    ASTRule(match, macro_params :: Dict, transformation) = new(match, validateMacro(macro_params), transformation)
end

struct MacroParameter
    name :: Symbol
    type :: Type
    param_validation_function :: Function  # Default is to always be valid

    has_default::Bool
    default_value::Any
    mandatory::Bool

    MacroParameter(name, type) = new(name,type, (_...) -> true, false, nothing, false)
    MacroParameter(name, type, f :: Function) = new(name, type, f, false, nothing, false)
    MacroParameter(name, type, mandatory :: Bool) = new(name, type, (_...) -> true, false, nothing, mandatory)
    MacroParameter(name, type, def_val, mandatory) = new(name, type, (_...) -> true, true, def_val, mandatory)
    MacroParameter(name, type, f :: Function, def_val) = new(name, type, f, true, def_val, false)
    MacroParameter(name, type, f :: Function, def_val, mandatory) = new(name, type, f, true, def_val, mandatory)
end

# TODO

struct FloatRange
    left::Float64
    right::Float64
    center::Float64

    FloatRange(left, right, center) = right >= center >= left ? new(left, right, center) : error("Invalid float range")
end


# ERROR

# 0: undefined
# 1X : parsing
# 11 : parameter name
# 12 : parameter type
# 13 : parameter value
struct ParsingErrorInfo
    num :: Int8
    name :: AbstractString
    description :: AbstractString

    ParsingErrorInfo(name) = new(100, name, "")
    ParsingErrorInfo(num, name) = new(100 + num, name, "")
    ParsingErrorInfo(num, name, desc) = new(100 + num, name, desc)
end

abstract type ErrorCollection end

struct VecErrorCollection <: ErrorCollection
    errors::Vector{ParsingErrorInfo}
    loc :: Vector{String}

    VecErrorCollection() = new(ParsingErrorInfo[], String[])
end

ExtendedExpr = Union{QuoteNode,Expr,Symbol,LineNumberNode}

# CONTEXT
@kwdef struct CustomMetric
    name::AbstractString
    units::AbstractString
    formula::Union{ExtendedExpr, Float64}
    symbol::Union{Symbol, Nothing}
    auxiliary::Bool = false
end

@kwdef struct MethodologyParameters
    id::Symbol
    name::AbstractString
    # This sets if the metric will inherit outer scope parameters if they exists or it will override them
    override::Bool
    params::Dict{Symbol, Any}
end


mutable struct DepthEntry
    set_name::AbstractString
    for_loop::Union{Nothing,Pair{ExtendedExpr,ExtendedExpr}}
    test_count::Int
end

mutable struct LocalContext
    depth_record::AbstractArray{DepthEntry}
    # :target
    environment::Set{Symbol}

    custom_metrics::Vector{Vector{CustomMetric}}
    enabled_methodologies::Vector{Vector{MethodologyParameters}}

    LocalContext() = new([], Set{Symbol}(), Vector{CustomMetric}[], Vector{MethodologyParameters}[])
end

mutable struct GlobalContext
    original_file_path::AbstractString

    in_recursion::Bool
    errors::ErrorCollection
    valid_symbols::Set{Symbol}

    GlobalContext(path, errors, valid) = new(path, false, errors, valid)
    GlobalContext(path, errors, valid, _) = new(path, true, errors, valid)
end

"""
In order to perform with the test suite generation, the AST walk needs to keep a context register to integrate features that rely on the scope hierarchy.

"""
mutable struct Context
    _local::LocalContext
    _global::GlobalContext
    test_tree_expr_builder::AbstractArray

    Context(_global::GlobalContext) = new(LocalContext(), _global, [])
end

always_true = (x...) -> true
no_validation = (x...) -> nothing

# Common transform routines
"""
  Returns an empty expresion for any input
"""
empty_expr    = (x...) -> quote end
"""
  Keeps the expression as it it
"""
no_transform  = (x,_,_) -> x
"""
  If validation failed with a false, the transform will abort returning an empty expression.
"""
abort_if_invalid(transform) = (x, ctx, info) -> !(info isa Nothing || !info) ? (transform(x, ctx, true)) : quote end

"""
  Returns a function that will return if its argument (x) is of type "type"
"""
checkType(type :: Type) = (x) -> x isa type

"""
  Constructs an ASTRule that assumes that the expression is automatically valid if matched.
  Thus no validation is done.
"""
validASTRule(match, transform) = ASTRule(
    match,
    no_validation,
    (x, ctx, _) -> transform(x,ctx, nothing)
)

"""
  Constructs an ASTRule that will always match. The onfail function will then be applied.
  Useful to catch a match failure.

# Arguments:
  - onfail : a function that receives a Context argument.
"""
match_failure(onfail) = ASTRule(
    (x...) -> true,
    no_validation,
    (_,ctx,_) -> onfail(ctx)
)

greaterThan0(n :: Number) = n > 0
