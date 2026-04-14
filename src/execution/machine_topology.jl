
module Topology

using Hwloc

#export getMaxCacheSize, getNUMADomain, hasGPUaffinity, sameNUMADomain, getNUMADomainCores, getGPUAffineCores, getMachineTopology!

struct Index
    indexing::Vector{Integer}
    symbols::Vector{Symbol}
end

cpu_model = Nothing
hwloc_efficiency_mask = 0x0
hwloc_topology = Nothing

pu_dict = Nothing
devices = Nothing
numas = Nothing

# Internal methods

function getChildren(root::Hwloc.Object, indexing::Vector{Integer})
    @assert length(indexing) > 0 "On PerfTest.Topology, empty index to getChildren"
    c = root
    for i in indexing
        c = c.children[i]
    end
    return c
end

function matchIdxs(idx1, idx2)::Bool
    l = length(idx1)
    if length(idx2) != l
        return false
    end
    for i in 1:l
        if idx1[i] != idx2[i]
            return false
        end
    end
    return true
end

function isAParentOfB(A, B)::Bool
    return matchIdxs(A, B[1:length(A)])
end

function findParentPackage(elem::Index)::Index
    idx = 0
    for (i, symbol) in enumerate(elem.symbols)
        if symbol == :Package || symbol == :Group
            idx = i
            break
        end
    end
    return Index(copy(elem.indexing[1:idx]), copy(elem.symbols[1:idx]))
end

# External methods

"""
    In case of heterogeneous levels, returns the biggest of each level
"""
function getCacheSizes()::Vector
    sizes = []
    for i in [:L3Cache, :L2Cache, :L1Cache]
        if (size = getMaxCacheSize(i)) > 0
            push!(sizes, size)
        end
    end
    return sizes
end

"""
    Biggest cache on the topology in bytes

    If the level is not present, 0 will be returned.
"""
function getMaxCacheSize(level::Symbol)::Integer

    current_max = 0
    for (_, x) in pu_dict
        indexing, symbols = x.indexing, x.symbols
        for (i, symbol) in enumerate(symbols)
            if symbol == level
                c = getChildren(hwloc_topology, indexing[1:i])
                current_max = current_max < c.attr.size ? c.attr.size : current_max
            end
        end
    end
    return current_max
end

function getNUMADomainCores()::Vector{Vector{Integer}}
    cores = [[] for i in 1:length(numas)]
    for (keycore, x) in pu_dict
        indexing_core = x.indexing
        for (keynuma, y) in numas
            indexing_numa = y.indexing
            if isAParentOfB(indexing_numa[1:end-1], indexing_core)
                push!(cores[keynuma], keycore)
            end
        end
    end
    return cores
end

function getDeviceAffineCores(device_id)::Vector{Integer}
    cores = []
    parent = findParentPackage(devices[device_id])
    for (key, x) in pu_dict
        if isAParentOfB(parent.indexing, x.indexing)
            push!(cores, key)
        end
    end
    return cores
end

function getEfficiencyCores()::Vector{Integer}
    eff = []
    for core_id in keys(pu_dict)
        if ((1 << Integer(core_id)) & hwloc_efficiency_mask) > 0
            push!(eff, core_id)
        end
    end
    return eff
end

"""
Obtain some basic parameters regarding the machine topology like NUMA arrangement, cache sizes, network interfaces. The info is obtained from Hwloc.jl
    Modifies topology submodule.
"""
function getMachineTopology!()

    Topology.cpu_model = Sys.CPU_NAME
    Topology.hwloc_topology = gettopology()
    cpukind = Hwloc.get_cpukind_info()
    for i in cpukind
        if i.efficiency_rank == 0
            Topology.hwloc_efficiency_mask = i.masks[end]
            break
        end
    end

    local indexing = []
    local symbols = []
    local pu_dict = Dict{Integer,Topology.Index}()
    local devices = Dict{Integer,Topology.Index}()
    local numas = Dict{Integer,Topology.Index}()

    recursiveTopRetrieve!(Topology.hwloc_topology, pu_dict, devices, numas, indexing, symbols)

    Topology.pu_dict = pu_dict
    Topology.numas = numas
    Topology.devices = devices

    return pu_dict, devices, numas
end

function recursiveTopRetrieve!(obj::Hwloc.Object, pu_dict, devices, numas, indexing, symbols)
    # Parse NUMA nodes
    for (i, mem) in enumerate(obj.memory_children)
        if mem.type_ == :NUMANode
            push!(indexing, i)
            push!(symbols, :NUMANode)
            numas[length(numas)+1] = Topology.Index(indexing, symbols)
            pop!(indexing)
            pop!(symbols)
        end
    end
    # Parse machine hierarchy
    for (i, child) in enumerate(obj.children)
        push!(indexing, i)
        push!(symbols, child.type_)
        if child.type_ == :PU
            @info "$indexing -> id: $(obj.os_index)"
            pu_dict[child.os_index] = Topology.Index(indexing, symbols)
        end
        recursiveTopRetrieve!(child, pu_dict, devices, numas, indexing, symbols)
        if child.type_ == :Package
            @info "$i"
        end
        pop!(indexing)
        pop!(symbols)
    end
    # Parse devices
    for (i, io) in enumerate(obj.io_children)
        push!(indexing, i)
        push!(symbols, io.type_)
        devices[length(devices)+1] = Topology.Index(indexing, symbols)
        recursiveTopRetrieve!(io, pu_dict, devices, numas, indexing, symbols)
        pop!(indexing)
        pop!(symbols)
    end
end

end # module end