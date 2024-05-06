using Printf
using BenchmarkTools

include("perftest/structs.jl")

macro lpad(pad)
    return :(" " ^ $(esc(pad)))
end

function p_blue(printable)
    printstyled(printable, color=:blue)
end

function p_red(printable)
	  printstyled(printable, color=:red)
end
function p_yellow(printable)
	  printstyled(printable, color=:yellow)
end
function p_green(printable)
	  printstyled(printable, color=:green)
end

# Auxiliar print functions
function printDepth!(depth :: AbstractArray)
	  for i in eachindex(depth)
	      if depth[i].depth_flag == false
            if firstindex(depth) == i
                printstyled("PERFORMANCE TEST:\n", color=:yellow)
            end
            depth[i].depth_flag = true

            print(repeat(" ", i))
            printstyled(lastindex(depth) == i ? "AT: " : "IN: ", color=:blue)
            println(depth[i].depth_name)
        end
    end
end


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

function printMetric(metric :: Metric_Result, constraint:: Metric_Constraint, tab::Int)

    println(@lpad(tab) * "-" ^ 72)
    if !(constraint.succeeded)
        p_red("[!]")
    else
        p_green("[✓]")
    end
    print(@lpad(tab) *"METRIC ")
    p_blue("$(metric.name)")
    println(" ["* metric.units *"]:")
    println(@lpad(tab) * "."^72)
    print(@lpad(tab))
    printIntervalLanding(constraint.threshold_min, constraint.threshold_max, metric.value, constraint.low_is_bad)
    println("")
    if constraint.full_print
        println(@lpad(tab) * "."^72)
        println(@lpad(tab) * "| Expected: " * @sprintf("%.3f", constraint.reference) * " [" * metric.units * "]" * " "^20 * "Threshold: " * @sprintf("%.3f", metric.value < constraint.reference ? constraint.threshold_min : constraint.threshold_max) * " [" * metric.units * "]")
        print(@lpad(tab) * "| Got: ")
        if !(constraint.succeeded)
            p_red(@sprintf("%.3f", metric.value))
        else
            p_yellow(@sprintf("%.3f", metric.value))
        end
        println(" [" * metric.units * "]" * " "^20)
    end
    if length(constraint.custom_plotting) > 0
        println(@lpad(tab) * "."^72)
    else
        println(@lpad(tab) * "_"^72)
    end
end


function printMethodology(methodology :: Methodology_Result, tab :: Int)

    println(@lpad(tab) * "═"^72)
    print(@lpad(tab) * "METHODOLOGY: ")
    p_blue("$(methodology.name)")
    println("")
    for (metric, constraint) in methodology.metrics
        printMetric(metric, constraint, tab)
    end
    println(@lpad(tab) * "═"^72)
end
