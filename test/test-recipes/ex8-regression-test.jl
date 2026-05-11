# Careful changing testset names (used for parsing)
using Test, PerfTest

@perftest_config "
[regression]
enabled = true
"

execution_number = try length(PerfTest.getExecutionTimestamps(".perftests/ex8-regression-test.jl_PERFORMANCE.JLD2")) + 1 catch; 1 end

@testset "Regression Tests" begin

    @testset "Default :median_time" begin

        @testset "This should pass" begin
            time = 0.5 / execution_number

            @perftest samples = 5 sleep(time)

        end

        @testset "This should fail" begin
            time = 0.1 * execution_number

            @perftest samples = 5 sleep(time)
        end

    end

    @testset "Custom metric" begin

        @define_metric name = "custom_time" units = "1/s" begin
            1 / :median_time
        end
        # Defining regression on a parent testset will apply it to all child testsets, but it can be redefined on a child testset to apply different regression criteria
        @regression threshold=0.9 low_is_bad=true metrics="custom_time"

        @testset "This should pass" begin
            time = 0.5 / execution_number

            @perftest samples = 5 sleep(time)
        end

        @testset "This should fail" begin
            time = 0.1 * execution_number

            @perftest samples = 5 sleep(time)
        end
    end
end