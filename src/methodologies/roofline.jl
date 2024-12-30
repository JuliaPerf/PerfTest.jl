using UnicodePlots: lines!, height
using MacroTools: blockunify
using Configurations: ExproniconLite


# THIS FILE SAVES THE MAIN COMPONENTS OF THE ROOFLINE
# METHODOLOGY BEHAVIOUR

# GENERATED SPACE IMPORTANT SYMBOLS:
#
# roofline_opint
# local_peakflops
# local_peakbandwidth



function rooflineCalc(peakCPU :: Float64, peakMem :: Float64)
    return (opint) -> min(peakCPU, opint * peakMem)
end



using UnicodePlots

# rooflineFunc = (maxflops, maxbandwidth) -> (opint -> min(maxflops, maxbandwidth * opint))

# # Additional printing behaviour
# function printRoofline(_roofline :: Methodology_Result)

#     if roofline.plotting
#         p = lineplot(0, _roofline.custom_elements[:roof_corner].value * 2.,
#                      rooflineFunc(_roofline.custom_elements[:cpu_peak].value,
#                                   _roofline.custom_elements[:mem_peak].value), name="Automatic Roofline")

#         vline!(p, _roofline.metrics[1].first.value, color=:cyan, name="Tested function")

#         show(print(p))
#         println("")
#     end
# end

# # Additional printing behaviour


# """
#   Parses roofline user request and sets up data for
#   roofline computation.
# """
# function rooflineMacroParse(x::Expr, ctx::Context)::Expr
#     if roofline.enabled
#         peakflops = nothing
#         peakbandwidth = nothing
#         target_ratio = nothing

#         actual_flops_expr = nothing


#         # Enables local roofline model construction
#         ctx.env_flags.roofline_prefix = true

#         # Capture needed args
#         for arg in x.args
#             # Is macro kwarg?
#             if arg isa Expr && arg.head == Symbol("=")
#                 if arg.args[1] == Symbol("cpu_peak")
#                     peakflops = eval(arg.args[2])
#                 elseif arg.args[1] == Symbol("target_opint")
#                     #TODO
#                 elseif arg.args[1] == Symbol("target_ratio")
#                     target_ratio = eval(arg.args[2])
#                     @show target_ratio, arg.args[2]
#                 elseif arg.args[1] == Symbol("membw_peak")
#                     peakbandwidth = eval(arg.args[2])
#                 elseif arg.args[1] == Symbol("actual_flops")
#                     if arg.args[2] isa Expr && arg.args[2].head == :block
#                         actual_flops_expr = fullParsingSuite(arg.args[2])
#                     end
#                     actual_flops_expr = fullParsingSuite(Meta.quot(arg.args[2]))
#                 end
#             end
#         end
#         # Last is the operational intensity BLOCK
#         if x.args[end].head == :block
#             t = fullParsingSuite(x.args[end])
#         else
#             error("Malformed @roofline, opint must be in block format")
#         end

#         ctx.local_injection = quote
#             $(ctx.local_injection)
#             roofline_opint = $t
#             $(if actual_flops_expr != nothing
#                   ctx.env_flags.roofline_full = true
#                   quote
#                       local_actual_flops_expr = $(eval(actual_flops_expr))
#                   end
#               else
#                   quote end
#               end)
#             local_peakflops = $(peakflops == nothing ? :(peakflops) : peakflops)
#             local_peakbandwidth = $(peakbandwidth == nothing ? :(peakbandwidth) : peakbandwidth)
#             local_target_ratio = $target_ratio
#         end
#     end
#     return quote
#         begin end
#     end
# end

function onRooflineDefinition(formula :: ExtendedExpr, ctx :: Context, info)
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
    elseif CONFIG.autoflops
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
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name="Attained Flops",
        units="FLOP/s",
        formula=form,
        symbol=:attainedFLOPS
    ))
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id = :roofline,
        name = "Roofline Model",
        override = true,
        params = info,
    ))
end

