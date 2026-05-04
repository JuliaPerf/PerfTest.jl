
@testset "Full pass" begin
    
    @testset "Run transformation" begin
        e = PerfTest.transform("test/test-recipes/ex7-measure-tests.jl")
        PerfTest.saveExprAsFile(e, "_t4_tmp_t4_tmp.jl")

        @test Perftest.errorCount == 0
    end

    @testset "Execution" begin
        include("_t4_tmp_t4_tmp.jl")
    end

    @testset "Data retrieval" begin
        passed = PerfTest.retrievePerfTests(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2", get=:tests, where_pred=PerfTest.testPassed, pathonly=true)
        failed = PerfTest.retrievePerfTests(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2", get=:tests, where_pred=PerfTest.testFailed, pathonly=true)

        @test all([occursin("pass", t)  for t in passed])
        @test all([occursin("fail", t)  for t in failed])
        @test length(passed) == 3
        @test length(failed) == 3

        methodologies = PerfTest.retrievePerfTests(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2", get=:methodologies)
        @test length(methodologies) == 6
        @test methodologies[1].name == "Effective Memory Throughput"
        @test 1.95 <= methodologies[1].custom_elements[:abs].value <= 2.0
        @test methodologies[1].custom_elements[:abs_ref].value == 2.0
        
        @test methodologies[2].name == "Performance Assertion"
        @test methodologies[2].metrics[1][1].value == true
        @test methodologies[2].metrics[1][2].succeeded == true
        @test methodologies[2].metrics[1][1].name == ":(duration * 0.9 < :median_time < duration * 1.1)"
    end

    # Cleanup
    rm("_t4_tmp_t4_tmp.jl")
    rm(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2")
    rm(".perftests", recursive=true)
end