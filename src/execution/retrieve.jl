export retrievePerfTests, inTestSet, hasMetric, hasAuxiliar, hasPrimitive, testNamed, testPassed

"""
    retrievePerfTests(datafile_path; get=:tests, where=(x)->true, execution=:latest)

General-purpose retrieval over a performance-test datafile.

# Arguments
- `datafile_path::AbstractString`: path to a serialized `Perftest_Datafile_Root`.
- `get::Symbol`: what to return. One of:
    - `:tests`          → `Vector{Test_Result}`
    - `:methodologies`  → `Vector{Methodology_Result}`
    - `:testsets`       → `Vector{String}` (fully-qualified testset paths)
- `where::Function`: predicate applied to each candidate element;
  only elements for which it returns `true` are kept.
- `execution::Union{Symbol, Int}`: which execution to consider.
- `pathonly ::Bool` : if true, only return the testset path for each result, instead of the full `Test_Result` or `Methodology_Result`.

# Examples
```julia
tests  = retrievePerfTests("results.dat")
fast   = retrievePerfTests("results.dat"; where = t -> hasMetric(t, :median_time))
passed = retrievePerfTests("results.dat"; where = testPassed)
meths  = retrievePerfTests("results.dat"; get = :methodologies) 

# All predicates:
- `inTestSet(test, "MySuite/MyTest")` → true if `test` is under a testset named "MySuite/MyTest".
- `hasMetric(test, :median_time)` → true if `test` has a metric
- `hasAuxiliar(test, :memory_usage)` → true if `test` has an auxiliar metric
- `hasPrimitive(test, :min_time)` → true if `test` has a primitive
- `testNamed(test, "MyTest")` → true if `test.name == "MyTest"`
- `testPassed(test)` → true if all methodologies of `test` passed
- `methodologyNamed(m, "MyMethodology")` → true if `m.name == "MyMethodology"`
- `methodologyHasMetric(m, "median_time")` → true if `m` has a metric named "median_time"
- `methodologyPassed(m)` → true if all metrics of `m` succeeded
```

"""
function retrievePerfTests(datafile_path::AbstractString;
    get::Symbol = :tests,
    where_pred::Function = _ -> true,
    execution::Union{Symbol, Int} = :latest,
    pathonly::Bool = false)
    root = openDataFile(datafile_path)
    if execution isa Symbol
        if execution == :latest
            suite = root.results[end]
        elseif execution == :all
            suite = root.results
            return [pathonly ? _retrieve(Val(get), s, where_pred)[2] : _retrieve(Val(get), s, where_pred)[1] for s in suite]
        else
            error("Invalid execution argument: $execution. Expected :latest, :all, or a index.")
        end
    else
        try
            suite = root.results[execution]
        catch
            throw(ArgumentError("No execution with timestamp $execution found in datafile."))
        end
    end
    return pathonly ? _retrieve(Val(get), suite, where_pred)[2] : _retrieve(Val(get), suite, where_pred)[1]
end

# Dispatches
_retrieve(::Val{:tests}, suite, pred) = _collect_tests(suite, pred)
_retrieve(::Val{:methodologies}, suite, pred) = _collect_methodologies(suite, pred)
_retrieve(::Val{:testsets}, suite, pred) = _collect_testsets(suite, pred)
function _retrieve(::Val{S}, _, _) where {S}
    throw(ArgumentError("retrievePerfTests: unknown get=:$S. " * "Expected one of :tests, :methodologies, :testsets."))
end


"""
    _walk_perftests(f, perftests, path=String[])

Recursively walk a `perftests` dict, calling `f(test, path)` for every
`Test_Result` leaf, where `path` is the vector of testset names leading to it.
"""
function _walk_perftests(f, perftests::AbstractDict, path::Vector{String} = String[])
    for (name, entry) in perftests
        if entry isa Test_Result
            f(entry, path)
        elseif entry isa AbstractDict
            _walk_perftests(f, entry, vcat(path, String(name)))
        end
    end
end

function _collect_tests(suite::Suite_Execution_Result, pred::Function)
    out = Test_Result[]
    path = String[]
    _walk_perftests(suite.perftests) do test, _path
        _apply(pred, test, _path) && (push!(out, test);push!(path, join(_path, " > ") * " > " * test.name))
    end
    return out, path
end

function _collect_methodologies(suite::Suite_Execution_Result, pred::Function)
    out = Methodology_Result[]
    path = String[]
    _walk_perftests(suite.perftests) do test, _path
        for m in test.methodology_results
            _apply(pred, m, _path) && (push!(out, m);push!(path, join(_path, " > ") * " > " * test.name * " > " * m.name))
        end
    end
    return out, path
end

function _collect_testsets(suite::Suite_Execution_Result, pred::Function)
    seen = Set{String}()
    out  = String[]
    _walk_perftests(suite.perftests) do _test, path
        # Every prefix of the path is a valid testset
        for i in 1:length(path)
            qualified = join(@view(path[1:i]), "/")
            if !(qualified in seen) && pred(qualified)
                push!(seen, qualified)
                push!(out, qualified)
            end
        end
    end
    return out,out
end


# PREDICATES

# Accept 1- or 2-arg predicates transparently
_apply(pred, test, path) = hasmethod(pred, Tuple{Test_Result, Vector{String}}) ?
                           pred(test, path) : pred(test)
#"""
#    inTestSet(test, setname) -> Bool
#
#True if `test` lives under a testset named `setname` (matched against any
#path component, or against the full "a/b/c" path).
#"""
#function inTestSet(test::Test_Result, setname::AbstractString)
    # TODO
#    error("inTestSet requires path info — use the path-aware variant below.")
#end

# Test predicates that don't need path info:
hasMetric(t::Test_Result, key::Symbol)      = haskey(t.metrics, key)
hasAuxiliar(t::Test_Result, key::Symbol)    = haskey(t.auxiliar, key)
hasPrimitive(t::Test_Result, key::Symbol)   = haskey(t.primitives, key)
testNamed(t::Test_Result, name::AbstractString) = t.name == name
testPassed(t::Test_Result) = all([methodologyPassed(m) for m in t.methodology_results])

# Methodology predicates:
methodologyNamed(m::Methodology_Result, name::AbstractString) = m.name == name
methodologyHasMetric(m::Methodology_Result, mname::AbstractString) = any(p -> first(p).name == mname, m.metrics)
methodologyPassed(m::Methodology_Result) = all(p -> last(p).succeeded, m.metrics)