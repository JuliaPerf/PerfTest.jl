
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
This method expects a hierarchy tree (`dict`) in the form of nested dictionaries and a vector of dictionary keys `idx`. The function will recursively apply the keys to get to a final element.

It is usually put to work with the `DepthRecord` struct.
"""
function by_index(dict::Union{Dict,BenchmarkGroup}, idx::Vector{DepthRecord})
    e = dict
    for idx_elem in idx
        e = Expr(:ref, e, idx_elem.depth_name)
    end

    return eval(e)
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
 M. A result (Test 1)
 M. B result (Test 1)
 M. A result (Test 2)
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
