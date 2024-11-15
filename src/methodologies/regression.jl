# TODO REFACTOR

# THIS FILE SAVES THE MAIN COMPONENTS OF THE REGRESSION METHODOLOGY BEHAVIOUR

# TODO IMPORTANT TRANSCRIBE LATER:
# Generated space variables relevant in any methodology
# Have to be defined in each generic methodology:
# x_reference
# x_ratio

function regressionPrefix(ctx::Context)::Expr
    a = CONFIG.regression.enabled
    return (a ?
           quote
        # Get reference trials given the specified calculation policy
        $(
            if true
                quote
                    try
                        global reference = last(data.results).benchmarks
                    catch e
                    end
                end
            # elseif false # TODO
            #     quote
            #         reference_components::Vector{BenchmarkGroup} = []
            #         for result in data.results
            #             push!(reference_components, result.benchmarks)
            #             # TODO Extra information needed??
            #         end
            #         global reference = reference_components[1]
            #     end
            # else
            #     error("Invalid: regression.regression_calculation")
            end
        )
    end : quote
        nothing
    end)
end

function regressionSuffix(ctx::Context)::Expr
    if CONFIG.regression.enabled
        return quote
            if res_num > 0

                # Estimates
                median_reference = median(reference)
                min_reference = minimum(reference)
                # Ratios
                median_ratio = ratio(median_suite, median_reference)
                min_ratio = ratio(min_suite, min_reference)
            else
                PerfTest.p_yellow("[ℹ]")
                println(" Regression: No previous results.")
            end
        end
    else
        return quote nothing end
    end
end

# Predefined elements to have:
# depth
# dictionaries defined in the function above
# metric_reference has to be cleared out in the function
function regressionEvaluation(context :: Context)::Expr
    return CONFIG.regression.enabled ? quote
        if res_num > 0
            # Setup result collecting struct
            methodology_result = PerfTest.Methodology_Result(
                name = "REGRESSION TESTING",
                metrics = Pair{PerfTest.Metric_Result, PerfTest.Metric_Constraint}[]
            )

            metric_references = Dict{Symbol, Any}()

            # Metric data generation
            # MEDIAN TIME
            reference_value = PerfTest.by_index(median_reference, depth).time
            metric_references[:median_time] = reference_value
            # $(checkMedianTime(
            #     configFallBack(metrics.median_time.regression_threshold,
            #         :regression)))
            # MIN TIME
            reference_value = PerfTest.by_index(min_reference, depth).time
            metric_references[:minimum_time] = reference_value
            # $(checkMinTime(
            #     configFallBack(metrics.median_time.regression_threshold,
            #                    :regression)))
            
            #$(testMeanMemory())
            #$(testMinMemory())
            #$(testMeanAllocs())
            #$(testMinAllocs())

            # TODO COMMENTED
            #$(checkCustomMetrics(context))

            # Metric print
            PerfTest.printMethodology(methodology_result, length(depth))

            # Metric actual test
            for pair in methodology_result.metrics
                @test pair.second.succeeded
            end
        end
    end : quote
        begin end
    end
end
