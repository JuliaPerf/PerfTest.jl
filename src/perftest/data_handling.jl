
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
