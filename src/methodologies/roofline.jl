using Base: nothing_sentinel

include("../structs.jl")
include("../config.jl")
include("../perftest/structs.jl")
include("../perftest/data_handling.jl")
include("../metrics.jl")
include("../benchmarking.jl")


# THIS FILE SAVES THE MAIN COMPONENTS OF THE ROOFLINE
# METHODOLOGY BEHAVIOUR

# GENERATED SPACE IMPORTANT SYMBOLS:
#
# roofline_opint
# local_peakflops
# local_peakbandwidth

"""
  Checks for the return symbol
"""
function retvalExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:return) ? :(PerfTests.by_index(export_tree, depth)[:ret_value]) : x), expr)
end

function autoflopExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:autoflop) ? :(PerfTests.by_index(export_tree, depth)[:autoflop]) : x), expr)
end

function printedOutputExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:printed_output) ? :(PerfTests.by_index(export_tree, depth)[:printed_output]) : x), expr)
end

function printedOutputAbbreviationExpressionParser(expr::Expr)::Expr
    return MacroTools.postwalk(x -> (x == :(:out) ? :(PerfTests.grepOutputXGetNumber(PerfTests.by_index(export_tree, depth)[:printed_output])) : x), expr)
end

using UnicodePlots

rooflineFunc = (maxflops, maxbandwidth) -> (opint -> min(maxflops, maxbandwidth * opint))

# Additional printing behaviour
function printRoofline(_roofline :: Methodology_Result)

    if roofline.plotting
        p = lineplot(0, _roofline.custom_elements[:roof_corner].value * 2.,
                     rooflineFunc(_roofline.custom_elements[:cpu_peak].value,
                                  _roofline.custom_elements[:mem_peak].value), name="Automatic Roofline")

        vline!(p, _roofline.metrics[1].first.value, color=:cyan, name="Tested function")

        show(print(p))
    end
end


"""
  Parses roofline user request and sets up data for
  roofline computation.
"""
function rooflineMacroParse(x::Expr, ctx::Context)::Expr
    if roofline.enabled
        peakflops = nothing
        peakbandwidth = nothing

        # Enables local roofline model construction
        ctx.env_flags.roofline_prefix = true

        # Capture needed args
        for arg in x.args
            # Is macro kwarg?
            if arg isa Expr && arg.head == Symbol("=")
                if arg.args[1] == Symbol("cpu_peak")
                    peakflops = arg.args[2]
                elseif arg.args[1] == Symbol("membw_peak")
                    peakbandwidth = arg.args[2]
                end
            end
        end
        # Last is the operational intensity BLOCK
        if x.args[end].head == :block
            # Fill primitives
            t = customMetricExpressionParser(x.args[end])
            # Fill return
            t = retvalExpressionParser(t)
            # Fill autoflops
            t = autoflopExpressionParser(t)
            # Fill output
            t = printedOutputExpressionParser(t)
            # Abbreviated version
            t = printedOutputAbbreviationExpressionParser(t)
        else
            error("Malformed @roofline, opint must be in block format")
        end

        push!(ctx.test_tree_expr_builder[end], quote
            roofline_opint = $t
            local_peakflops = $(peakflops == nothing ? :(peakflops) : peakflops)
            local_peakbandwidth = $(peakbandwidth == nothing ? :(peakbandwidth) : peakbandwidth)
        end)
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

        result = PerfTests.Metric_Result(
            name="OPERATIONAL INTENSITY",
            units="FLOP/Byte",
            value=roofline_opint
        )

        # MEM LIMIT TO CPU LIMIT THRESHOLD (used as the reference for bounded tests)
        ref = local_peakflops / local_peakbandwidth

        # Ratio
        ratio = result.value / ref
        # test
        _test = min < ratio < max


        constraint = PerfTests.Metric_Constraint(
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
        methodology_result = PerfTests.Methodology_Result(
            name="ROOFLINE",
            metrics=Pair{PerfTests.Metric_Result,PerfTests.Metric_Constraint}[],
        )

        cpu_peak = PerfTests.Metric_Result(
            name="Peak CPU flops",
            units="GFlops/s",
            value=local_peakflops
        )
        methodology_result.custom_elements[:cpu_peak] = cpu_peak
        mem_peak = PerfTests.Metric_Result(
            name="Peak memory bandwidth",
            units="GB/s",
            value=local_peakbandwidth
        )
        methodology_result.custom_elements[:mem_peak] = mem_peak
            #push!(methodology_result.custom_elements, (:plot => plotexpr))
        limit_mem_b = PerfTests.Metric_Result(
            name="Is memory limited?",
            units="Yes/No",
            value= ratio > (local_peakflops / local_peakbandwidth) ? "NO" : "YES"
        )
        methodology_result.custom_elements[:mem_lim] = limit_mem_b
        roof_corner = PerfTests.Metric_Result(
            name="Roofline corner",
            units="FLOP/Byte",
            value= local_peakflops / local_peakbandwidth
        )
        methodology_result.custom_elements[:roof_corner] = roof_corner

        methodology_result.custom_elements[:plot] = PerfTests.printRoofline

        push!(methodology_result.metrics, (result => constraint))

        PerfTests.printMethodology(methodology_result, $(length(context.depth)))
        # Register metric results TODO
        current_test_results[:roofline] = methodology_result

        @test _test
    end) : quote
        begin end
    end
end


