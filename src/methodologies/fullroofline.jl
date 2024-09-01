
# THIS FILE SAVES THE MAIN COMPONENTS OF THE ROOFLINE
# METHODOLOGY BEHAVIOUR

# GENERATED SPACE IMPORTANT SYMBOLS:
#
# roofline_opint
# local_peakflops
# local_peakbandwidth


using UnicodePlots

rooflineFunc = (maxflops, maxbandwidth) -> (opint -> min(maxflops, maxbandwidth * opint))



"""
  Parses roofline user request and sets up data for
  roofline computation.
"""
function fullRooflineMacroParse(x::Expr, ctx::Context)::Expr
    if roofline.enabled
        peakflops = nothing
        peakbandwidth = nothing
        actual_flops_expr = nothing


        # Enables local roofline model construction
        ctx.env_flags.roofline_prefix = true

        # Capture needed args
        for arg in x.args
            # Is macro kwarg?
            if arg isa Expr && arg.head == Symbol("=")
                if arg.args[1] == Symbol("cpu_peak")
                    peakflops = eval(arg.args[2])
                elseif arg.args[1] == Symbol("target_opint")
                    #TODO
                elseif arg.args[1] == Symbol("membw_peak")
                    peakbandwidth = eval(arg.args[2])
                elseif arg.args[1] == Symbol("actual_flops")
                    if arg.args[2] isa Expr && arg.args[2].head == :block
                        @warn "OU YEAH"
                        actual_flops_expr = fullParsingSuite(arg.args[2])
                    end
                end
            end
        end
        # Last is the operational intensity BLOCK
        if x.args[end].head == :block
            t = fullParsingSuite(x.args[end])
        else
            error("Malformed @roofline, opint must be in block format")
        end

        ctx.local_injection = quote
            $(ctx.local_injection)
            roofline_opint = $t
            $(if actual_flops_expr != nothing
                  ctx.env_flags.roofline_full = true
                  quote
                      local_actual_flops_expr = $actual_flops_expr
                  end
              else
                  quote end
              end)
            local_peakflops = $(peakflops == nothing ? :(peakflops) : peakflops)
            local_peakbandwidth = $(peakbandwidth == nothing ? :(peakbandwidth) : peakbandwidth)
        end
    end
    return quote
        begin end
    end
end

function rooflineEvaluation(context::Context)::Expr
    return roofline.enabled && context.env_flags.roofline_prefix ? (
        context.env_flags.roofline_prefix = false; quote
        # Threshold
        min = $(roofline.tolerance_around_memcpu_intersection.min_percentage)
        max = $(roofline.tolerance_around_memcpu_intersection.max_percentage)

            result = PerfTest.Metric_Result(
                name="OPERATIONAL INTENSITY",
                units="FLOP/Byte",
                value=roofline_opint
            )


            $(
                if context.env_flags.roofline_full
                    quote
                        operational_intensity_result = result
                        result = PerfTest.Metric_Result(
                            name="Real Performance vs Model performance",
                            units="[%(real/model)]",
                            value=local_actual_flops_expr / minimum(roofline_opint * mem_peak, cpu_peak)
                        )
                        methodology_result.custom_elements[:opint] = operational_intensity_result
                        methodology_result.custom_elements[:realf] = PerfTest.Metric_Result(
                        name= "Real Performance",
                        units="GFlops",
                        value=local_real_performance,)
                    end
                    context.env_flags.roofline_full = false
                end
            )


        # MEM LIMIT TO CPU LIMIT THRESHOLD (used as the reference for bounded tests)
        ref = local_peakflops / local_peakbandwidth

        # Ratio
        ratio = result.value / ref
        # test
        _test = min < ratio < max


        constraint = PerfTest.Metric_Constraint(
            reference=ref,
            threshold_min=min * ref,
            threshold_min_percent=min,
            threshold_max=max * ref,
            threshold_max_percent=max,
            low_is_bad=true,
            succeeded=_test, custom_plotting=Symbol[],
            full_print=$(verbose ? :(true) : :(!_test))
        )



        # Setup result collecting struct
        methodology_result = PerfTest.Methodology_Result(
            name="ROOFLINE",
            metrics=Pair{PerfTest.Metric_Result,PerfTest.Metric_Constraint}[],
        )

        cpu_peak = PerfTest.Metric_Result(
            name="Peak CPU flops",
            units="GFlops/s",
            value=local_peakflops
        )
        methodology_result.custom_elements[:cpu_peak] = cpu_peak
        mem_peak = PerfTest.Metric_Result(
            name="Peak memory bandwidth",
            units="GB/s",
            value=local_peakbandwidth
        )
        methodology_result.custom_elements[:mem_peak] = mem_peak
            #push!(methodology_result.custom_elements, (:plot => plotexpr))
        limit_mem_b = PerfTest.Metric_Result(
            name="Is memory limited?",
            units="Yes/No",
            value= ratio > (local_peakflops / local_peakbandwidth) ? "NO" : "YES"
        )
        methodology_result.custom_elements[:mem_lim] = limit_mem_b
        roof_corner = PerfTest.Metric_Result(
            name="Roofline corner",
            units="FLOP/Byte",
            value= local_peakflops / local_peakbandwidth
        )
        methodology_result.custom_elements[:roof_corner] = roof_corner

        methodology_result.custom_elements[:plot] = PerfTest.printRoofline

        $(checkAuxiliaryCustomMetrics(context))

        push!(methodology_result.metrics, (result => constraint))

        PerfTest.printMethodology(methodology_result, $(length(context.depth)))
        # Register metric results TODO
        current_test_results[:roofline] = methodology_result

        @test _test
    end) : quote
        begin end
    end
end
