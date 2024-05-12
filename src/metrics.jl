
include("config.jl")
include("perftest/structs.jl")

sym_set = Set([:(:median_time), :(:minimum_time)])

function customMetricExpressionParser(expr :: Expr) :: Expr
    return MacroTools.postwalk(x -> (@show x; x in sym_set ? :(metric_results[$x].value) : x), expr)
end

function customMetricReferenceExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (@show x; x in sym_set ? :(metric_references[$x]) : x), expr)
end

function onCustomMetricDefinition(expr ::Expr, context :: Context, flags::Set{Symbol}) :: Expr

    # Special case
    if :mem_throughput in flags
        name = "Memory Throughput"
        unit = "MB/s"

        if verbose
            println("A memory throughput measure has been defined:")
        end
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
        if verbose
            println("A custom measure has been defined:")
        end
        if !(got_name && got_unit)
            error("Absent \"name\" or \"units\" in custom metric.")
        end
    end

    # If outside testsets the metric will be global (aka. applied everywhere)
    if length(context.depth) > 1
        # Save a pair of metric flags and metric result
        push!(context.local_c_metrics, CustomMetric(
            name=name,
            units=unit,
            formula=expr.args[end],
            flags=flags
        ))
        if verbose
            println(">    In a local scope:", context.depth)
        end
    else
        push!(context.global_c_metrics, CustomMetric(
            name=name,
            units=unit,
            formula=expr.args[end],
            flags=flags
        ))
        if verbose
            println(">    In a global scope")
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

# TODO flops memory
function buildPrimitiveMetrics() :: Expr
    return quote
        metric_results = Dict{Symbol, PerfTests.Metric_Result}()

        # Median time
        metric_results[:median_time] = PerfTests.Metric_Result(
            name = "Median Time",
            units = "ns",
            value = PerfTests.by_index(median_suite, depth).time
        )
        # Min time
        metric_results[:minimum_time] = PerfTests.Metric_Result(
            name = "Minimum Time",
            units = "ns",
            value = PerfTests.by_index(min_suite, depth).time
        )

    end
end

# WARNING Predefined symbols needed before this quote
# reference_value
# metric_results
function checkMedianTime(thresholds ::Struct_Tolerance)::Expr
    return metrics.median_time.enabled ? quote

        threshold_min = $(thresholds.min_percentage)
        threshold_max = $(thresholds.max_percentage)

        # Get value from the dictionary built on the function above
        result = metric_results[:median_time]

        # Test boolean
	      _test = threshold_min < (reference_value / result.value) < threshold_max

        constraint = PerfTests.Metric_Constraint(
            reference=reference_value,
            threshold_min=threshold_min * reference_value,
            threshold_min_percent = threshold_min,
            threshold_max=threshold_max * reference_value,
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

# WARNING Predefined symbols needed before this quote
# reference_value
# metric_results
function checkMinTime(thresholds::Struct_Tolerance)::Expr
    return metrics.median_time.enabled ? quote

        threshold_min = $(thresholds.min_percentage)
        threshold_max = $(thresholds.max_percentage)

        # Get value from the dictionary built on the function above
        result = metric_results[:minimum_time]

        # Test boolean
	      _test = threshold_min < (reference_value / result.value) < threshold_max

        constraint = PerfTests.Metric_Constraint(
            reference=reference_value,
            threshold_min=threshold_min * reference_value,
            threshold_min_percent = threshold_min,
            threshold_max=threshold_max * reference_value,
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


# WARNING Predefined symbols needed before this quote
# metric_results
# msym
# metric (see loop on function below this one)
function checkCustomMetric(metric :: CustomMetric)::Expr

    return quote
        (threshold_min, threshold_max) = $(
            let a = configFallBack(Struct_Tolerance(), :regression)
                a.min_percentage,
                a.max_percentage
            end)

        # Filling out the formula
        reference_value = $(customMetricReferenceExpressionParser(metric.formula))
        result = PerfTests.Metric_Result(
            name = $(metric.name),
            units = $(metric.units),
            value = $(customMetricExpressionParser(metric.formula))
        )

        # Test boolean
	      _test = threshold_min < (reference_value / result.value) < threshold_max

        constraint = PerfTests.Metric_Constraint(
            reference=reference_value,
            threshold_min=threshold_min * reference_value,
            threshold_min_percent = threshold_min,
            threshold_max=threshold_max * reference_value,
            threshold_max_percent = threshold_max,
            low_is_bad=false,
            succeeded = _test,

            custom_plotting = Symbol[],
            full_print = $(verbose ? :(true) : :(_test))
        )


        # Register metric results
        push!(methodology_result.metrics, (result => constraint))
    end
end


# WARNING Predefined symbols needed before this quote
# local_customs, global_customs
function checkCustomMetrics(context :: Context)::Expr
    result = :(begin end)
    for metric in context.global_c_metrics
        result = quote $result; $(checkCustomMetric(metric)) end
    end
    for metric in context.local_c_metrics
        result = quote $result; $(checkCustomMetric(metric)) end
    end
    return result
end
