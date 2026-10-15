using Test, PerfTest

# Regression fixture: a plain (non-macro) function whose `do`-block body is a
# single tuple-literal statement, e.g. `get!(dict, key) do; (A, B); end`. This
# is the exact shape that `MacroTools.prettify`'s `flatten` pass used to strip
# down to a bare, unparenthesized `Expr(:tuple, A, B)`, which Julia's `Base.show`
# for `:do` expressions then printed as two separate statements instead of one
# tuple, silently changing what the `do`-block returns.
const _cache = IdDict{Symbol,Tuple{Vector{Float64},Vector{Float64}}}()

function fill_cache!(key::Symbol, n::Int)
    (a, b) = get!(_cache, key) do
        (Vector{Float64}(undef, n), Vector{Float64}(undef, n))
    end
    return (a, b)
end

@perftest_config "
[regression]
enabled = false
[general]
verbose = 0
"

@testset "do-block tuple" begin
    @perftest begin
        fill_cache!(:x, 4)
    end
end
