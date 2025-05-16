

using Base: quoted_syms
"""

Called when a effective memory throughput macro is detected, sets up the effective memory throughput methodology

"""
function onMemoryThroughputDefinition(formula::ExtendedExpr, ctx::Context, info)

    if !(Configuration.CONFIG["memory_bandwidth"]["enabled"])
        return
    end
    if haskey(info, :ratio)
    else
        info[:ratio] = Configuration.CONFIG["memory_bandwidth"]["default_threshold"]
    end
    # Check if the user wants to use a custom benchmark
    if haskey(info, :custom_benchmark)
        info[:custom] = true
	@show ctx._global.custom_benchmarks
        # Check TODO if custom b. has been defined
        if !( info[:custom_benchmark] in ctx._global.custom_benchmarks)
            throwParseError!("Undefined custom benchmark $(info[:custom_benchmark])", ctx)
        end
    else
        info[:custom] = false
    end
    # Adds to the inner scope the request to build the methodology and its needed metric
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name="Effective memory throughput",
        units="GB/s",
        formula=formula,
        symbol=:effMemTP
    ))
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id=:effMemTP,
        name="Effective memory throughput",
        override=true,
        params=info,
    ))
    return quote end
end


"""
  Returns an expression used to evaluate the effective memory throughput over a test target
"""
function buildMemTRPTMethodology(context :: Context)::Expr

    info = captureMethodologyInfo(:effMemTP, context._local.enabled_methodologies)

    if info isa Nothing
        return quote end
    else
        info = info.params
        return quote
	          let
                reference_benchmark = $(!info[:custom]
                                        ? :(_PRFT_GLOBALS.builtins[$(QuoteNode(info[:mem_benchmark]))])
                                        : :(_PRFT_GLOBALS.custom_benchmarks[$(QuoteNode(info[:custom_benchmark]))]))

                value = test_res.metrics[:effMemTP].value / reference_benchmark
                success = value >= $(info[:ratio])
                result = newMetricResult($mode,
                                       name="Effective Throughput Ratio",
                                       units="%",
                                       value=value*100)
                test = Metric_Test(
                    reference=100,
                    threshold_min_percent=$(info[:ratio]),
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
                    units="B/s",
		    value=test_res.metrics[:effMemTP].value
                )
                aux_ref_value = newMetricResult(
                    $mode,
                    name="Peak empirical bandwidth",
                    units="B/s",
                    value=reference_benchmark
                )

                # Save results and auxiliary measurements
                methodology_res = Methodology_Result(
                    name="Effective Memory Throughput",
                )
                push!(methodology_res.metrics, (result => test))
                methodology_res.custom_elements[:abs] = magnitudeAdjust(aux_abs_value)
                methodology_res.custom_elements[:abs_ref] = magnitudeAdjust(aux_ref_value)

                # Printing
                if $(Configuration.CONFIG["general"]["verbose"]) || !(test.succeeded)
                    PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)), $(Configuration.CONFIG["general"]["plotting"]))
                end


                # Testing
                @test test.succeeded
                saveMethodologyData(test_res.name, methodology_res)
            end
        end
    end
end
