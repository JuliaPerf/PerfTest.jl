
##-------------------------------------------------------------------------------------##
# Basic type serialization

# Primitive / leaf types pass through unchanged.
serialize_value(x::Union{Nothing, Bool, Integer, AbstractFloat, AbstractString, Symbol}) = x

# Tuples: serialize element-wise, keep as tuple (JLD2 handles tuples fine).
serialize_value(x::Tuple) = map(serialize_value, x)

# Vectors: recurse.
serialize_value(x::AbstractVector) = Any[serialize_value(e) for e in x]

# Dicts: recurse on values (keys are usually Symbol/String, leave them).
function serialize_value(x::AbstractDict)
    out = Dict{Any, Any}()
    for (k, v) in x
        out[k] = serialize_value(v)
    end
    return out
end

# Pair: serialize both sides.
serialize_value(p::Pair) = Dict(
    TYPE_KEY => "Pair",
    "first"  => serialize_value(p.first),
    "second" => serialize_value(p.second),
)

# Opaque types we don't want to recurse into — store as-is and hope JLD2 keeps up,
# or convert to a neutral representation. For BenchmarkGroup we just pass through.
serialize_value(x::BenchmarkGroup) = x  # consider BenchmarkTools' own serialization

##-------------------------------------------------------------------------------------##
# Composite type serialization

# Generic struct fallback.
function serialize_value(x::T) where {T}
    isstructtype(T) || error("PerfTest-Serialization: Don't know how to serialize $(T)")
    d = Dict{String, Any}(TYPE_KEY => string(nameof(T)))
    for f in fieldnames(T)
        d[string(f)] = serialize_value(getfield(x, f))
    end
    return d
end

##-------------------------------------------------------------------------------------##
# Root method

function serialize_root(obj)
    d = serialize_value(obj)
    d isa AbstractDict || (d = Dict{String,Any}("value" => d))
    d[VERSION_KEY] = CURRENT_VERSION
    return d
end
