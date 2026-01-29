
# Create a custom Julia testset type (from jl) template
using Test
using Test: AbstractTestSet, Broken, Error, Fail, Pass, record, finish, get_testset_depth, get_testset, print_test_results, get_test_counts, Result

mutable struct PerfTestSet <: AbstractTestSet
    description::String
    results::Vector{Any}
    n_passed::Int

    ## Extra fields needed for PerfTest suites

    # autonumeric counter to identify tests
    test_count :: Int

    # Holds the current iteration
    iterator::Any

    # Holds BenchmarkTools.jl benchmarks
    benchmarks::BenchmarkGroup
    # The following includes test results and snapshots of the metrics at test time
    test_results::Dict{String, Test_Result}

    # For regression
    old_test_results::Union{Nothing, Dict{String,Union{Dict,Test_Result}}}

    # To print the whole levels
    parent_chain::Vector{AbstractString}

    # Constructor
    PerfTestSet(desc::String) = begin
        # Check if there is a parent
        if isa(Test.get_testset(), PerfTestSet)
            parents = [Test.get_testset().parent_chain; Test.get_testset().description]
        else
            parents = AbstractString[]
        end
        return new(desc, [], 0, 0, nothing, BenchmarkGroup(), Dict{String, Test_Result}(), nothing, parents)
    end
end

function newBenchmarkGroup() :: BenchmarkGroup
    return BenchmarkGroup()
end


# Save test results or child test sets
function Test.record(ts::PerfTestSet, t::Result; extra_data = nothing)
    if !main_rank(mode)
        return ts
    end

    nt = nothing
    if isa(t, Pass)
        ts.n_passed += 1
    end
    return push!(ts.results, isnothing(nt) ? t : nt)
end
function Test.record(ts::PerfTestSet, child::AbstractTestSet)
    return push!(ts.results, child)
end

function Test.finish(ts::PerfTestSet)
    if !main_rank(mode)
        return ts
    end

    # Print failed tests on the current level (or everything if verbose)
    for (test_name,test_result) in ts.test_results
        if sum(get_test_counts(ts)[2:3]) > 0 || Configuration.CONFIG["general"]["verbose"]
            for parent in ts.parent_chain
                print("IN: $(parent) ")
            end
            print(
                "\n"
            )
            print(" " ^ get_testset_depth() * "AT: $(ts.description)\n")
            for methodology in test_result.methodology_results
                printMethodology(methodology, get_testset_depth(), Configuration.CONFIG["general"]["plotting"])
            end

            # Print auxiliary metrics
            printAuxiliaries(test_result.auxiliar, get_testset_depth())
        else
        end
    end

    if get_testset_depth() > 0
        record(get_testset(), ts)
        return ts
    else
        # show the results are printed if we are at the top level
        print_test_results(ts)
    end
    return ts
end



# Recursive function that counts the number of test results of each
# type directly in the testset, and totals across the child testsets
function Test.get_test_counts(ts::PerfTestSet)
    passes, fails, errors, broken = 0, 0, 0, 0
    c_passes, c_fails, c_errors, c_broken = 0, 0, 0, 0
    for t in ts.results
        isa(t, Pass)   && (passes  += 1)
        isa(t, Fail)   && (fails  += 1)
        isa(t, Error)  && (errors += 1)
        isa(t, Broken) && (broken += 1)
        if isa(t, AbstractTestSet)
            np, nf, ne, nb, ncp, ncf, nce, ncb, duration = get_test_counts(t)
            c_passes += np + ncp
            c_fails += nf + ncf
            c_errors += ne + nce
            c_broken += nb + ncb
        end
    end
    # We dont use this but we leave the field for compatibility with other types of TestSet
    duration = ""
    return passes, fails, errors, broken, c_passes, c_fails, c_errors, c_broken, duration
end

function Test.get_test_counts(tss::Vector{Any})

    passes, fails, errors, broken = 0, 0, 0, 0
    c_passes, c_fails, c_errors, c_broken = 0, 0, 0, 0
    
    for ts in tss
        for t in ts.results
            isa(t, Pass)   && (passes  += 1)
            isa(t, Fail)   && (fails  += 1)
            isa(t, Error)  && (errors += 1)
            isa(t, Broken) && (broken += 1)
            if isa(t, AbstractTestSet)
                np, nf, ne, nb, ncp, ncf, nce, ncb, duration = get_test_counts(t)
                c_passes += np + ncp
                c_fails += nf + ncf
                c_errors += ne + nce
                c_broken += nb + ncb
            end
        end
    end

    # We dont use this but we leave the field for compatibility with other types of TestSet
    duration = ""
    return passes, fails, errors, broken, c_passes, c_fails, c_errors, c_broken, duration
end

function get_test_errors(ts::PerfTestSet)
    errors = Error[]
    for t in ts.results
        isa(t, Error)  && (push!(errors, t))
        if isa(t, AbstractTestSet)
            append!(errors, get_test_errors(t))
        end
    end
    return errors
end

"""
   Will print the overall result of the test suite execution 
"""
function Test.print_test_results(ts::PerfTestSet)
    if !main_rank(mode)
        return ts
    end

    passes, fails, errors, _, cp,cf,ce,_ = get_test_counts(ts)
    print("Aggregate Results: $(passes + cp) PASSED, $(fails + cf) FAILED, $(errors+ce) ERRORS\n")
    err = get_test_errors(ts)
    for _error in err    
        println("ERROR:")
        println(_error.value)
        print(_error.backtrace)
    end 
end


function buildPrimitiveMetrics!(::Type{NormalMode}, ts::PerfTestSet, test_result :: Test_Result)
    # Get testset
    test_result.primitives[:median_time] = median(ts.benchmarks[test_result.name]).time / 1e9
    test_result.primitives[:min_time] = minimum(ts.benchmarks[test_result.name]).time / 1e9
    test_result.primitives[:iterator] = ts.iterator
end

var"@perftestset" = Test.var"@testset"

function extractTestResults(tss :: Vector{Any}) :: Dict{String, Union{Dict, Test_Result}}
# In case a testset with for is present
    dict = Dict{String,Union{Dict,Test_Result}}() 

    for ts in tss
        dict[ts.description * "_" * string(ts.iterator)] = extractTestResults(ts)
    end

    return dict
end

function extractTestResults(ts :: PerfTestSet) :: Dict{String,Union{Dict,Test_Result}}
    dict = Dict{String,Union{Dict,Test_Result}}() 

    for t in ts.results
        if isa(t, Test.Result)
        else
            dict[t.description] = extractTestResults(t)
        end
    end
    for (k,v) in ts.test_results
        dict[k] = v
    end

    return dict
end


"""
TODO
"""
function saveMethodologyData(testname :: AbstractString, data :: Methodology_Result)
	ts = Test.get_testset()
    res :: Test_Result = ts.test_results[testname]
    push!(res.methodology_results, data)
end
