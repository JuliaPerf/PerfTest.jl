using Test
using PerfTest

view = true

@testset "Measure - Full pass" begin

    @testset "Run transformation" begin
        e = PerfTest.transform("test-recipes/ex7-measure-tests.jl")

        PerfTest.saveExprAsFile(e, "_t4_tmp_t4_tmp.jl")

        @test PerfTest.num_errors() == 0
    end

    @testset "Execution" begin
        if view
            include("_t4_tmp_t4_tmp.jl")
        else
            redirect_stdout(devnull) do
                include("_t4_tmp_t4_tmp.jl")
            end
        end
        @test length(PerfTest.get_testset().results) > 0
        Test.get_testset().results = []
    end

    @testset "Data retrieval" begin
        passed = PerfTest.retrievePerfTests(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2", get=:tests, where_pred=PerfTest.testPassed, pathonly=true)
        failed = PerfTest.retrievePerfTests(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2", get=:tests, where_pred=PerfTest.testFailed, pathonly=true)

        @test all([occursin("pass", t) for t in passed])
        @test all([occursin("fail", t) for t in failed])
        # "Perfcompare" is a `@testset ... for duration in [0.1, 0.5]`, saved once per iteration
        @test length(passed) == 6
        @test length(failed) == 6

        # Retrieval order within a testset level follows Dict order, not declaration order,
        # so methodologies are located by content rather than by index
        methodologies = PerfTest.retrievePerfTests(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2", get=:methodologies)
        @test length(methodologies) == 12

        effmem = methodologies[findfirst(m -> m.name == "Effective Memory Throughput", methodologies)]
        @test 1.95 <= effmem.custom_elements[:abs].value <= 2.0
        @test effmem.custom_elements[:abs_ref].value == 2.0

        perfcmp_expr = ":(duration * 0.9 < :median_time < duration * 1.1)"
        perfcmp = filter(m -> m.name == "Performance Assertion" && m.metrics[1][1].name == perfcmp_expr, methodologies)
        @test length(perfcmp) == 2
        @test all(m -> m.metrics[1][1].value == true, perfcmp)
        @test all(m -> m.metrics[1][2].succeeded == true, perfcmp)
    end

    # Cleanup
    try
        rm(".perftests/ex7-measure-tests.jl_PERFORMANCE.JLD2")
        rm(".perftests", recursive=true)
        rm("_t4_tmp_t4_tmp.jl")
    catch
        @warn "Automatic file cleanup failed."
    end
end