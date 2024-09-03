


sym_set = Set([:(:median_time), :(:minimum_time)])

"""
This is one of the parser functions that expand any formula block for metric definition.
This function will parse all primitive metric symbols with the structure where the corresponding value of the metric is.
"""
function customMetricExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x in sym_set ? :(metric_results[$x].value) : x), expr)
end

"""
This is one of the parser functions that expand any formula block for metric definition.
This function will parse all primitive metric symbols with the structure where the corresponding reference value for the metric is.
"""
function customMetricReferenceExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x in sym_set ? :(metric_references[$x]) : x), expr)
end

"""
This is one of the parser functions that expand any formula block for metric definition.
This function will parse the appropiate symbol and substitute it by the return value of the test target execution.
"""
function retvalExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:return) ? :(PerfTest.by_index(export_tree, depth)[:ret_value]) : x), expr)
end

"""
This is one of the parser functions that expand any formula block for metric definition.
This function will parse the `:autoflop` symbol and substitute it with the flop count of the test target
"""
function autoflopExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> ((@show x; x == :(:autoflop)) ? :(PerfTest.by_index(export_tree, depth)[:autoflop]) : x), expr)
end

"""
This is one of the parser functions that expand any formula block for metric definition.
This function will parse the `:printed_output` symbol and substitute it with the standard output of the test target execution
"""
function printedOutputExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:printed_output) ? :(PerfTest.by_index(export_tree, depth)[:printed_output]) : x), expr)
end

function printedOutputAbbreviationExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:out) ? :(PerfTest.grepOutputXGetNumber(PerfTest.by_index(export_tree, depth)[:printed_output])) : x), expr)
end

"""
This is one of the parser functions that expand any formula block for metric definition.
This function will parse the `:iterator` symbol and substitute it with the current value of the innermost test set loop of the current test target execution
"""
function iteratorExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:iterator) ? :(PerfTest.by_index(export_tree, depth)[:iterator]) : x), expr)
end

"""
This function combines a collection of rules to turn a formula block into a functioning expression to calculate any metric defined by said formula
"""
function fullParsingSuite(expr::Expr)::Expr
    # Fill primitives
    t = customMetricExpressionParser(expr)
    # Fill return
    t = retvalExpressionParser(t)
    # Fill autoflops
    t = autoflopExpressionParser(t)
    # Fill output
    t = printedOutputExpressionParser(t)
    # Abbreviated version
    t = printedOutputAbbreviationExpressionParser(t)
    # Fill iterator on for testsets
    t = iteratorExpressionParser(t)
    return t
end

"""
This function is called to register a custom metric, it will parse the arguments of the definition macro and add the metric to the context to be later used in test targets on the same scope.
"""
function onCustomMetricDefinition(expr ::Expr, context :: Context, flags::Set{Symbol}) :: Expr

    # Special case
    if :mem_throughput in flags
        name = "Memory Throughput"
        unit = "MB/s"

        if verbose
            println("A memory throughput measure has been defined:")
        end
    else
        @show dump(expr)
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

"""
This function is used to register a special custom metric, which is the effective memory throughput calculation, and is registered in the same way as any other but with a special flag that the EMT metholodogy will use to get and use the metric.
"""
function onMemoryThroughputDefinition(expr::Expr, context::Context)::Expr
    # Communicate that this can be used with the mem throughput methodology
    flags = Set{Symbol}([:mem_throughput])
    return onCustomMetricDefinition(expr, context, flags)
end

"""
This function generates the code that make primitive metrics values available to all metodologies and custom metrics.
"""
function buildPrimitiveMetrics() :: Expr
    return quote
        metric_results = Dict{Symbol, PerfTest.Metric_Result}()

        # Median time
        metric_results[:median_time] = PerfTest.Metric_Result(
            name = "Median Time",
            units = "ns",
            value = PerfTest.by_index(median_suite, depth).time
        )
        # Min time
        metric_results[:minimum_time] = PerfTest.Metric_Result(
            name = "Minimum Time",
            units = "ns",
            value = PerfTest.by_index(min_suite, depth).time
        )

    end
