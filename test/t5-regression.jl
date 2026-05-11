using Test,PerfTest

view = false

@testset "Regression - Full pass" begin
    
    @testset "Run transformation" begin
        e = PerfTest.transform("test-recipes/ex8-regression-test.jl")
        PerfTest.saveExprAsFile(e, "_t5_tmp_t5_tmp.jl")

        @test PerfTest.num_errors() == 0
    end

    @testset "Execution" begin
        for i in 1:3

            @testset "PerfTest env" begin
                if view
                    include("_t5_tmp_t5_tmp.jl")
                else
                    redirect_stdout(devnull) do
                        include("_t5_tmp_t5_tmp.jl")
                    end
                end
            end
            Test.get_testset().results = []


            passed = PerfTest.retrievePerfTests(".perftests/ex8-regression-test.jl_PERFORMANCE.JLD2", get=:tests, where_pred=PerfTest.testPassed, pathonly=true)
            failed = PerfTest.retrievePerfTests(".perftests/ex8-regression-test.jl_PERFORMANCE.JLD2", get=:tests, where_pred=PerfTest.testFailed, pathonly=true)
            if i == 1
                @test length(passed) == 4
                @test length(failed) == 0
            else 
                @test length(passed) == 2
                for p in passed
                    @test contains(p, "pass")
                end
                @test length(failed) == 2
                for f in failed
                    @test contains(f, "fail")
                end
            end
        end
    end


    # Cleanup
    try
        rm("_t5_tmp_t5_tmp.jl")
        rm(".perftests/ex8-regression-test.jl_PERFORMANCE.JLD2")
        rm(".perftests", recursive=true)
    catch
        @warn "Automatic file cleanup failed."
    end
end