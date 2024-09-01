


# THIS FILE SAVES THE MAIN COMPONENTS OF THE EMPYRICAL EFFECTIVE MEM. THROUGHPUT
# METHODOLOGY BEHAVIOUR

function effMemThroughputPrefix(ctx::Context)::Expr
    return effective_memory_throughput.enabled ?
           quote
               using Suppressor
               using STREAMBenchmark
    end : quote
        begin end
    end
end


function effMemThroughputEvaluation(context :: Context)::Expr
    if effective_memory_throughput.enabled
        expr = quote begin end end

        for cmetric in union(context.global_c_metrics,context.local_c_metrics)
            if :mem_throughput in cmetric.flags
                expr = quote
                    $expr
                    # Threshold
                    min = $(effective_memory_throughput.tolerance.min_percentage)
                    max = $(effective_memory_throughput.tolerance.max_percentage)

                    result = PerfTest.Metric_Result(
                        name=$(cmetric.name),
                        units=$(cmetric.units),
                        value=$(customMetricExpressionParser(cmetric.formula))
                    )
                    
                    # Ratio
                    ratio = result.value / peakbandwidth
                    # test
                    _test = min < ratio < max


                    constraint = PerfTest.Metric_Constraint(
                        reference=peakbandwidth,
                        threshold_min=min * peakbandwidth,
                        threshold_min_percent=min,
                        threshold_max=max * peakbandwidth,
                        threshold_max_percent=max,
                        low_is_bad=true,
                        succeeded=_test, custom_plotting=Symbol[],
                        full_print=$(verbose ? :(true) : :(!_test))
                    )



                    # Setup result collecting struct
                    methodology_result = PerfTest.Methodology_Result(
                        name="EFFECTIVE MEMORY THROUGHPUT RATIO",
                        metrics=Pair{PerfTest.Metric_Result,PerfTest.Metric_Constraint}[]
                    )

                    push!(methodology_result.metrics, (result => constraint))

                    PerfTest.printMethodology(methodology_result, $(length(context.depth)))
                    # Register metric results TODO

                    @test _test
                end
            end
        end

        return expr
    else
        return quote begin end end
    end
end
