
"""

Called when a regression macro is detected, sets up the regression methodology

"""
function onRegressionDefinition(_::ExtendedExpr, ctx::Context, info)
    if !(Configuration.CONFIG["regression"]["enabled"])
        return
    end

    if haskey(info, :threshold)
    else
        info[:threshold] = Configuration.CONFIG["regression"]["default_threshold"]
    end
    if haskey(info, :metrics)
    else
        info[:metrics] = :median_time
    end
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id=:regression,
        name="Metric regression tracking",
        override=true,
        params=info,
    ))

    addLog("metrics", "[METHODOLOGY] Defined REGRESSION on $([i.set_name for i in ctx._local.depth_record])")
end


"""
 Executes regression for one single metric
"""
function regression(metric :: Symbol, info)
    metric = QuoteNode(metric)
    return quote
        if haskey(test_res.metrics, $metric) && !(old_test_res isa Nothing) && haskey(old_test_res.metrics, $metric)
            ratio = test_res.metrics[$metric] / old_test_res.metrics[$metric]
            success = ratio > $(info[:threshold])

            result = newMetricResult($mode,
                                    name=$("$metric Difference"),
                                    units="%",
                                    value=ratio * 100
            )
            test = Metric_Test(
                reference=100.0,
                threshold_min_percent=$(info[:threshold]) * 100,
                threshold_max_percent=nothing,
                low_is_bad=true,
                succeeded=success,
                custom_plotting=Symbol[],
                full_print=true
            )

            push!(methodology_res.metrics, (result => test))

            all_succeeded &= success
        elseif !(old_test_res isa Nothing) && !haskey(test_res.metrics, $metric) && haskey(test_res.primitives, $metric) && haskey(old_test_res.primitives, $metric)
            ratio = test_res.primitives[$metric] / old_test_res.primitives[$metric]
            success = ratio > $(info[:threshold])

            result = newMetricResult($mode,
                                    name=$("$metric Difference"),
                                    units="%",
                                    value=ratio * 100
            )
            test = Metric_Test(
                reference=100.0,
                threshold_min_percent=$(info[:threshold]) * 100,
                threshold_max_percent=nothing,
                low_is_bad=true,
                succeeded=success,
                custom_plotting=Symbol[],
                full_print=true
            )

            push!(methodology_res.metrics, (result => test))

            all_succeeded &= success
        end
    end
end

"""
  Returns an expression used to evaluate regression over a test target
"""
function buildRegression(context::Context)::Expr


    info = captureMethodologyInfo(:regression, context._local.enabled_methodologies)
    if info isa Nothing
        return quote end
    else
        info = info.params
        return quote
            let
                methodology_res = Methodology_Result(
                    name="Performance Regression Testing"
                )

                all_succeeded = true
                $(
                if info[:metrics] isa Symbol
                    regression(info[:metrics], info)
                else
                    for i in info[:metrics]
                        regression(i, info)
                    end
                end
                )
                
                
                for (r,test) in methodology_res.metrics
                    PerfTest.@_prftest test.succeeded
                end

                saveMethodologyData(test_res.name, methodology_res)
            end
        end
    end
end
