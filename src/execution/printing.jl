

function printFullRoofline(_roofline :: Methodology_Result, printplots :: Bool)

    factor = _roofline.custom_elements[:factor]

    if printplots
        p = Plot([0, max(_roofline.custom_elements[:opint].value + 1.0,  _roofline.custom_elements[:roof_corner_raw].value * 2.)], [0, _roofline.custom_elements[:cpu_peak].value * 1.2], yscale=:log2)
        p = lineplot(0, max(_roofline.custom_elements[:opint].value + 1., _roofline.custom_elements[:roof_corner_raw].value * 2.),
                     rooflineCalc(_roofline.custom_elements[:cpu_peak].value,
                _roofline.custom_elements[:mem_peak].value), name="Automatic Roofline")

        lineplot!(p, 0, max(_roofline.custom_elements[:opint].value + 1.0, _roofline.custom_elements[:roof_corner_raw].value * 2.0),
                     rooflineCalc(_roofline.custom_elements[:cpu_peak].value * factor,
                                  _roofline.custom_elements[:mem_peak].value * factor), name="Test threshold")
        vline!(p, _roofline.custom_elements[:opint].value, color=:yellow, name="Tested function")

        scatterplot!(p, [_roofline.custom_elements[:opint].value],[_roofline.custom_elements[:realf].value], color=:red, marker=:circle, name="Execution (Circle)")
        show(print(p))
        println("")
    end
end


"""
  This method is used to print the test names, with consideration on
the hierarchy and adding indentation whenever necessary
"""
function printDepth!(depth::AbstractArray)
    for i in eachindex(depth)
        if depth[i].header_printed == false
            if firstindex(depth) == i
                printstyled("PERFORMANCE TEST:\n", color=:yellow)
            end
            depth[i].header_printed = true

            print(repeat(" ", i))
            printstyled(lastindex(depth) == i ? "AT: " : "IN: ", color=:blue)
            println(depth[i].name)
        end
    end
end

"""
This method dumps into the output a test result in case of failure. The output will be formatted to make it easy to read.
"""
function printfail(judgement::BenchmarkTools.TrialJudgement, trial::BenchmarkTools.Trial, reference :: BenchmarkTools.Trial, tolerance :: FloatRange, tab::Int)

    print(lpad(">", tab))
    printstyled(" Failure: ", color=:red)
    print("Expected time: ", median(reference).time)
    print("  Got time: ")
    printstyled(median(trial).time, color=:yellow)
    println("")
    print(lpad(">", tab))
    print(" Difference: ")
    printstyled(@sprintf("%.3f",(judgement.ratio.time - 1) * 100), "%", color=
        judgement.ratio.time > 1 ? :red : :green)
    print("  Threshold: ")
    printstyled((tolerance.left - tolerance.center) * 100, "%", color=:blue)
    println("")
end

"""
This method is used to print a graphical representation on a test result and the admisible intervals it can take. The result will and the two bounds will be printed in order.
"""
function printIntervalLanding(bot, top, landing, down_is_bad::Bool = true)

    @assert bot < top

    if (bot > landing)
        print("--[Result: ")
        down_is_bad ? p_red(@sprintf("%.3f", landing)) : p_blue(@sprintf("%.3f", landing))
        print("]---(Bottom threshold: ")
        down_is_bad ? p_red(@sprintf("%.3f", bot)) : p_green(@sprintf("%.3f", bot))
        print(")---(Top threshold: ")
        down_is_bad ? p_green(@sprintf("%.3f", top)) : p_red(@sprintf("%.3f", top))
        print(")--")
    elseif (top > landing)
        print("--(Bottom threshold: ")
        down_is_bad ? p_red(@sprintf("%.3f", bot)) : p_green(@sprintf("%.3f", bot))
        print(")---[Result: ")
        p_blue(@sprintf("%.3f", landing))
        print("]---(Top threshold: ")
        down_is_bad ? p_green(@sprintf("%.3f", top)) : p_red(@sprintf("%.3f", top))
        print(")--")
    else
        print("--(Bottom threshold: ")
        down_is_bad ? p_red(@sprintf("%.3f", bot)) : p_green(@sprintf("%.3f", bot))
        print(")---(Top threshold: ")
        down_is_bad ? p_green(@sprintf("%.3f", top)) : p_red(@sprintf("%.3f", top))
        print(")---[Result: ")
        down_is_bad ? p_blue(@sprintf("%.3f",landing)) : p_red(@sprintf("%.3f", landing))
        print("]--")
    end
end

