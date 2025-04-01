
sources = [
    "ex1-hierarchy-basic.jl",
    "ex2-effmemtp.jl",
    "ex3-roofline.jl",
    "ex4-perfcmp.jl",
    "ex5-recursive.jl"
]
checks = [
    [
        "[BNCH] New Group: [\"FIRST LEVEL\"]",
        "[TESTS] Entering testgroup",
        "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
        "[TESTS] Entering testgroup",
        "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
        "[TESTS] Exiting SECOND LEVEL at depth 2",
        "[BNCH] Exiting group",
        "[TESTS] Exiting FIRST LEVEL at depth 1",
        "[BNCH] Exiting group"
    ],
    [
     "[BNCH] New Group: [\"FIRST LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Exiting SECOND LEVEL at depth 2",
     "[BNCH] Exiting group",
     "[TESTS] Exiting FIRST LEVEL at depth 1",
     "[BNCH] Exiting group",
    ],
    [
     "[BNCH] New Group: [\"FIRST LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[METHODOLOGY] Defined ROOFLINE MODEL on [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "Building Operational intensity",
     "Building Attained Flops",
     "[TESTS] Exiting SECOND LEVEL at depth 2",
     "[BNCH] Exiting group",
     "[TESTS] Exiting FIRST LEVEL at depth 1",
     "[BNCH] Exiting group",
    ],
    [
     "[BNCH] New Group: [\"FIRST LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Exiting SECOND LEVEL at depth 2",
     "[BNCH] Exiting group",
     "[TESTS] Exiting FIRST LEVEL at depth 1",
     "[BNCH] Exiting group",
    ],
    [
        "[BNCH] New Group: [\"RECURSIVE\"]",
     "[TESTS] Entering testgroup",
     "[RECURSIVE] Recursivity is enabled, entering \"ex4-perfcmp.jl\"",
     "[BNCH] New Group: [\"RECURSIVE\", \"FIRST LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Group: [\"RECURSIVE\", \"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Entering testgroup",
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"RECURSIVE\", \"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[TESTS] Exiting SECOND LEVEL at depth 2",
     "[BNCH] Exiting group",
     "[TESTS] Exiting FIRST LEVEL at depth 1",
     "[BNCH] Exiting group",
     "[RECURSIVE] \"ex4-perfcmp.jl\" has been processed, 0 errors found",
     "[TESTS] Exiting RECURSIVE at depth 1",
     "[BNCH] Exiting group"
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
