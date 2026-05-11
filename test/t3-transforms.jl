
using Test, PerfTest

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