function printThresholdLanding(threshold, landing, down_is_bad::Bool = true)
    if (threshold >= landing)
        print("--[Result: ")
        down_is_bad ? p_red(@sprintf("%.3f", landing)) : p_blue(@sprintf("%.3f", landing))
        print("]---(Threshold: ")
        down_is_bad ? p_red(@sprintf("%.3f", threshold)) : p_green(@sprintf("%.3f", threshold))
        print(")--")
    else
        print("--(Bottom threshold: ")
        down_is_bad ? p_red(@sprintf("%.3f", threshold)) : p_green(@sprintf("%.3f", threshold))
        print(")---[Result: ")
        p_blue(@sprintf("%.3f", landing))
        print("]--")
    end
end

"""
This method is used to dump into the output the information about a metric and the value obtained in a specific test.
"""
function printMetric(metric :: Metric_Result, test:: Metric_Test, tab::Int)

    println(@lpad(tab) * "-" ^ 72)
    if !(test.succeeded)
        p_red("[!]")
    else
        p_green("[✓]")
    end
    print(@lpad(tab) *"METRIC ")
    p_blue("$(metric.name)")
    print(" ["* metric.magnitude_prefix * metric.units *"]:")
    # MPI info
    if !(metric.mpi isa Nothing)
        print(" "^10)
        p_yellow("MPI Enabled")
        print(" ")
        p_blue(metric.mpi.reduct)
        println(" - " * string(metric.mpi.size) * " ranks")
    else
        println()
    end
    println(@lpad(tab) * "."^72)
    print(@lpad(tab))
    if metric.units == "bool"
        print(test.succeeded ? "TRUE" : "FALSE")
    else 
        begin    
        if test.threshold_max_percent isa Nothing
            printThresholdLanding(test.threshold_min_percent/100 * test.reference, metric.value, test.low_is_bad)
        else    
            printIntervalLanding(test.threshold_min_percent/100 * test.reference, test.threshold_max_percent/100 * test.reference, metric.value, test.low_is_bad)
        end
        end
    end
    println("")
    if test.full_print
        println(@lpad(tab) * "."^72)
        println(@lpad(tab) * "| Reference: " * @sprintf("%.3f", test.reference) * " [" * metric.units * "]" * " "^20 * "Threshold: " * @sprintf("%.3f", metric.value < test.reference || (test.threshold_max_percent isa Nothing) ? test.threshold_min_percent /100 * test.reference : test.threshold_max_percent /100 * test.reference) * " [" * metric.units * "]")
        print(@lpad(tab) * "| Got: ")
        if !(test.succeeded)
            p_red(@sprintf("%.3f", metric.value))
        else
            p_yellow(@sprintf("%.3f", metric.value))
        end

        println(" [" * metric.units * "]" * " "^20)
    end
    if length(test.custom_plotting) > 0
        println(@lpad(tab) * "."^72)
    else
        println(@lpad(tab) * "_"^72)
    end
end

"""
This function is used to dump metric information regading auxiliar metrics, which are not used in testing.
"""
function auxiliarMetricPrint(metric :: Metric_Result, tab::Int)
    println(" "^tab * "Metric: " * metric.name * " [" * metric.magnitude_prefix * metric.units * "]")
    println(" " ^ tab * "  = ", metric.value)
    println("")
end

"""
This function is used to print the information relative to a methodology, relative to a a specific test execution result. This will usually print a series of metrics and might also print plots.
"""
function printMethodology(methodology :: Methodology_Result, tab :: Int, printplots :: Bool)


    println(@lpad(tab) * "═"^72)
    print(@lpad(tab) * "METHODOLOGY: ")
    p_blue("$(methodology.name)")
    println("")
    for (metric, constraint) in methodology.metrics
        printMetric(metric, constraint, tab)
    end
    if length(methodology.custom_elements) > 0
        println(@lpad(tab) * "-"^72)
        println(@lpad(tab) * "Additional data:")
        for (_, elem) in methodology.custom_elements
            if methodology.custom_auto_print && elem isa Metric_Result
                auxiliarMetricPrint(elem, tab)
            end
            # Custom behaviour when printing, i.e used to plot
            if elem isa Function
                elem(methodology, printplots)
            end
        end
    end
    println(@lpad(tab) * "═"^72)
end




function printAuxiliaries(metrics :: Dict{Symbol, Metric_Result}, tab :: Int)
    println(@lpad(tab) * "Auxiliary results:")
	  for (_,metric) in metrics
        if metric.auxiliary
            PerfTest.auxiliarMetricPrint(metric, tab)
        end
    end
end
