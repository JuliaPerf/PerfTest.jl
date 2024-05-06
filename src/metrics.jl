
include("config.jl")
include("perftest/structs.jl")

sym_set = Set([:(:median_time), :(:min_time)])

function customMetricExpressionParser(expr :: Expr) :: Expr
    return MacroTools.postwalk(x -> (@show x; x in sym_set ? :(metric_results[$x].value) : x), expr)
end

function onCustomMetricDefinition(expr ::Expr, context :: Context, flags::Set{Symbol}) :: Expr

    # Special case
    if :mem_throughput in flags
        name = "Memory Throughput"
        unit = "MB/s"
    else
        got_name = false
        got_unit = false
        # Scan for name and unit
        for elem in expr.args
            if elem isa Expr && elem.head == Symbol("=")
                if !(elem.args[2] isa String)
                    error("Malformed local custom metric.")
                end
                if elem.args[1] == Symbol("name")
                    name = elem.args[2]
                    got_name = true
                end
                if elem.args[1] == Symbol("units")
                    unit = elem.args[2]
                    got_unit = true
                end
            end
        end
        if !(got_name && got_unit)
            error("Absent \"name\" or \"units\" in custom metric.")
        end
    end

    if length(context.depth) > 1
        # Save a pair of metric flags and metric result
        context.local_injection =
            quote
                push!(local_customs, $flags => PerfTests.Metric_Result(
                    name=$name,
                    units=$unit,
                    # [!] ASSUMING THE BLOCK IS AT THE END OF THE MACRO CALL
                    value=$(customMetricExpressionParser(expr.args[end]))
                ))
            end
    else
        context.custom_metrics = quote
	          $(context.custom_metrics)
            push!(global_customs, $flags => PerfTests.Metric_Result(
                name=$name,
                units=$unit,
                # [!] ASSUMING THE BLOCK IS AT THE END OF THE MACRO CALL
                value=$(customMetricExpressionParser(expr.args[end]))
            ))
        end
    end
    # If the metric is defined outside the testsets it will be applied everywhere
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


function medianTime(thresholds ::Struct_Tolerance)::Expr
    return metrics.median_time.enabled ? quote

        threshold_min = $(thresholds.min_percentage)
        threshold_max = $(thresholds.max_percentage)

        # Get measures for this specific test
        msuite = PerfTests.by_index(median_suite, depth)
        mref = PerfTests.by_index(median_reference, depth)
        rsuite = PerfTests.by_index(median_ratio, depth)

        # Test boolean
	      _test = threshold_min < rsuite.time < threshold_max

        result = PerfTests.Metric_Result(
            name="Median Time",
            units="ns",
            value=msuite.time,
        )

        constraint = PerfTests.Metric_Constraint(
            reference=mref.time,
            threshold_min=threshold_min * mref.time,
            threshold_min_percent = threshold_min,
            threshold_max=threshold_max * mref.time,
            threshold_max_percent = threshold_max,
            low_is_bad=false,
            succeeded = _test,

            custom_plotting = Symbol[],
            full_print = $(verbose ? :(true) : :(_test))
        )


        # Register metric results
        push!(methodology_result.metrics, (result => constraint))

    end : quote nothing end
end
