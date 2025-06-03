
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
        
        "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
        
        "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
        
        "[BNCH] Exiting group",
        
        "[BNCH] Exiting group"
    ],
    [
     "[BNCH] New Group: [\"FIRST LEVEL\"]",
     
     "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] New Test: Test 1 \"x = testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] Exiting group",
     
     "[BNCH] Exiting group",
    ],
    [
     "[BNCH] New Group: [\"FIRST LEVEL\"]",
     
     "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "[METHODOLOGY] Defined ROOFLINE MODEL on [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     "Building Operational intensity",
     "Building Attained Flops",
     
     "[BNCH] Exiting group",
     
     "[BNCH] Exiting group",
    ],
    [
     "[BNCH] New Group: [\"FIRST LEVEL\"]",
     
     "[BNCH] New Group: [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] Exiting group",
     
     "[BNCH] Exiting group",
    ],
    [
        "[BNCH] New Group: [\"RECURSIVE\"]",
     
     "[RECURSIVE] Recursivity is enabled, entering \"ex4-perfcmp.jl\"",
     "[BNCH] New Group: [\"RECURSIVE\", \"FIRST LEVEL\"]",
     
     "[BNCH] New Group: [\"RECURSIVE\", \"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] New Test: Test 1 \"testfun(10)\" @ [\"RECURSIVE\", \"FIRST LEVEL\", \"SECOND LEVEL\"]",
     
     "[BNCH] Exiting group",
     
     "[BNCH] Exiting group",
     "[RECURSIVE] \"ex4-perfcmp.jl\" has been processed, 0 errors found",
     
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
