
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
    if haskey(info, :low_is_bad)
    else
        info[:low_is_bad] = false
    end
    # vvvv Verify that parameters make sense among each other vvvv
    if info[:metrics] isa metricID()
        info[:metrics] = [metricID(info[:metrics])]
        info[:low_is_bad] = info[:low_is_bad] isa Vector ? throwParseError!("Several low_is_bad values provided for low_is_bad for a single metric", ctx) : [info[:low_is_bad]]
        info[:threshold] = info[:threshold] isa Vector ? throwParseError!("Several threshold values provided for threshold for a single metric", ctx) : [info[:threshold]]
    else
        if info[:low_is_bad] isa Bool
            info[:low_is_bad] = fill(info[:low_is_bad], length(info[:metrics]))
        elseif length(info[:low_is_bad]) != length(info[:metrics])
            throwParseError!("Length of low_is_bad should be either 1 to apply to all, or the same as the length of metrics", ctx)
        end
        if info[:threshold] isa Float64
            info[:threshold] = fill(info[:threshold], length(info[:metrics]))
        elseif length(info[:threshold]) != length(info[:metrics])
            throwParseError!("Length of threshold should be either 1 to apply to all, or the same as the length of metrics", ctx)
        end
        info[:metrics] = [metricID(m) for m in info[:metrics]]
    end
    # ^^^^ Verify that parameters make sense among each other ^^^^
    for metric in info[:metrics]
        if !(metric in formula_symbols) && !isCustomMetricDefined(ctx, metric)
            throwParseError!("Metric $metric is not available in the current context.", ctx)
        end
    end
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id=:regression,
        name="Metric regression tracking",
        override=false,
        params=info,
    ))

    addLog("metrics", "[METHODOLOGY] Defined REGRESSION on $([i.set_name for i in ctx._local.depth_record]) METRICS: $(info[:metrics]) TH: $(info[:threshold]) LOW_IS_BAD: $(info[:low_is_bad])")
end


"""
 Executes regression for one single metric
"""
function regression(metric :: Symbol, threshold::Float64, low_is_bad::Bool)
    metric = QuoteNode(metric)

    success_expr = :($(low_is_bad ? :(>) : :(<))(ratio ,$(threshold)))
    return quote
        if haskey(test_res.metrics, $metric) && !(old_test_res isa Nothing) && haskey(old_test_res.metrics, $metric)
            ratio = test_res.metrics[$metric].value / old_test_res.metrics[$metric].value
            success = $success_expr

            result = newMetricResult($mode,
                                    name=$("$metric Difference"),
                                    units="%",
                                    value=ratio * 100
            )
            test = Metric_Test(
                reference=100.0,
                threshold_min_percent=$(threshold) * 100,
                threshold_max_percent=nothing,
                low_is_bad=$(low_is_bad),
                succeeded=success,
                custom_plotting=Symbol[],
                full_print=true
            )

            push!(methodology_res.metrics, (result => test))
            
            # Register tracked metric in auxiliar group for later usage in Bencher
            methodology_res.custom_elements[$metric] =  (newMetricResult(
                $mode,
                name=test_res.metrics[$metric].name,
                units=test_res.metrics[$metric].units,
                value=test_res.metrics[$metric].value) => test
            )

            all_succeeded &= success
        elseif !(old_test_res isa Nothing) && !haskey(test_res.metrics, $metric) && haskey(test_res.primitives, $metric) && haskey(old_test_res.primitives, $metric)
            ratio = test_res.primitives[$metric] / old_test_res.primitives[$metric]
            success = $success_expr

            result = newMetricResult($mode,
                                    name=$("$metric Difference"),
                                    units="%",
                                    value=ratio * 100
            )
            test = Metric_Test(
                reference=100.0,
                threshold_min_percent=$(threshold) * 100,
                threshold_max_percent=nothing,
                low_is_bad=$(low_is_bad),
                succeeded=success,
                custom_plotting=Symbol[],
                full_print=true
            )

            push!(methodology_res.metrics, (result => test))

            # Register tracked metric in auxiliar group for later usage in Bencher
            methodology_res.custom_elements[$metric] = (newMetricResult(
                $mode,
                name=$("$metric"),
                units="s",
                value=test_res.primitives[$metric]) => test
            )

            all_succeeded &= success
        end
        if Configuration.CONFIG["general"]["verbose"] >= 2 && !(old_test_res isa Nothing)
            methodology_res.custom_elements[:reference] = newMetricResult(
                $mode,
                name=$("$metric Reference value"),
                units=haskey(old_test_res.metrics, $metric) ? old_test_res.metrics[$metric].units : "s",
                value=haskey(old_test_res.metrics, $metric) ? old_test_res.metrics[$metric].value : (haskey(old_test_res.primitives, $metric) ? old_test_res.primitives[$metric] : NaN)
            )
        end
        methodology_res.custom_elements[$metric] = (newMetricResult(
            $mode,
            name=$("$metric"),
            units=haskey(test_res.metrics, $metric) ? test_res.metrics[$metric].units : "s",
            value=haskey(test_res.metrics, $metric) ? test_res.metrics[$metric].value : (haskey(test_res.primitives, $metric) ? test_res.primitives[$metric] : NaN)
        ))
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
                    regression(info[:metrics], info[:threshold], info[:low_is_bad])
                else
                    q = quote end;
                    for (i, metric) in enumerate(info[:metrics])
                        q = quote
                            $q;
                            $(regression(metric, info[:threshold][i], info[:low_is_bad][i]))
                        end
                    end;
                    q
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