end

"""
This function is used to generate the code that evaluates if the median time of execution of a target is within a specified reference.

# WARNING
Predefined symbols needed before this code is added to the generated space:
 - `reference_value`
 - `metric_results`
"""
function checkMedianTime(thresholds ::Struct_Tolerance)::Expr
    return metrics.median_time.enabled ? quote

        threshold_min = $(thresholds.min_percentage)
        threshold_max = $(thresholds.max_percentage)

        # Get value from the dictionary built on the function above
        result = metric_results[:median_time]

        # Test boolean
	      _test = threshold_min < (reference_value / result.value) < threshold_max

        constraint = PerfTest.Metric_Constraint(
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

"""
This function is used to generate the code that evaluates if the minimum time of execution of a target is within a specified reference.

# WARNING
Predefined symbols needed before this code is added to the generated space:
 - `reference_value`
 - `metric_results`
"""
function checkMinTime(thresholds::Struct_Tolerance)::Expr
    return metrics.median_time.enabled ? quote

        threshold_min = $(thresholds.min_percentage)
        threshold_max = $(thresholds.max_percentage)

        # Get value from the dictionary built on the function above
        result = metric_results[:minimum_time]

        # Test boolean
	      _test = threshold_min < (reference_value / result.value) < threshold_max

        constraint = PerfTest.Metric_Constraint(
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


"""
This function is used to generate the code that evaluates if a custom metric result f a target is within a specified reference.

# WARNING
Predefined symbols needed before this code is added to the generated space:
 - `reference_value`
 - `metric_results`
"""
function checkCustomMetric(metric :: CustomMetric)::Expr

    if :aux in metric.flags
        return checkAuxiliaryMetric(metric)
    else
    return quote
        (threshold_min, threshold_max) = $(
            let a = configFallBack(Struct_Tolerance(), :regression)
                a.min_percentage,
                a.max_percentage
            end)

        # Filling out the formula
        reference_value = $(customMetricReferenceExpressionParser(metric.formula))
        result = PerfTest.Metric_Result(
            name = $(metric.name),
            units = $(metric.units),
            value = $(customMetricExpressionParser(metric.formula))
        )

        # Test boolean
	      _test = threshold_min < (reference_value / result.value) < threshold_max

        constraint = PerfTest.Metric_Constraint(
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
end


"""
This function is used to generate the code that evaluates if a custom metric result f a target is within a specified reference.

# WARNING
Predefined symbols needed before this code is added to the generated space:
 - `reference_value`
 - `metric_results`
"""
function checkCustomMetrics(context::Context)::Expr
    result = :(
        begin end
    )
    for metric in context.global_c_metrics
        result = quote
            $result
            $(checkCustomMetric(metric))
        end
    end
    for metric in context.local_c_metrics
        result = quote
            $result
            $(checkCustomMetric(metric))
        end
    end
    return result
end


"""
This method is used to generate the code that computes the value of a given auxiliary custom metric in the context the code is generated.
"""
function checkAuxiliaryMetric(metric::CustomMetric)::Expr
    return quote
        # Filling out the formula
        result_ = PerfTest.Metric_Result(
            name=$(metric.name),
            units=$(metric.units),
            value=$(fullParsingSuite(metric.formula))
        )
        # Register metric results
        methodology_result.custom_elements[Symbol(:aux_, $(metric.name))] = result_
    end
end

"""
This method is used to generate the code that computes the value of every auxiliary custom metric enabled in th current context, where the code is generated.
"""
function checkAuxiliaryCustomMetrics(context::Context)::Expr
    result = :(
        begin end
    )
    for metric in context.global_c_metrics
        if :aux in metric.flags
            result = quote
                $result
                $(checkCustomMetric(metric))
            end
        end
    end
    for metric in context.local_c_metrics
        if :aux in metric.flags
            result = quote
                $result
                $(checkCustomMetric(metric))
            end
        end
    end
    return result
end
