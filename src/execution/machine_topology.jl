module Topology

using Hwloc
using ThreadPinningCore

addLog = x -> @info "[$(string(x))]"
throwParseError! = x -> @error "Invalid thread arrangement: $x"
struct Index
    indexing::Vector{Integer}
    symbols::Vector{Symbol}
end

"""
    For a process, the specification on how many threads and how many numa domains to use for the test suite.
        (#numas, #threads_per_numa)
    Example:
        (1, 1) or :single   -> One thread on one numa node
        (1, 2)              -> Two threads on two numa nodes
        (1, 1//1) or :numa  -> All threads on one numa node
        (1, 1//2)           -> Half of the threads available for one numa node
        (2, 1)              -> One thread on each of two numa nodes 
        (1//1,1//1) or :all -> All posible threads on all numa nodes
        # For later:
        :gpu_single         -> One thread in the same numa domain as a GPU device
        :gpu_each           -> One thread per GPU device, on the same domains as their respective devices
"""
ArrangementSpec = Union{Symbol,Tuple{Union{Integer,Rational{Int64}},Union{Integer,Rational{Int64}}}}

cpu_model = Nothing
hwloc_efficiency_mask = 0x0
hwloc_topology = nothing

pu_dict = nothing
devices = nothing
numas = nothing

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

setupLog(logfunc :: Function, errorfunc :: Function) = begin
    Topology.addLog = logfunc
    Topology.throwParseError! = errorfunc
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

    addLog("machine", "[MACHINE] $(cpu_model), $(length(numas)) NUMA domains with $([t for t in threadsPerNuma()]) threads per domain.")
    addLog("machine", "[MACHINE] Cache sizes (biggest per level): $(getCacheSizes() ./ 1024 ./ 1024) MBytes.")

    return pu_dict, devices, numas
end

function numberOfNUMAS()::Integer
    return length(numas)
end

function threadsPerNuma()::Vector{Integer}
    return [length(numa) for numa in getNUMADomainCores()]
end

# Autovectorized
function literallizeArrangement(arrgmts::Vector)::Vector{Tuple{Integer,Integer}}
    return literallizeArrangement.(arrgmts)
end

