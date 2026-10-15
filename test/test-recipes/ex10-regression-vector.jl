using Test, PerfTest

@perftest_config "
[regression]
enabled = true
"

@testset "Vector regression args" begin

    @define_metric name = "custom_metric1" units = "1/s" begin
        1 / :median_time
    end

    @define_metric name = "custom_metric2" units = "s" begin
        :median_time
    end

    # Mirrors the multi-metric @regression call from
    # examples/example-kkt-cholesky-regression/clarabel_perftest.jl, which
    # requires the macro to accept vector-literal arguments.
    @regression metrics=[:median_time, :custom_metric1, :custom_metric2] threshold=[1.15, 1.20, 0.85] low_is_bad=[false, false, true]

    @perftest samples = 5 sleep(0.01)

end
