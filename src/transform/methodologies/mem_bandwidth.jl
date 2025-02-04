

function onMemoryThroughputDefinition(formula :: ExtendedExpr, ctx :: Context, info)

    if !(ctx._global.configuration["memory_bandwidth"]["enabled"])
        return
    end
    if haskey(info, :ratio)
    else
        info[:ratio] = ctx._global.configuration["memory_bandwidth"]["default_threshold"]
    end
    # Adds to the inner scope the request to build the methodology and its needed metric
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name="Effective memory throughput",
        units="GB/s",
        formula=formula,
        symbol=:effMemTP
    ))
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id = :effMemTP,
        name = "Effective memory throughput",
        override = true,
        params = info,
    ))
end


function buildMemTRPTMethodology(context :: Context)::Expr

    info = captureMethodologyInfo(:effMemTP, context._local.enabled_methodologies)

    if info isa Nothing
        return quote end
    else
        return quote
	          let
                value = _PRFT_LOCAL[:metrics][:effMemTP].value / _PRFT_GLOBAL[:machine][:empirical][:peakmemBW]
                success = value >= $(info.params[:ratio])

                result = newMetricResult($mode,
                                       name="Effective Throughput Ratio",
                                       units="%",
                                       value=value*100)
                test = Metric_Test(
                    reference=100,
                    threshold_min_percent=$(info.params[:ratio]),
                    threshold_max_percent=1.0,
                    low_is_bad=true,
                    succeeded=success,
                    custom_plotting=Symbol[],
                    full_print=true
                )

                # Absolute value as an additional metric
                aux_abs_value = newMetricResult(
                    $mode,
                    name="Attained Bandwidth",
                    units="GB/s",
                    value=_PRFT_LOCAL[:metrics][:effMemTP].value
                )
                aux_ref_value = newMetricResult(
                    $mode,
                    name="Peak empirical bandwidth",
                    units="GB/s",
                    value=_PRFT_GLOBAL[:machine][:empirical][:peakmemBW]
                )

                # Save results and auxiliary measurements
                methodology_res = Methodology_Result(
                    name="Effective Memory Throughput",
                )
                push!(methodology_res.metrics, (result => test))
                methodology_res.custom_elements[:abs] = magnitudeAdjust(aux_abs_value)
                methodology_res.custom_elements[:abs_ref] = magnitudeAdjust(aux_ref_value)

                # Printing
                if $(context._global.configuration["general"]["verbose"]) || !(flop_test.succeeded)
                    PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)), $(context._global.configuration["general"]["plotting"]))
                end

                # Saving TODO

                # Testing
                @test test.succeeded
            end
        end
    end
end
