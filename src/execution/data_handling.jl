
using JLD2: StringDatatype
using JLD2

"""
This method is used to get historical data of a performance test suite from a save file located in `path`.
"""
function openDataFile(path::AbstractString)::Perftest_Datafile_Root
    return JLD2.load(path)["contents"]
end

"""
This method is used to save historical data of a performance test suite to a save file located in `path`.
"""
function saveDataFile(path :: AbstractString, contents:: Perftest_Datafile_Root)
    return jldsave(path; contents)
end

"""
This method expects a hierarchy tree (`dict`) in the form of nested dictionaries and a vector of dictionary keys `idx`. The function will recursively index by the keys to get to a final element.

The `DepthRecord` struct represents an index.
"""
function by_index(dict::Union{Dict,BenchmarkGroup}, idx::Vector{DepthRecord})
    e = dict
    for idx_elem in idx
        e = Expr(:ref, e, idx_elem.name)
    end

    return eval(e)
end


function pushElementToTestResult!(result::Dict{String, Union{Test_Result, Dict}}, test_path::Vector{DepthRecord}, class::Symbol, id::Symbol, element::Any)
    # Navigate to the required Test_Result
    for i in 1:length(test_path)-1
        result = result[test_path[i].name]
    end

    test_result = result[test_path[end].name]

    # Add element to the appropriate field
    if class in (:primitives, :metrics, :auxiliar, :methodology_results)
        getfield(test_result, class)[id] = element
    else
        error("Invalid class: $class. Must be one of :primitives, :metrics, :auxiliar, or :methodology_results")
    end

    return nothing
end

"""
This method will return a flattened array of all of the results for all the methodologies exercised in the provided dictionary.

# Example:
 "Test Set 1"
     -> "Test 1"
         -> Methodology A result
         -> Methodology B result
 "Test Set 2"
     -> "Test 1"
         -> Methodology A result
Returns:
 M. A result (Test Set 1)
 M. B result (Test Set 1)
 M. A result (Test Set 2)
"""
function extractMethodologyResultArray(methodology_dict :: Dict, methodology :: Symbol) :: Vector{Methodology_Result}
    retval = []
    for (key, elem) in methodology_dict
        if key isa Symbol && key == methodology
            push!(retval, elem)
        elseif key isa String
            append!(retval, extractMethodologyResultArray(elem, methodology))
        end
    end
    return retval
end

"""
Given a series of methodology results, the the raw values of all the metrics contained in the methodology results.
"""
function getMetricValue(mresult_vector :: Vector{Methodology_Result}, name :: String)

    retval = []
    for i in mresult_vector
        for m in i.metrics
            if m[1].name == name
                push!(retval, m[1].value)
            end
        end
        for elem in i.custom_elements
            if elem isa Metric_Result && elem.name == name
                push!(retval, elem.value)
            end
        end
    end

    return retval
end

"""
This method will return a flattened array of the whole test result hierarchy.

# Example
# Example:
 "Test Set 1"
     -> "Test 1"
         -> Methodology A result
         -> Methodology B result
 "Test Set 2"
     -> "Test 1"
         -> Methodology A result
Returns:
 "Test Set 1 -> Test 1 -> Methodology A"
 "Test Set 1 -> Test 1 -> Methodology B"
 "Test Set 2 -> Test 1 -> Methodology A"
"""
function extractNamesResultArray(methodology_dict::Dict, methodology :: Symbol)::Vector{String}
    retval = String[]
    for (key, elem) in methodology_dict
        if key isa Symbol && key == methodology
            push!(retval, "")
        elseif key isa String
            sublevel = extractNamesResultArray(elem, methodology)
            for i in sublevel
                push!(retval, key * " > " * i)
            end
        end
    end
    return retval
end


# NEW ONES
#This function will return all results associated with a specific methodology across all tests.
function get_methodology_results(datafile::Perftest_Datafile_Root, methodology_name::AbstractString)
    results = []
    for result in datafile.results
        for (name, methodology_result) in result.perftests
            if methodology_result.name == methodology_name
                push!(results, methodology_result)
            end
        end
    end
    return results
end

"""This function will return all tests that failed (i.e., where succeeded is false)."""
function get_failed_tests(datafile::Perftest_Datafile_Root)
    failed_tests = []
    for result in datafile.results
        for (name, methodology_result) in result.perftests
            for (metric_result, metric_test) in methodology_result.metrics
                if !metric_test.succeeded
                    push!(failed_tests, (methodology_result.name, metric_result.name, metric_test))
                end
            end
        end
    end
    return failed_tests
end

"""This function will return all metrics for a specific test name."""
function get_metrics_for_test(datafile::Perftest_Datafile_Root, test_name::AbstractString)
    metrics = []
    for result in datafile.results
        for (name, methodology_result) in result.perftests
            if name == test_name
                for (metric_result, metric_test) in methodology_result.metrics
                    push!(metrics, metric_result)
                end
            end
        end
    end
    return metrics
end

"""This function will return all results for a specific metric across all methodologies."""
function get_metric_results(datafile::Perftest_Datafile_Root, metric_name::AbstractString)
    metric_results = []
    for result in datafile.results
        for (name, methodology_result) in result.perftests
            for (metric_result, metric_test) in methodology_result.metrics
                if metric_result.name == metric_name
                    push!(metric_results, (methodology_result.name, metric_result, metric_test))
                end
            end
        end
    end
    return metric_results
end