function buildRoofline(context::Context)::Expr

    info = captureMethodologyInfo(:roofline, context._local.enabled_methodologies)
    if info isa Nothing
        return quote end
    else
        return quote
            let
                opint = _PRFT_LOCAL[:metrics][:opInt].value
                flop_s = _PRFT_LOCAL[:metrics][:attainedFLOPS].value

                roof = PerfTest.rooflineCalc(_PRFT_GLOBAL[:machine][:empirical][:peakflops], _PRFT_GLOBAL[:machine][:empirical][:peakmemBW])

                result_flop_ratio = Metric_Result(
                    name="Attained FLOP/S by expected FLOP/S",
                    units="%",
                    value=flop_s / roof(opint) * 100
                )

                methodology_res = Methodology_Result(
                    name="Roofline Model"
                )

                $(if info.params[:test_flop]
                      quote
                          success_flop = result_flop_ratio.value >= $(info.params[:target_ratio])

                          flop_test = Metric_Test(
                              reference=100,
                              threshold_min_percent = $(info.params[:target_ratio]),
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
                # if info.params[:test_opint]

                # else

                # end

                aux_mem = Metric_Result(
                    name="Peak empirical bandwidth",
                    units="B/s",
                    value=_PRFT_GLOBAL[:machine][:empirical][:peakmemBW]
                )
                aux_flops = Metric_Result(
                    name="Peak empirical flops",
                    units="FLOP/s",
                    value=_PRFT_GLOBAL[:machine][:empirical][:peakflops]
                )
                aux_rcorner = Metric_Result(
                    name="Roofline Corner",
                    units="Flop/Byte",
                    value=aux_flops.value/aux_mem.value
                )
                methodology_res.custom_elements[:mem_peak] = magnitudeAdjust(aux_mem)
                methodology_res.custom_elements[:cpu_peak] = magnitudeAdjust(aux_flops)
                methodology_res.custom_elements[:roof_corner] = magnitudeAdjust(aux_rcorner)
                methodology_res.custom_elements[:roof_corner_raw] = aux_rcorner
                methodology_res.custom_elements[:factor] = $(info.params[:target_ratio])


                methodology_res.custom_elements[:plot] = PerfTest.printFullRoofline

                #     methodology_result.custom_elements[:factor] = local_target_ratio

                # Printing
                PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)))

                # Saving TODO

                # Testing
                @test flop_test.succeeded
            end
        end
    end
end

function rooflineEvaluation(context::Context)::Expr

    return quote :ROOFLINEEVAL end

    # CONFIG.roofline.enabled && context.env_flags.roofline_prefix ? (
    #     if context.env_flags.roofline_full
    #         context.env_flags.roofline_full = false;
    #         fullRooflineEvaluation(context)
    #     else
    #     context.env_flags.roofline_prefix = false; quote
    #     # Threshold
    #     _min = $(roofline.tolerance.min_percentage)
    #     _max = $(roofline.tolerance.max_percentage)

    #         result = PerfTest.Metric_Result(
    #             name="OPERATIONAL INTENSITY",
    #             units="FLOP/Byte",
    #             value=roofline_opint
    #         )



    #         # Setup result collecting struct
    #         methodology_result = PerfTest.Methodology_Result(
    #             name="ROOFLINE",
    #             metrics=Pair{PerfTest.Metric_Result,PerfTest.Metric_Constraint}[],
    #         )

    #     # MEM LIMIT TO CPU LIMIT THRESHOLD (used as the reference for bounded tests)
    #     ref = local_peakflops / local_peakbandwidth

    #     # Ratio
    #     ratio = result.value / ref
    #     @warn "$ratio"
    #     # test
    #     _test = _min < result.value < _max


    #     constraint = PerfTest.Metric_Constraint(
    #         reference=ref,
    #         threshold_min=_min * ref,
    #         threshold_min_percent=_min,
    #         threshold_max=_max * ref,
    #         threshold_max_percent=_max,
    #         low_is_bad=true,
    #         succeeded=_test, custom_plotting=Symbol[],
    #         full_print=$(verbose ? :(true) : :(!_test))
    #     )



    #     cpu_peak = PerfTest.Metric_Result(
    #         name="Peak CPU flops",
    #         units="GFlops/s",
    #         value=local_peakflops
    #     )
    #     methodology_result.custom_elements[:cpu_peak] = cpu_peak
    #     mem_peak = PerfTest.Metric_Result(
    #         name="Peak memory bandwidth",
    #         units="GB/s",
    #         value=local_peakbandwidth
    #     )
    #     methodology_result.custom_elements[:mem_peak] = mem_peak
    #         #push!(methodology_result.custom_elements, (:plot => plotexpr))
    #     limit_mem_b = PerfTest.Metric_Result(
    #         name="Is memory limited?",
    #         units="Yes/No",
    #         value= ratio > (local_peakflops / local_peakbandwidth) ? "NO" : "YES"
    #     )
    #     methodology_result.custom_elements[:mem_lim] = limit_mem_b
    #     roof_corner = PerfTest.Metric_Result(
    #         name="Roofline corner",
    #         units="FLOP/Byte",
    #         value= local_peakflops / local_peakbandwidth
    #     )
    #     methodology_result.custom_elements[:roof_corner] = roof_corner

    #         methodology_result.custom_elements[:plot] = PerfTest.printFullRoofline

    #     $(checkAuxiliaryCustomMetrics(context))

    #     push!(methodology_result.metrics, (result => constraint))

    #     PerfTest.printMethodology(methodology_result, $(length(context.depth)))
    #     # Register metric results TODO
    #     current_test_results[:roofline] = methodology_result

    #     @test _test
    # end end) : quote
    #     begin end
    # end
