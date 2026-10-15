using Test, PerfTest

view = false

datafile = ".perftests/ex12-regression-for-loop.jl_PERFORMANCE.JLD2"

@testset "Regression - @testset for loop, per-iteration baselines" begin

    @testset "Run transformation" begin
        e = PerfTest.transform("test-recipes/ex12-regression-for-loop.jl")
        PerfTest.saveExprAsFile(e, "_t7_tmp_t7_tmp.jl")

        @test PerfTest.num_errors() == 0
    end

    @testset "Execution" begin
        for i in 1:2

            @testset "PerfTest env" begin
                if view
                    include("_t7_tmp_t7_tmp.jl")
                else
                    redirect_stdout(devnull) do
                        include("_t7_tmp_t7_tmp.jl")
                    end
                end
            end
            Test.get_testset().results = []

            tests = PerfTest.retrievePerfTests(datafile, get=:tests)
            paths = PerfTest.retrievePerfTests(datafile, get=:tests, pathonly=true)

            @testset "Run $i: each loop iteration is saved distinctly (not collapsed to the last)" begin
                @test length(tests) == 3
                @test length(unique(paths)) == 3
                @test Set(t.primitives[:iterator] for t in tests) == Set([1, 2, 3])
            end

            # Durations (0.4s / 0.2s / 0.05s, by iterator) are held constant across runs, so
            # a correctly-matched per-iteration comparison should always pass. Under the
            # collapsed-to-last-iteration bug, every iteration would instead be compared
            # against the last iteration's (0.05s) reference, and the 0.4s/0.2s iterations
            # would spuriously fail as regressions.
            passed = PerfTest.retrievePerfTests(datafile, get=:tests, where_pred=PerfTest.testPassed, pathonly=true)
            failed = PerfTest.retrievePerfTests(datafile, get=:tests, where_pred=PerfTest.testFailed, pathonly=true)

            @testset "Run $i: regression compares each iteration against its own baseline" begin
                @test length(passed) == 3
                @test length(failed) == 0
            end
        end
    end

    # Cleanup
    try
        rm("_t7_tmp_t7_tmp.jl")
        rm(".perftests/ex12-regression-for-loop.jl_PERFORMANCE.JLD2")
        rm(".perftests", recursive=true)
    catch
        @warn "Automatic file cleanup failed."
    end
end
