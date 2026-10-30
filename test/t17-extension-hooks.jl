using Test
using PerfTest

# The hooks of the core the extensions rely on, with mock aliases and a mock LIKWID extension, so no extension package
# or hardware is needed (the extensions themselves are tested by the annex suite, see extensions/runtests.jl)

# Every file based case runs in a fresh temporary directory, so test/perftest_config.toml is never touched
intempdir(f) = mktempdir(dir -> cd(f, dir))

# Executes a saved suite in a fresh process with `dir` as working directory, as runperftests does
function execute(suite, dir)
    out = IOBuffer()
    cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $suite`; dir=dir)
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    return ok, String(take!(out))
end

# A @define_metric of the formula `formula`, named `name`
metric(name, formula) = "    @define_metric name = \"$name\" units = \"\" begin\n        $formula\n    end"

# A recipe with `lines` inside its testset, before its @perftest
inTestset(lines...) = "using Test, PerfTest\n@testset \"T\" begin\n" * join(lines, "\n") * "\n    @perftest samples = 3 sin(1.0)\nend\n"

# The group lists given to PerfTest.perfmon in a suite, one per @perftest in order
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

# An alias as an extension defines them, only in this process
PerfTest.newSymbols(::Val{:mock_double_time}) = properties -> :(2 * test_res.primitives[:median_time])

@testset "Extension hooks - an alias is resolved when the recipe is transformed" begin
    intempdir() do
        write("recipe.jl", inTestset(metric("dt", ":mock_double_time")))
        suite = abspath("recipe_perfsuite.jl")
        PerfTest.saveExprAsFile(PerfTest.transform("recipe.jl"), suite)
        @test PerfTest.num_errors() == 0

        # The suite executes in a process without the alias, its formula is already in it
        ok, output = execute(suite, pwd())
        @test ok
        @test occursin(r"Aggregate Results: \d+ PASSED, \d+ FAILED, 0 ERRORS", output)
        test = only(PerfTest.retrievePerfTests(".perftests/recipe.jl_PERFORMANCE.JLD2"))
        @test test.metrics[:dt].value ≈ 2 * test.primitives[:median_time]
    end
end

@testset "Extension hooks - an unknown symbol is reported when the suite executes" begin
    intempdir() do
        write("recipe.jl", inTestset(metric("m", ":no_such_metric")))
        suite = abspath("recipe_perfsuite.jl")
        PerfTest.saveExprAsFile(PerfTest.transform("recipe.jl"), suite)
        @test PerfTest.num_errors() == 0
        _, output = execute(suite, pwd())
        @test occursin("Unrecognized metric :no_such_metric", output)
    end
end

# Energy counters as a GPU extension reads them, a device being here its power in W
struct MockDevice; watts::Float64; end
PerfTest.read_joule(d::MockDevice) = d.watts

@testset "Extension hooks - energy counters and medians of the samples of each device" begin
    @test PerfTest.readEnergies([MockDevice(1.0), MockDevice(2.5)]) == [1.0, 2.5]

    samples = [[Float64(s), 10.0 * s] for s in 1:3]
    @test PerfTest.deviceMedians(samples) == [2.0, 20.0]
    n = PerfTest.MIN_VARIANCE_SAMPLES
    medians = PerfTest.deviceMedians([[Float64(s), 10.0 * s] for s in 1:n])
    @test all(m -> m isa PerfTest.SampledValue && m.n == n, medians)
    @test medians[2].value ≈ 10 * medians[1].value
end

# ----------------------------------------------------------------------------------------------------------------------
# From here on, a mock LIKWID extension: the transforms generate LIKWID measurements, their suites are not executed
# ----------------------------------------------------------------------------------------------------------------------

PerfTest.is_loaded(::Val{:LIKWID}) = true
PerfTest.newSymbols(::Val{:mock_g1}) = properties -> (PerfTest.enableLikwidGroup!(:G1); :(1))
PerfTest.newSymbols(::Val{:mock_g2}) = properties -> (PerfTest.enableLikwidGroup!(:G2); :(2))

@testset "Extension hooks - LIKWID groups apply to the testset that enables them" begin
    intempdir() do
        write("recipe.jl", """
            using Test, PerfTest
            @testset "Outer" begin
            $(metric("m1", ":mock_g1"))
                @testset "A" begin
            $(metric("m2", ":mock_g2"))
                    @perftest samples = 1 sin(1.0)
                end
                @testset "B" begin
                    @perftest samples = 1 sin(2.0)
                end
                @perftest samples = 1 sin(3.0)
            end
            """)
        ex = PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
        # A sees the groups of its testset and of Outer, B and Outer only the one of Outer
        @test perfmonGroups(ex) == [["G1", "G2"], ["G1"], ["G1"]]
    end
end

@testset "Extension hooks - native LIKWID names" begin
    intempdir() do
        write("recipe.jl", inTestset(metric("m", ":LIKWID.METRICS.RAWG.var\"Some metric [unit]\""),
                                     metric("e", ":LIKWID.EVENTS.RAWE.SOME_EVENT")))
        ex = PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
        source = string(ex)
        @test occursin("sum(PerfTest.likwidMetricsRetrieve(test_res, :RAWG, \"Some metric [unit]\"))", source)
        @test occursin("sum(PerfTest.likwidEventsRetrieve(test_res, :RAWE, \"SOME_EVENT\"))", source)
        @test perfmonGroups(ex) == [["RAWE", "RAWG"]]

        # An unknown selector, or a group without the metric
        for formula in [":LIKWID.BOGUS.G.x", ":LIKWID.METRICS.G"]
            write("recipe.jl", inTestset(metric("m", formula)))
            @test_throws ErrorException PerfTest.transform("recipe.jl")
        end
    end
end

@testset "Extension hooks - the suite imports the loaded extensions" begin
    intempdir() do
        write("recipe.jl", inTestset())
        source = string(PerfTest.transform("recipe.jl"))
        @test PerfTest.num_errors() == 0
        @test occursin("using LIKWID", source)
        @test !occursin("using CUDA", source)
        @test !occursin("using AMDGPU", source)
    end
end
