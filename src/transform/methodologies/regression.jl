
"""
Thresholds of a @regression that gives none, one for each of its metrics from regression.default_threshold: the
threshold itself for a metric where a high value is bad (low_is_bad = false, e.g. a time), and 2 − threshold for one
where a low value is bad (low_is_bad = true, e.g. a throughput). The default 1.1 thus tolerates a time up to 10% higher,
and a throughput up to 10% lower (0.9), than the reference. 2 − threshold is computed on the decimal value it is written
with, so 1.1 gives exactly 0.9.

A regression.default_threshold of 2 or more leaves no threshold for a metric where a low value is bad, it is reported as
a parse error naming where it comes from.
"""
function defaultRegressionThresholds(metrics::AbstractVector, low_is_bad, ctx::Context)::Vector{Float64}
    threshold = Configuration.CONFIG["regression"]["default_threshold"]
    # An Int as well, the type of the key is Number
    high_is_bad = Float64(threshold)
    low_is_bad_th = Float64(2 - parse(BigFloat, string(high_is_bad)))

    # Already reported when it does not match the metrics, see onRegressionDefinition
    if !(low_is_bad isa AbstractVector && length(low_is_bad) == length(metrics))
        return fill(high_is_bad, length(metrics))
    end

    low = [metric for (metric, lib) in zip(metrics, low_is_bad) if lib === true]
    if !isempty(low) && threshold >= 2
        throwParseError!("Invalid regression threshold in the @regression of recipe $(ctx._global.original_file_path): it gives " *
                         "no threshold, so $(join(repr.(low), ", ")), where a low value is bad (low_is_bad = true), would " *
                         "take 2 − regression.default_threshold, but regression.default_threshold = $(repr(threshold)) (from " *
                         "$(Configuration.source_of("regression.default_threshold"))) gives 2 − $(repr(threshold)) = " *
                         "$(repr(low_is_bad_th)), which every ratio new/reference passes. Give that @regression an explicit " *
                         "threshold (threshold=..., the ratio new/reference a metric with low_is_bad = true must stay above), " *
                         "or set regression.default_threshold below 2", ctx)
    end
    return [lib === true ? low_is_bad_th : high_is_bad for lib in low_is_bad]
end

plural(n::Integer, word::AbstractString) = "$n $word$(n == 1 ? "" : "s")"
literalList(values) = "[" * join(repr.(values), ", ") * "]"

"""
Report as a parse error that `key` (:low_is_bad or :threshold) of a @regression is a vector that does not give one
value per metric, see onRegressionDefinition.
"""
function reportRegressionLengthMismatch(key::Symbol, single::Type, value::AbstractVector, metrics::AbstractVector, ctx::Context)
    throwParseError!("Invalid $key in the @regression of recipe $(ctx._global.original_file_path): $key = $(literalList(value)) " *
                     "gives $(plural(length(value), "value")) for $(plural(length(metrics), "metric")) ($(join(repr.(metrics), ", "))). " *
                     "$key is either a single $single, which applies to every metric, or a vector with one $single per " *
                     "metric, in the order of metrics", ctx)
end

"""

Called when a regression macro is detected, sets up the regression methodology. Without a threshold, the thresholds
come from regression.default_threshold, see defaultRegressionThresholds.

low_is_bad and threshold are each either a single value, which applies to every metric, or a vector with one value per
metric. A vector of another length is reported as a parse error, as is the metric :autoflop (see AUTOFLOP_UNSUPPORTED),
and the macro is then ignored so the transform goes on collecting the errors of the recipe.

"""
function onRegressionDefinition(_::ExtendedExpr, ctx::Context, info)
    if !(Configuration.CONFIG["regression"]["enabled"])
        return
    end
    # Its validation already reported the arguments it could not read, e.g. too many of them
    info === nothing && return

    given_threshold = haskey(info, :threshold)
    if haskey(info, :metrics)
    else
        info[:metrics] = :median_time
    end
    if haskey(info, :low_is_bad)
    else
        info[:low_is_bad] = false
    end
    if haskey(info, :showvar)
    else
        info[:showvar] = false
    end
    # vvvv Verify that parameters make sense among each other vvvv
    info[:metrics] = info[:metrics] isa metricID() ? [metricID(info[:metrics])] : [metricID(m) for m in info[:metrics]]
    consistent = true
    # One value for each metric
    for (key, single) in ((:low_is_bad, Bool), (:threshold, Float64))
        if key === :threshold && !given_threshold
            continue
        elseif !(info[key] isa AbstractVector)
            info[key] = fill(info[key], length(info[:metrics]))
        elseif length(info[key]) != length(info[:metrics])
            reportRegressionLengthMismatch(key, single, info[key], info[:metrics], ctx)
            consistent = false
        end
    end
    if !given_threshold
        # One for each metric, following its low_is_bad
        info[:threshold] = defaultRegressionThresholds(info[:metrics], info[:low_is_bad], ctx)
    end
    # ^^^^ Verify that parameters make sense among each other ^^^^
    for metric in info[:metrics]
        if metric === :autoflop
            reportAutoflopUse!("The @regression", "tracks the metric :autoflop", ctx;
                               instead = "Track a metric defined with @define_metric from the flop count of the target " *
                                         "instead, or pass the flop count to @roofline with actual_flops.")
            consistent = false
        elseif !(metric in formula_symbols) && !isCustomMetricDefined(ctx, metric)
            # Referred to by its name, but defined with another symbol
            named = customMetricByName(ctx, metric)
            hint = named === nothing ? "" : " The metric named $(repr(named.name)) is referred to by its symbol $(repr(named.symbol))."
            throwParseError!("Metric $metric is not available in the current context.$hint", ctx)
        end
    end
    # Already reported, the suite is not generated
    consistent || return

    existing_idx = findfirst(m -> m.id == :regression, ctx._local.enabled_methodologies[end])
    if existing_idx === nothing
        push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
            id=:regression,
            name="Metric regression tracking",
            override=false,
            params=info,
        ))
    else
        # Extend in place: a second entry in the same scope would lose to the first under captureMethodologyInfo's first-key-wins merge.
        existing_params = ctx._local.enabled_methodologies[end][existing_idx].params
        # showvar is a scalar (not per-metric), so a redeclaration simply overwrites it.
        existing_params[:showvar] = info[:showvar]
        for (metric, threshold, low_is_bad) in zip(info[:metrics], info[:threshold], info[:low_is_bad])
            metric_idx = findfirst(==(metric), existing_params[:metrics])
            if metric_idx === nothing
                push!(existing_params[:metrics], metric)
                push!(existing_params[:threshold], threshold)
                push!(existing_params[:low_is_bad], low_is_bad)
            else
                # Same metric declared again: drop the old parameters, keep the new ones.
                existing_params[:threshold][metric_idx] = threshold
                existing_params[:low_is_bad][metric_idx] = low_is_bad
            end
        end
    end

    addLog("metrics", "[METHODOLOGY] Defined REGRESSION on $([i.set_name for i in ctx._local.depth_record]) METRICS: $(info[:metrics]) TH: $(info[:threshold]) LOW_IS_BAD: $(info[:low_is_bad])")
