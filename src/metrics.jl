
include("config.jl")
include("perftest/structs.jl")

sym_set = Set([:(:median_time), :(:min_time)])

function customMetricExpressionParser(expr :: Expr) :: Expr
    return MacroTools.postwalk(x -> (@show x;x in sym_set ? :(metric_results[$x].value) : x), expr)
end

function onCustomMetricDefinition(expr ::Expr, context :: Context, flags::Set{Symbol}) :: Expr
    if length(context.depth) > 1

        # Special case
        if :mem_throughput in flags
            name = "Memory Throughput"
        else
            # Scan for name TODO
            for elem in expr.args
            end
            error("Impossible state, metrics.jl")
        end

        # Save a pair of metric flags and metric result
        context.local_injection =
           quote
            push!(local_customs, $flags => PerfTests.Metric_Result(
            name=$name,
            units="MB/s",
            # [!] ASSUMING THE BLOCK IS AT THE END OF THE MACRO CALL
            value=$(customMetricExpressionParser(expr.args[end]))
            ))
           end
    end
    # TODO
    return :(
        begin end
    )
end

function onMemoryThroughputDefinition(expr::Expr, context::Context)::Expr
    # Communicate that this can be used with the mem throughput methodology
    flags = Set{Symbol}([:mem_throughput])
    return onCustomMetricDefinition(expr, context, flags)
end

# TODO
function buildMetrics() :: Expr
    return quote
        metric_results = Dict{Symbol, PerfTests.Metric_Result}()

        # Median time
        metric_results[:median_time] = PerfTests.Metric_Result(
            name = "Median Time",
            units = "ns",
            value = PerfTests.by_index(median_suite, depth).time
        )
        # Min time
        metric_results[:min_time] = PerfTests.Metric_Result(
            name = "Minimum Time",
            units = "ns",
            value = PerfTests.by_index(min_suite, depth).time
        )

    end
end


function testMedianTime()::Expr
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
        )
        constraint = PerfTests.Metric_Constraint(
            reference=rsuite.time,
            threshold_min=threshold_min * mref.time,
            threshold_min_percent = threshold_min,
            threshold_max=threshold_max * mref.time,
            threshold_max_percent = threshold_max,
            low_is_bad=false
        )

        # Print result
        if _test
            PerfTests.printMetric(result, constraint, length(depth), false, false, false)
        else
            PerfTests.printMetric(result, constraint, length(depth), false, true, true)
        end

        # Register metric results TODO

        @test _test
    end : quote nothing end
end
