using Printf
using BenchmarkTools

include("structs.jl")

# Auxiliar print functions
function printdepth!(depth :: AbstractArray)
	  for i in eachindex(depth)
	      if depth[i].depth_flag == false
            if firstindex(depth) == i
                printstyled("PERFORMANCE TEST FAILURES:\n", color=:yellow)
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

# Function that generates a test name if needed
function gen_test_name!(state :: Context)
    v = (last(state.depth).depth_test_count += 1)
    return "Test $v"
end

function testset_update!(state:: Context, name::String)
    push!(state.depth, ASTWalkDepthRecord(name));
end
