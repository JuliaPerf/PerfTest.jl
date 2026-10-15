# Careful changing testset names (used for parsing)
using Test, PerfTest

@perftest_config "
[regression]
enabled = true
[perfcompare]
enabled = true
"

@testset "Showvar Tests" begin

    @testset "Regression with showvar, enough samples" begin
        # samples=100 on a near-instant target reliably clears MIN_VARIANCE_SAMPLES (30),
        # so median_time's variance should be populated and, since showvar=true, printed.
        @regression threshold=0.5 low_is_bad=false metrics=:median_time showvar=true

        @auxiliary_metric name = "half_time" units = "s" begin
            :median_time / 2
        end

        @perftest samples = 100 (1 + 1)
    end

    @testset "Regression with showvar, too few samples" begin
        # samples=5 stays below MIN_VARIANCE_SAMPLES, so variance must not be shown even
        # though showvar=true was requested.
        @regression threshold=0.5 low_is_bad=false metrics=:median_time showvar=true

        @perftest samples = 5 (1 + 1)
    end

    @testset "Perfcompare with showvar" begin
        @perfcompare showvar=true :median_time < 10.0

        @auxiliary_metric name = "double_time" units = "s" begin
            :median_time * 2
        end

        @perftest samples = 100 (1 + 1)
    end
end
