##-------------------------------------------------------------------------------------##
# Composite type serialization

# Reconstruct a value knowing the expected Julia type `T`.
deserialize_value(x, ::Type{T}) where {T} = _deserialize(x, T)

# Primitive passthrough.
_deserialize(x, ::Type{T}) where {T<:Union{Nothing,Bool,Number,AbstractString,Symbol}} = x
_deserialize(x::Nothing, ::Type{<:Union{Nothing, T}}) where {T} = nothing

# Union with Nothing: dispatch on whether x is nothing.
function _deserialize(x, ::Type{Union{Nothing, T}}) where {T}
    x === nothing ? nothing : _deserialize(x, T)
end

# Vectors: recurse using the element type.
function _deserialize(x::AbstractVector, ::Type{<:AbstractVector{E}}) where {E}
    return E[_deserialize(e, E) for e in x]
end
_deserialize(x::AbstractVector, ::Type{Vector{Any}}) = Any[_deserialize_auto(e) for e in x]

# Dicts: recurse on values with the declared value type.
function _deserialize(x::AbstractDict, ::Type{<:AbstractDict{K,V}}) where {K,V}
    out = Dict{K,V}()
    for (k, v) in x
        out[k] = _deserialize(v, V)
    end
    return out
end

# Pair reconstruction.
function _deserialize(x::AbstractDict, ::Type{Pair{A,B}}) where {A,B}
    return _deserialize(x["first"], A) => _deserialize(x["second"], B)
end

# Struct reconstruction: read TYPE_KEY, look up concrete type, recurse per-field.
function _deserialize(x::AbstractDict, ::Type{T}) where {T}
    # Allow abstract target types — resolve via TYPE_KEY if present.
    concrete = if haskey(x, TYPE_KEY) && haskey(TYPE_REGISTRY, x[TYPE_KEY])
        TYPE_REGISTRY[x[TYPE_KEY]]
    else
        T
    end
    isstructtype(concrete) || error("Cannot rebuild non-struct type $concrete")

    args = Any[]
    for (fname, ftype) in zip(fieldnames(concrete), fieldtypes(concrete))
        key = string(fname)
        if haskey(x, key)
            push!(args, _deserialize(x[key], ftype))
        else
            # Missing field — rely on @kwdef default via kwarg constructor.
            return _kwdef_construct(concrete, x)
        end
    end
    return concrete(args...)
end

# Fallback when we have no type hint (e.g. Dict{Symbol, Any} values).
function _deserialize_auto(x)
    if x isa AbstractDict && haskey(x, TYPE_KEY)
        tname = x[TYPE_KEY]
        if tname == "Pair"
            return _deserialize_auto(x["first"]) => _deserialize_auto(x["second"])
        elseif haskey(TYPE_REGISTRY, tname)
            return _deserialize(x, TYPE_REGISTRY[tname])
        end
    end
    return x
end

# Use @kwdef's keyword constructor when fields are missing (forward-compat).
function _kwdef_construct(::Type{T}, x::AbstractDict) where {T}
    kwargs = Dict{Symbol,Any}()
    for (fname, ftype) in zip(fieldnames(T), fieldtypes(T))
        if haskey(x, string(fname))
            kwargs[fname] = _deserialize(x[string(fname)], ftype)
        end
    end
    return T(; kwargs...)
end

##-------------------------------------------------------------------------------------##
# Root method

function deserialize_root(d::AbstractDict, ::Type{T}) where {T}
    haskey(d, VERSION_KEY) || error("Missing version key in serialized test results, delete the test result file.")
    d = apply_migrations(d)
    return _deserialize(d, T)
end
