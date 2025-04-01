using UnicodePlots: lines!, height
using MacroTools: blockunify
using Configurations: ExproniconLite
using UnicodePlots

function rooflineCalc(peakCPU :: Float64, peakMem :: Float64)
    return (opint) -> min(peakCPU, opint * peakMem)
end


"""

Called when a roofline macro is detected, sets up the roofline methodology

"""
function onRooflineDefinition(formula :: ExtendedExpr, ctx :: Context, info)
    if !(Configuration.CONFIG["roofline"]["enabled"])
        return
    end

    # Adds to the inner scope the request to build the methodology and its needed metrics
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name="Operational intensity",
        units="Flop/Byte",
        formula=transformFormula(formula, ctx),
        symbol=:opInt
    ))
    # Is there a flop definition?
    if haskey(info, :actual_flops)
        local form = transformFormula(quote
            $(info[:actual_flops]) / :median_time
        end, ctx)
        # Can we put the autoflops or shall we construct a partial model?
    elseif Configuration.CONFIG["autoflops"]
        local form = transformFormula(quote
	          :autoflop / :median_time
        end, ctx)
    else
        # Incomplete model
        local form = quote
            0
        end
        info[:test_flop] = false
    end
    #Is there a defined ratio as the test threshold?
    if haskey(info, :target_ratio)
    else
        info[:target_ratio] = Configuration.CONFIG["roofline"]["default_threshold"]
    end
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name="Attained Flops",
        units="FLOP/s",
        formula=form,
        symbol=:attainedFLOPS
    ))
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id=:roofline,
        name="Roofline Model",
        override=true,
        params=info,
    ))


    addLog("metrics", "[METHODOLOGY] Defined ROOFLINE MODEL on $([i.set_name for i in ctx._local.depth_record])")
end


"""
  Returns an expression used to generate and evaluate a roofline model over a test target
"""
function buildRoofline(context::Context)::Expr

    info = captureMethodologyInfo(:roofline, context._local.enabled_methodologies)

    if info isa Nothing
        return quote end
    else
        info = info.params
        return quote
            let
                opint = _PRFT_LOCAL[:metrics][:opInt].value
                flop_s = _PRFT_LOCAL[:metrics][:attainedFLOPS].value

                roof = PerfTest.rooflineCalc(_PRFT_GLOBAL[:machine][:empirical][:peakflops], _PRFT_GLOBAL[:machine][:empirical][:peakmemBW][$(QuoteNode(info[:mem_benchmark]))])

                result_flop_ratio = newMetricResult(
                    $mode,
                    name="Attained FLOP/S by expected FLOP/S",
                    units="%",
                    value=flop_s / roof(opint) * 100
                )

                methodology_res = Methodology_Result(
                    name="Roofline Model"
                )

                $(if info[:test_flop]
                      quote
                          success_flop = result_flop_ratio.value >= $(info[:target_ratio])

                          flop_test = Metric_Test(
                              reference=100,
                              threshold_min_percent = $(info[:target_ratio]),
                              threshold_max_percent = nothing,
                              low_is_bad = true,
                              succeeded = success_flop,
                              custom_plotting = Symbol[],
                              full_print=true
                          )
                          push!(methodology_res.metrics, (result_flop_ratio => flop_test))
                      end
                else
                      quote
                      end
                end)
                methodology_res.custom_elements[:realf] = magnitudeAdjust(_PRFT_LOCAL[:metrics][:attainedFLOPS])

                methodology_res.custom_elements[:opint] = _PRFT_LOCAL[:metrics][:opInt]
                # result_opint = _PRFT_LOCAL[:metrics][:opint]
                # if info.[:test_opint]

                # else

                # end

                aux_mem = newMetricResult(
                    $mode,
                    name="Peak empirical bandwidth",
                    units="B/s",
                    value=_PRFT_GLOBAL[:machine][:empirical][:peakmemBW][$(QuoteNode(info[:mem_benchmark]))]
                )
                aux_flops = newMetricResult(
                    $mode,
                    name="Peak empirical flops",
                    units="FLOP/s",
                    value=_PRFT_GLOBAL[:machine][:empirical][:peakflops]
                )
                aux_rcorner = newMetricResult(
                    $mode,
                    name="Roofline Corner",
                    units="Flop/Byte",
                    value=aux_flops.value/aux_mem.value
                )
                methodology_res.custom_elements[:mem_peak] = magnitudeAdjust(aux_mem)
                methodology_res.custom_elements[:cpu_peak] = magnitudeAdjust(aux_flops)
                methodology_res.custom_elements[:roof_corner] = magnitudeAdjust(aux_rcorner)
                methodology_res.custom_elements[:roof_corner_raw] = aux_rcorner
                methodology_res.custom_elements[:factor] = $(info[:target_ratio])


                methodology_res.custom_elements[:plot] = PerfTest.printFullRoofline

                # Printing
                if $(Configuration.CONFIG["general"]["verbose"]) || !(flop_test.succeeded)
                    PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)), $(Configuration.CONFIG["general"]["plotting"]))
                end

                # Saving
                push!(by_index(_PRFT_GLOBAL[:new], _PRFT_LOCAL[:depth]).methodology_results, methodology_res)

                # Testing
                try
                    @test flop_test.succeeded
                catch end
            end
        end
    end
end