end



function fullRooflineEvaluation(context::Context)::Expr
    #context.env_flags.roofline_prefix = false
    return quote :FULLROOFEVAL end
    # return quote
    #     # Threshold
    #     _min = $(roofline.tolerance.min_percentage)
    #     _max = $(roofline.tolerance.max_percentage)


    #     # Setup result collecting struct
    #     methodology_result = PerfTest.Methodology_Result(
    #         name="ROOFLINE",
    #         metrics=Pair{PerfTest.Metric_Result,PerfTest.Metric_Constraint}[],
    #     )



    #     elapsed = PerfTest.by_index(median_suite, depth).time
    #     result = PerfTest.Metric_Result(
    #         name="Real Performance vs Model performance",
    #         units="Flops/Flops",
    #         value=(local_actual_flops_expr / elapsed) / min(roofline_opint * local_peakbandwidth, local_peakflops)
    #     )
    #     operational_intensity_result = PerfTest.Metric_Result(
    #             name="OPERATIONAL INTENSITY",
    #             units="FLOP/Byte",
    #             value=roofline_opint
    #         )

    #     methodology_result.custom_elements[:opint] = operational_intensity_result
    #     methodology_result.custom_elements[:realf] = PerfTest.Metric_Result(
    #         name="Real Performance",
    #         units="GFlops",
    #         value=local_actual_flops_expr / elapsed)


    #     ref = local_target_ratio

    #     # Ratio
    #     ratio = result.value
    #     # test
    #     _test = _max * ref < ratio < _min * ref


    #     constraint = PerfTest.Metric_Constraint(
    #         reference=ref,
    #         threshold_min=_min * ref,
    #         threshold_min_percent=_min,
    #         threshold_max=_max * ref,
    #         threshold_max_percent=_max,
    #         low_is_bad=true,
    #         succeeded=_test, custom_plotting=Symbol[],
    #         full_print=$(verbose ? :(true) : :(!_test))
    #     )



    #     cpu_peak = PerfTest.Metric_Result(
    #         name="Peak CPU flops",
    #         units="GFlops/s",
    #         value=local_peakflops
    #     )
    #     methodology_result.custom_elements[:cpu_peak] = cpu_peak
    #     mem_peak = PerfTest.Metric_Result(
    #         name="Peak memory bandwidth",
    #         units="GB/s",
    #         value=local_peakbandwidth
    #     )
    #     methodology_result.custom_elements[:mem_peak] = mem_peak
    #     #push!(methodology_result.custom_elements, (:plot => plotexpr))
    #     limit_mem_b = PerfTest.Metric_Result(
    #         name="Is memory limited?",
    #         units="Yes/No",
    #         value= operational_intensity_result.value > (local_peakflops / local_peakbandwidth) ? "NO" : "YES"
    #     )
    #     methodology_result.custom_elements[:mem_lim] = limit_mem_b
    #     roof_corner = PerfTest.Metric_Result(
    #         name="Roofline corner",
    #         units="FLOP/Byte",
    #         value=local_peakflops / local_peakbandwidth
    #     )
    #     t = PerfTest.Metric_Result(
    #         name="Time",
    #         units="ns",
    #         value= elapsed
    #     )
    #         methodology_result.custom_elements[:t] = t
    #     methodology_result.custom_elements[:roof_corner] = roof_corner

    #     methodology_result.custom_elements[:plot] = PerfTest.printFullRoofline

    #     methodology_result.custom_elements[:factor] = local_target_ratio

    #     $(checkAuxiliaryCustomMetrics(context))

    #     push!(methodology_result.metrics, (result => constraint))

    #     PerfTest.printMethodology(methodology_result, $(length(context.depth)))
    #     # Register metric results TODO
    #     current_test_results[:roofline] = methodology_result

    #     @test _test
    # end
end
