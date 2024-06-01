
using JLD2: StringDatatype
using JLD2

include("structs.jl")

function openDataFile(path :: AbstractString) :: Perftest_Datafile_Root
    return JLD2.load(path)["contents"]
end

function saveDataFile(path :: AbstractString, contents:: Perftest_Datafile_Root)
    return jldsave(path; contents)
end

## DepthRecord
# Auxiliar by index Dict access function
function by_index(dict::Union{Dict,BenchmarkGroup}, idx::Vector{DepthRecord})
    e = dict
    for idx_elem in idx
        e = Expr(:ref, e, idx_elem.depth_name)
    end

    return eval(e)
end


## To extract values from methology results
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
