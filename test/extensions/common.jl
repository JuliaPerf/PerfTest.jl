# Helpers shared by the extension test files, see runtests.jl

using Test
using PerfTest

# Every file based case runs in a fresh temporary directory, so no configuration, logs or results are left behind
intempdir(f) = mktempdir(dir -> cd(f, dir))

# Messages of the parse errors of the last transform
parseErrors() = [e.name for e in PerfTest.ctx._global.errors.errors]

# A recipe with `lines` inside its testset, before its @perftest
inTestset(lines...; target = "sin(1.0)") =
    "using Test, PerfTest\n@testset \"T\" begin\n" * join(lines, "\n") * "\n    @perftest samples = 1 $target\nend\n"

# The suite generated from a recipe with `lines` inside its testset
function transformed(lines...; kwargs...)
    write("recipe.jl", inTestset(lines...; kwargs...))
    return PerfTest.transform("recipe.jl")
end

# Whether the transform rejects a recipe with `lines`, the formulas of the extensions throw instead of reporting a
# parse error, either is a rejection
function rejected(lines...)
    try
        transformed(lines...)
        return PerfTest.num_errors() > 0
    catch
        return true
    end
end

# A @define_metric of the formula `formula`, named `name`
metric(name, formula) = "    @define_metric name = \"$name\" units = \"\" begin\n        $formula\n    end"

# The group lists given to PerfTest.perfmon in a suite, one per @perftest
function perfmonGroups(ex)
    found = Vector{String}[]
    walk(x) = if x isa Expr
        if x.head == :call && x.args[1] == :(PerfTest.perfmon)
            push!(found, only(filter(a -> a isa Vector{String}, x.args)))
        end
        foreach(walk, x.args)
    end
    walk(ex)
    return found
end

# Number of errored tests in the output of a suite, it exits successfully even when some errored
function suiteErrors(output)
    m = match(r"Aggregate Results: \d+ PASSED, \d+ FAILED, (\d+) ERRORS", output)
    return m === nothing ? 0 : parse(Int, m.captures[1])
end

# Transforms the recipe `file` of the working directory, saves its suite and executes it in a fresh process, as
# runperftests does. Returns whether everything succeeded (no test of the suite errored either) and the output, which
# is printed on failure
function runRecipe(file)
    output = try
        expr = PerfTest.transform(file)
        if PerfTest.num_errors() > 0
            "Parse errors: $(join(parseErrors(), "\n"))"
        else
            suite = replace(file, r"\.jl$" => "_perfsuite.jl")
            PerfTest.saveExprAsFile(expr, suite)
            out = IOBuffer()
            cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $suite`; dir=pwd())
            ok = success(pipeline(cmd; stdout=out, stderr=out))
            output = String(take!(out))
            ok && suiteErrors(output) == 0 ? nothing : output
        end
    catch e
        "The transform threw: $(sprint(showerror, e, catch_backtrace()))"
    end
    output === nothing && return true, ""
    println(output)
    return false, output
end

# The test results saved by the last execution of the recipe `file` of the working directory
savedTests(file) = PerfTest.retrievePerfTests(".perftests/$(file)_PERFORMANCE.JLD2"; get=:tests)

# The value of the metric `sym` of a saved test result
metricValue(test, sym) = test.metrics[sym].value

# Marks a set of tests as skipped on this machine, with the reason
function skipped(reason)
    @info "Skipped: $reason"
    @test_skip false
end
