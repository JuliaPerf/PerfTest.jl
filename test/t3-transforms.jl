
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
    ],
    [
    ],
    [
    ],
    [
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
