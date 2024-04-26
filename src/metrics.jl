
include("config.jl")
include("perftest/structs.jl")


function testMedianTime() :: Expr
    return metrics.median_time.enabled ? quote

        # SET WHICH THRESHOLD IS USED
        $(metrics.median_time.regression_threshold.underperform_percentage != nothing ?
            quote
                threshold_min = $(metrics.median_time.regression_threshold.underperform_percentage)
            end :
            quote
                threshold_min = $(regression.general_regression_threshold.underperform_percentage)
        end)
        $(metrics.median_time.regression_threshold.overperform_percentage != nothing ?
            quote
                threshold_max = $(metrics.median_time.regression_threshold.overperform_percentage)
            end :
            quote
                threshold_max = $(regression.general_regression_threshold.overperform_percentage)
            end)

        # Get measures for this specific test
        msuite = PerfTests.by_index(median_suite, depth)
        mref = PerfTests.by_index(median_reference, depth)
        rsuite = PerfTests.by_index(median_ratio, depth)

        # Test
	      _test = threshold_min < rsuite.time < threshold_max

        result = PerfTests.Metric_Result(
            name="Median Time",
            units="ns",
            value=msuite.time,
            reference=rsuite.time,
            threshold_min=threshold_min * mref.time,
            threshold_max=threshold_max * mref.time,
            low_is_bad=false
        )

        # Print result
        if _test
            PerfTests.printMetric(result, length(depth), false, false, false)
        else
            PerfTests.printMetric(result, length(depth), false, true, true)
        end

        @test _test
    end : quote nothing end
end
