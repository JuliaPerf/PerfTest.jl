
# `std` is brought into scope via `using BenchmarkTools` at the top of src/PerfTest.jl
# (BenchmarkTools re-exports it) — Statistics itself is not a declared dependency.

"""
Minimum number of underlying raw samples required before a computed variance is
shown to the user (rather than merely computed and gated off). Below this, PerfTest
treats the population as too small for the standard-error estimate to be meaningful.
"""
const MIN_VARIANCE_SAMPLES = 30

"""
A scalar value paired with the standard error of the mean (`sem`) and the raw
sample count (`n`) that backed it. Arithmetic on `SampledValue`s propagates `sem`
through ordinary Julia operator dispatch (absolute errors add in quadrature for
+/-, relative errors add in quadrature for */÷), so formulas built from
`transformFormula`/`SBMID` (which splice plain Julia arithmetic around resolved
symbols) get variance propagation without any changes to the AST-rewriting
machinery itself. A plain `Real` promotes to a zero-variance `SampledValue` with
`n = typemax(Int)`, so it never becomes the bottleneck of a `min(a.n, b.n)`
combination.
"""
struct SampledValue{N<:Real} <: Real
    value :: N
    sem   :: N
    n     :: Int
end

function SampledValue(samples::AbstractVector{<:Real}, center::Real)
    n = length(samples)
    s = n >= 2 ? std(samples) / sqrt(n) : zero(float(center))
    v, sv = promote(float(center), float(s))
    return SampledValue(v, sv, n)
end

Base.promote_rule(::Type{SampledValue{N}}, ::Type{M}) where {N<:Real,M<:Real} = SampledValue{promote_type(N,M)}
Base.convert(::Type{SampledValue{N}}, x::Real) where {N<:Real} = SampledValue(convert(N, x), zero(N), typemax(Int))
Base.convert(::Type{SampledValue{N}}, x::SampledValue) where {N<:Real} = SampledValue(convert(N, x.value), convert(N, x.sem), x.n)
Base.float(x::SampledValue) = SampledValue(float(x.value), float(x.sem), x.n)
Base.zero(::Type{SampledValue{N}}) where {N} = SampledValue(zero(N), zero(N), typemax(Int))
Base.zero(x::SampledValue) = zero(typeof(x))
Base.one(::Type{SampledValue{N}}) where {N} = SampledValue(one(N), zero(N), typemax(Int))

Base.show(io::IO, x::SampledValue) = print(io, x.value, " ± ", x.sem, " (n=", x.n, ")")

# Comparisons intentionally ignore `sem`/`n` — needed so @perfcompare formulas like
# `:median_time < 0.05` keep working unchanged when :median_time resolves to a SampledValue.
Base.:(==)(a::SampledValue, b::SampledValue) = a.value == b.value
Base.isless(a::SampledValue, b::SampledValue) = isless(a.value, b.value)
Base.:<(a::SampledValue, b::SampledValue) = isless(a, b)
Base.:<=(a::SampledValue, b::SampledValue) = a.value <= b.value
Base.:>(a::SampledValue, b::SampledValue) = b < a
Base.:>=(a::SampledValue, b::SampledValue) = b <= a

_safe(x::Real) = isfinite(x)

_quad(a::Real, b::Real) = (_safe(a) && _safe(b)) ? sqrt(a^2 + b^2) : oftype(float(a), NaN)

function _relquad(a::SampledValue, b::SampledValue)
    ra = (!_safe(a.sem)) ? NaN : (iszero(a.value) ? (iszero(a.sem) ? 0.0 : NaN) : a.sem / abs(a.value))
    rb = (!_safe(b.sem)) ? NaN : (iszero(b.value) ? (iszero(b.sem) ? 0.0 : NaN) : b.sem / abs(b.value))
    return (isnan(ra) || isnan(rb)) ? NaN : sqrt(ra^2 + rb^2)
end

function Base.:+(a::SampledValue, b::SampledValue)
    SampledValue(a.value + b.value, _quad(a.sem, b.sem), min(a.n, b.n))
end
function Base.:-(a::SampledValue, b::SampledValue)
    SampledValue(a.value - b.value, _quad(a.sem, b.sem), min(a.n, b.n))
end
Base.:-(a::SampledValue) = SampledValue(-a.value, a.sem, a.n)
Base.:+(a::SampledValue) = a

function Base.:*(a::SampledValue, b::SampledValue)
    v = a.value * b.value
    r = _relquad(a, b)
    SampledValue(v, isnan(r) ? oftype(float(v), NaN) : r * abs(v), min(a.n, b.n))
end
function Base.:/(a::SampledValue, b::SampledValue)
    if iszero(b.value)
        nanv = oftype(float(a.value), NaN)
        return SampledValue(nanv, nanv, min(a.n, b.n))
    end
    v = a.value / b.value
    r = _relquad(a, b)
    SampledValue(v, isnan(r) ? oftype(float(v), NaN) : r * abs(v), min(a.n, b.n))
end