end


"""
 Executes regression for one single metric
"""
function regression(metric :: Symbol, threshold::Float64, low_is_bad::Bool, showvar::Bool)
    metric = QuoteNode(metric)

    success_expr = :($(low_is_bad ? :(>) : :(<))(ratio ,$(threshold)))
    return quote
        if haskey(test_res.metrics, $metric) && !(old_test_res isa Nothing) && haskey(old_test_res.metrics, $metric)
            ratio_sv = metricSampledValue(test_res.metrics[$metric]) / metricSampledValue(old_test_res.metrics[$metric])
            ratio = ratio_sv isa SampledValue ? ratio_sv.value : ratio_sv
            success = $success_expr

            result = newMetricResult($mode,
                                    name=$("$metric Difference"),
                                    units="%",
                                    value=ratio_sv * 100,
                                    showvar=$(showvar)
            )
            test = Metric_Test(
                reference=100.0,
                threshold_min_percent=$(threshold) * 100,
                threshold_max_percent=nothing,
                low_is_bad=$(low_is_bad),
                succeeded=success,
                custom_plotting=Symbol[],
                full_print=true,
                showvar=$(showvar)
            )

            push!(methodology_res.metrics, (result => test))

            # Register tracked metric in auxiliar group for later usage in Bencher
            methodology_res.custom_elements[$metric] =  (newMetricResult(
                $mode,
                name=test_res.metrics[$metric].name,
                units=test_res.metrics[$metric].units,
                value=metricSampledValue(test_res.metrics[$metric]),
                showvar=$(showvar)) => test
            )

            all_succeeded &= success
        elseif !(old_test_res isa Nothing) && !haskey(test_res.metrics, $metric) && haskey(test_res.primitives, $metric) && haskey(old_test_res.primitives, $metric)
            ratio_sv = test_res.primitives[$metric] / old_test_res.primitives[$metric]
            ratio = ratio_sv isa SampledValue ? ratio_sv.value : ratio_sv
            success = $success_expr

            result = newMetricResult($mode,
                                    name=$("$metric Difference"),
                                    units="%",
                                    value=ratio_sv * 100,
                                    showvar=$(showvar)
            )
            test = Metric_Test(
                reference=100.0,
                threshold_min_percent=$(threshold) * 100,
                threshold_max_percent=nothing,
                low_is_bad=$(low_is_bad),
                succeeded=success,
                custom_plotting=Symbol[],
                full_print=true,
                showvar=$(showvar)
            )

            push!(methodology_res.metrics, (result => test))

            # Register tracked metric in auxiliar group for later usage in Bencher
            methodology_res.custom_elements[$metric] = (newMetricResult(
                $mode,
                name=$("$metric"),
                units="s",
                value=test_res.primitives[$metric],
                showvar=$(showvar)) => test
            )

            all_succeeded &= success
        end
        if Configuration.CONFIG["general"]["verbose"] >= 2 && !(old_test_res isa Nothing)
            methodology_res.custom_elements[:reference] = newMetricResult(
                $mode,
                name=$("$metric Reference value"),
                units=haskey(old_test_res.metrics, $metric) ? old_test_res.metrics[$metric].units : "s",
                value=haskey(old_test_res.metrics, $metric) ? metricSampledValue(old_test_res.metrics[$metric]) : (haskey(old_test_res.primitives, $metric) ? old_test_res.primitives[$metric] : NaN),
                showvar=$(showvar)
            )
        end
        methodology_res.custom_elements[$metric] = (newMetricResult(
            $mode,
            name=$("$metric"),
            units=haskey(test_res.metrics, $metric) ? test_res.metrics[$metric].units : "s",
            value=haskey(test_res.metrics, $metric) ? metricSampledValue(test_res.metrics[$metric]) : (haskey(test_res.primitives, $metric) ? test_res.primitives[$metric] : NaN),
            showvar=$(showvar)
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
                    regression(info[:metrics], info[:threshold], info[:low_is_bad], info[:showvar])
                else
                    q = quote end;
                    for (i, metric) in enumerate(info[:metrics])
                        q = quote
                            $q;
                            $(regression(metric, info[:threshold][i], info[:low_is_bad][i], info[:showvar]))
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
