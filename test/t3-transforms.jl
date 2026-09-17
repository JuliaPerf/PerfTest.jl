
using Test, PerfTest, MacroTools

prefix = "test-recipes/"

sources = [
    "ex1-hierarchy-basic.jl",
    "ex2-effmemtp.jl",
    "ex3-roofline.jl",
    "ex4-perfcmp.jl",
    "ex5-recursive.jl"
]
sources = [prefix * s for s in sources]
checks = [
    [
        "[TESTSET] New Group: [\"FIRST LEVEL\"]", "[TESTSET] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[PERFTEST] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[TESTSET] Exiting group", "[TESTSET] Exiting group"
    ],
    [
        "[TESTSET] New Group: [\"FIRST LEVEL\"]", "[TESTSET] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[PERFTEST] New Test: Test 1 \"x = testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[TESTSET] Exiting group", "[TESTSET] Exiting group",
    ],
    [
        "[TESTSET] New Group: [\"FIRST LEVEL\"]", "[TESTSET] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[PERFTEST] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
        "[METHODOLOGY] Defined ROOFLINE MODEL on [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
        "Building Operational intensity",
        "Building Attained Flops", "[TESTSET] Exiting group", "[TESTSET] Exiting group",
    ],
    [
        "[TESTSET] New Group: [\"FIRST LEVEL\"]", "[TESTSET] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[PERFTEST] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]", "[TESTSET] Exiting group", "[TESTSET] Exiting group",
    ],
    [
        "[TESTSET] New Group: [\"RECURSIVE\"]", "[RECURSIVE] Recursivity is enabled, entering \"test-recipes/ex4-perfcmp.jl\"",
        "[TESTSET] New Group: [\"RECURSIVE\", \"FIRST LEVEL\"]", "[TESTSET] New Group: [\"RECURSIVE\", \"FIRST LEVEL\", \"SECOND LEVEL\"]", "[PERFTEST] New Test: Test 1 \"testfun(10)\" @ [\"RECURSIVE\", \"FIRST LEVEL\", \"SECOND LEVEL\"]", "[TESTSET] Exiting group", "[TESTSET] Exiting group",
        "[RECURSIVE] \"test-recipes/ex4-perfcmp.jl\" has been processed, 0 errors found", "[TESTSET] Exiting group"
    ],
]


@testset "System Tests - Transformation" begin

    for (i, source) in enumerate(sources)
        expr = PerfTest.transform(source)
        log = PerfTest.dumpLogsString()

        for check in checks[i]
            @test occursin(check, log)
        end
    end
end

@testset "System Tests - @regression with vector-literal arguments" begin

    PerfTest.transform(prefix * "ex10-regression-vector.jl")
    log = PerfTest.dumpLogsString()

    @test PerfTest.num_errors() == 0
    @test !occursin("[PARSING ERROR]", log)
    @test occursin("METRICS: [:median_time, :custom_metric1, :custom_metric2]", log)
    @test occursin("LOW_IS_BAD: Bool[0, 0, 1]", log)
end

@testset "rewrapDoBlockBodies - repairs prettify's single-statement do-block flattening" begin

    # Reproduces, in isolation, the exact corruption `MacroTools.prettify` used to
    # introduce: a `do`-block whose body is a single tuple-literal statement gets
    # `flatten`-ed down to a bare (non-:block) tuple expression, which Base's `:do`
    # printer then mis-renders as two unparenthesized statements.
    ex = quote
        (L, D) = get!(_dense_factors, ldlsolver) do
            (Matrix{Float64}(undef, n, n), Vector{Float64}(undef, n))
        end
    end

    pretty = MacroTools.prettify(ex)
    corrupted = string(pretty)
    @test !occursin("(Matrix{Float64}(undef, n, n), Vector{Float64}(undef, n))", corrupted)

    fixed = string(PerfTest.rewrapDoBlockBodies(pretty))
    @test occursin("(Matrix{Float64}(undef, n, n), Vector{Float64}(undef, n))", fixed)
end

@testset "System Tests - do-block tuple bodies survive full transform" begin

    expr = PerfTest.transform(prefix * "ex11-do-block-tuple.jl")
    source = string(expr.args[1])

    @test occursin("(Vector{Float64}(undef, n), Vector{Float64}(undef, n))", source)
end

@testset "System Tests - regression baseline keys are loop-aware inside @testset for" begin

    # `@perftest`/`@regression` inside a `@testset "..." for n in ...` must resolve their
    # saved-baseline lookup key at suite run time (using the current loop variable), not
    # bake a single static key shared by every iteration - otherwise every iteration ends
    # up comparing against whichever iteration's result was saved last. See "Sleep by size"
    # in ex12-regression-for-loop.jl, which has this shape.
    expr = PerfTest.transform(prefix * "ex12-regression-for-loop.jl")
    source = string(expr)

    @test PerfTest.num_errors() == 0
    @test occursin("string(\"Sleep by size\", \"_\", n)", source)
    @test !occursin("[\"Wrapper\", \"Sleep by size\"]", source)
end