"""
    Prepares a thread arrangement specification for execution by converting it to a literal form `(numas, threads_per_numa)`. 
    And verifies that the arrangement is satisfiable on the current machine and Julia process.
"""
function literallizeArrangement(arrgmt::ArrangementSpec)::Tuple{Integer,Integer}
    # Ensure topology is loaded
    if Topology.hwloc_topology isa Nothing
        Topology.getMachineTopology!()
    end
    reason = ""

    total_numas = Topology.numberOfNUMAS()
    threads_per_numa = Topology.threadsPerNuma()  # Vector{Integer}, one entry per NUMA

    if arrgmt isa Symbol
        arrgmt = if arrgmt == :single
            (1, 1)
        elseif arrgmt == :numa
            (1, 1 // 1)
        elseif arrgmt == :all
            (1 // 1, 1 // 1)
        else
            error("Invalid thread arrangement: symbol `$arrgmt` is unrecognised. " *
                  "Must be one of [:single, :numa, :all] or a tuple — see ArrangementSpec docs.")
        end
    end
    
    if length(arrgmt) != 2
        error("Invalid thread arrangement: $arrgmt has $(length(arrgmt)) element(s); " *
              "expected exactly 2  (#numas, #threads_per_numa).")
    end

    numa_spec, thread_spec = arrgmt

    literal_numas::Integer = if numa_spec isa Rational
        if !(0 < numa_spec <= 1)
            error("Invalid thread arrangement: NUMA ratio $numa_spec is out of range; " *
                  "must satisfy 0 < ratio ≤ 1.")
        end
        # e.g. 1//1 → all NUMAs, 1//2 → half of them (at least 1)
        max(1, floor(Integer, numa_spec * total_numas))
    else
        if numa_spec <= 0
            error("Invalid thread arrangement: if #numa is and integer, it shall be positive, got $numa_spec.")
        end
        if numa_spec > total_numas
            reason *= ("Invalid thread arrangement: requested $numa_spec NUMA domain(s) but " *
                  "the host only has $total_numas.")
        end
        Integer(numa_spec)
    end

    # Use the minimum available thread count across the selected NUMAs so the
    # arrangement is satisfiable on every chosen domain.
    min_threads_in_selected = minimum(threads_per_numa[1:literal_numas])

    literal_threads::Integer = if thread_spec isa Rational
        if !(0 < thread_spec <= 1)
            error("Invalid thread arrangement: thread ratio $thread_spec is out of range; " *
                  "must satisfy 0 < ratio ≤ 1.")
        end
        max(1, floor(Integer, thread_spec * min_threads_in_selected))
    else
        if thread_spec <= 0
            error("Invalid thread arrangement: #threads_per_numa must be a positive integer, " *
                  "got $thread_spec.")
        end
        if thread_spec > min_threads_in_selected
            reason *= ("Invalid thread arrangement: requested $thread_spec thread(s) per NUMA but " *
                  "the most constrained of the $literal_numas selected NUMA domain(s) only " *
                  "has $min_threads_in_selected available thread(s).")
        end
        Integer(thread_spec)
    end

    total_needed = literal_numas * literal_threads

    # Check Julia thread count
    if Threads.nthreads() < total_needed || reason != ""
        reason *= "Not enough threads on the interpreter."
        addLog("machine", "Specified thread arrangement $arrgmt -> literalized to ($literal_numas, $literal_threads) cannot be applied on this Julia process. $reason Ignoring.")
        return (0,0)
    elseif Threads.nthreads() > total_needed || reason == ""
        reason *= "Too many threads on the interpreter."
        addLog("machine", "Specified thread arrangement $arrgmt -> literalized to ($literal_numas, $literal_threads) cannot be applied on this Julia process. $reason Ignoring.")
        return (0,0)
    end
    return (literal_numas, literal_threads)
end

# Autovectorized
function validateArrangement(arrgmts::Vector)::Bool
    return all(validateArrangement.(arrgmts))
end


"""
    validateArrangement(arrgmt::ArrangementSpec) -> Bool

Validates the arrangement syntax.

Throws an error if the arrangement is badly specified.
"""
function validateArrangement(arrgmt::ArrangementSpec)::Bool
    if arrgmt isa Symbol
        return if arrgmt == :single
            true
        elseif arrgmt == :numa
            true
        elseif arrgmt == :all
            true
        else
            throwParseError!("Invalid thread arrangement: symbol `$arrgmt` is unrecognised. " *
                             "Must be one of [:single, :numa, :all] or a tuple — see ArrangementSpec docs.")
            false
        end
    end
    if length(arrgmt) != 2
        throwParseError!("Invalid thread arrangement: $arrgmt has $(length(arrgmt)) element(s); " *
                         "expected exactly 2  (#numas, #threads_per_numa).")
        return false
    end

    numa_spec, thread_spec = arrgmt
    if numa_spec isa Rational
        if !(0 < numa_spec <= 1)
            throwParseError!("Invalid thread arrangement: $arrgmt, NUMA ratio $numa_spec is out of range; " *
                             "must satisfy 0 < ratio ≤ 1.")
            return false
        end
    else
        if numa_spec <= 0
            throwParseError!("Invalid thread arrangement: $arrgmt, if #numa is and integer, it shall be positive, got $numa_spec.")
            return false
        end
    end
    if thread_spec isa Rational
        if !(0 < thread_spec <= 1)
            throwParseError!("Invalid thread arrangement: $arrgmt, thread ratio $thread_spec is out of range; " *
                             "must satisfy 0 < ratio ≤ 1.")
            return false
        end
    else
        if thread_spec <= 0
            throwParseError!("Invalid thread arrangement: $arrgmt, #threads_per_numa must be a positive integer, " *
                             "got $thread_spec.")
            return false
        end
    end

    return true
end

function isExecutableArrangement(arrgmts::Vector)::Union{ArrangementSpec,Nothing}
    for arrgmt in arrgmts
        if !((found = isExecutableArrangement(arrgmt)) isa Nothing)
            return found
        end
    end
    return nothing
end

function isExecutableArrangement(arrgmt::ArrangementSpec)::Union{ArrangementSpec,Nothing}
    return if arrgmt[1] >= 1 && arrgmt[2] >= 1
        arrgmt
    else
        nothing
    end
end

"""
    enforceThreadArrangement(arrgmt::Tuple{Integer, Integer}) -> Bool
    enforceThreadArrangement(arrgmt::Vector{Integer}) -> Bool

Given a *literal* arrangement `(#numa_domains, #threads_per_numa)`, checks
that the running Julia process has at least `#numa_domains × #threads_per_numa`
threads available.

In case a vector is passed, the vector is interpreted as a manual arrangement, 
with the elements being the cores to allocate.

- Returns `false` if the interpreter does not have enough threads.
- Returns `true` and pins the Julia threads to the appropriate CPU threads
  (in NUMA-domain order, `#threads_per_numa` consecutive cores per domain)
  if the arrangement can be satisfied.
"""
function enforceThreadArrangement(arrgmt::Tuple{Integer,Integer})::Bool
    n_numas, n_threads = arrgmt
    total_needed = n_numas * n_threads

    # Check Julia thread count
    if Threads.nthreads() < total_needed
        @warn "enforceThreadArrangement: need $total_needed Julia thread(s) " *
              "($(n_numas) NUMA × $(n_threads) threads/NUMA) but only " *
              "$(Threads.nthreads()) are available."
        return false
    end

    # For each of the first n_numas NUMA domains take the first n_threads cores.
    numa_cores = Topology.getNUMADomainCores()  # Vector{Vector{Integer}}

    cpu_ids = Vector{Integer}()
    for numa_idx in 1:n_numas
        # Sort for determinism
        domain_cores = sort(numa_cores[numa_idx])
        append!(cpu_ids, domain_cores[1:n_threads])
    end

    pinthreads(cpu_ids)
    return true
end

function enforceThreadArrangement(manual::Vector{Integer})::Bool
    if length(manual) > sum(length.(Topology.getNUMADomainCores()))
        error("enforceThreadArrangement: more threads have been specified than the ones available in the machine")
    end
    if length(manual) > Threads.nthreads()
        error("enforceThreadArrangement: more threads have been specified than the ones avaiable for the interpreter")
    end
    pinthreads(manual)
end

"""
    freeThreadArrangement()

Unpins all Julia threads, removing any CPU affinity constraints previously
set by `enforceThreadArrangement`.
"""
function freeThreadArrangement()
    unpinthreads()
end

end # module end