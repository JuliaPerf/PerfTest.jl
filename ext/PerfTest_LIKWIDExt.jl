module PerfTest_LIKWIDExt

using LIKWID
using PerfTest
using DataStructures: OrderedDict

function PerfTest.is_loaded(::Val{:LIKWID}) return true end

# ----------------------------------------------------------------------------
# Extension data type to store LIKWID results in Test_Result
# ----------------------------------------------------------------------------
struct LIKWIDExtensionData <: PerfTest.ExtensionData
    metrics :: OrderedDict
    events  :: OrderedDict
end
PerfTest.LIKWIDExtensionData(metrics, events) = LIKWIDExtensionData(OrderedDict(metrics), OrderedDict(events))

# ----------------------------------------------------------------------------
# perfmon entry point
# ----------------------------------------------------------------------------

# `expr` is the (quoted) user code, `groups` is the requested LIKWID group list.
PerfTest.perfmon(args...; kwargs...) = LIKWID.perfmon(args...; kwargs...)
PerfTest.var"@PRFT_perfmon"(__source__::LineNumberNode, __module__::Module, groups,expr) = quote LIKWID.perfmon(() -> $expr, $groups; autopin = false, print = false) end

# ============================================================================
#  Specifier sets
# ============================================================================
const flop_submetrics_type = Set([
    :single,
    :double,
    :integer,
])

const flop_submetrics_vectorize = Set([
    :scalar,
    :vector,
    :vector_128,
    :vector_256,
    :vector_512,
])

const bw_metrics_level = Set([
    :l1,
    :l2,
    :l3,
    :mem,
])

const bw_metrics_kind = Set([
    :read,
    :write,
    :read_write,
])

const energy_metrics_part = Set([
    :package,
    :dram,
    :all,
])

# ============================================================================
#  Helpers
# ============================================================================
"""
    classify(properties, sets...)

Split a flat list of specifier symbols into the categories defined by the
named `sets`. Returns a NamedTuple-like Dict mapping each set's name to the
matched symbol (or `nothing`) and validates that every property belongs to
exactly one of the provided sets.
"""
function classify(properties, sets::Pair{Symbol,<:AbstractSet}...)
    result = Dict{Symbol,Any}(name => nothing for (name, _) in sets)
    for p in properties
        matched = false
        for (name, set) in sets
            if p in set
                if result[name] !== nothing
                    error("Conflicting specifiers '$(result[name])' and '$p' " *
                          "for category '$name'.")
                end
                result[name] = p
                matched = true
                break
            end
        end
        matched || error("Invalid specifier '$p'. Valid options are: " *
                         "$(union(map(last, sets)...)).")
    end
    return result
end

# ============================================================================
#  FLOP / FLOP-rate formulas
# ============================================================================
# LIKWID exposes ready-made FLOP metrics in the FLOPS_* groups. We map the
# (type, vectorization) specifier combination onto the right LIKWID metric
# name. Where LIKWID does not provide a pre-computed metric we fall back to
# summing the underlying retired-instruction events with the right weights.

# Precomputed LIKWID metric names per type (double / single).
const _flop_metric_by_type = Dict(
    :double  => ("FLOPS_DP", "DP [MFLOP/s]"),
    :single  => ("FLOPS_SP", "SP [MFLOP/s]"),
)

# Event weights (counts × elements-per-op) used when we need fine-grained
# vectorization breakdowns that LIKWID does not expose directly.
const _flop_events_double = [
    (:FP_ARITH_INST_RETIRED_SCALAR_DOUBLE,        1, :scalar),
    (:FP_ARITH_INST_RETIRED_128B_PACKED_DOUBLE,   2, :vector_128),
    (:FP_ARITH_INST_RETIRED_256B_PACKED_DOUBLE,   4, :vector_256),
    (:FP_ARITH_INST_RETIRED_512B_PACKED_DOUBLE,   8, :vector_512),
]

const _flop_events_single = [
    (:FP_ARITH_INST_RETIRED_SCALAR_SINGLE,        1, :scalar),
    (:FP_ARITH_INST_RETIRED_128B_PACKED_SINGLE,   4, :vector_128),
    (:FP_ARITH_INST_RETIRED_256B_PACKED_SINGLE,   8, :vector_256),
    (:FP_ARITH_INST_RETIRED_512B_PACKED_SINGLE,  16, :vector_512),
]

# Build a `quote` that sums the chosen weighted events.
function _flop_event_expr(events, group)
    terms = Expr[]
    for (ev, weight, _vec) in events
        push!(terms, :(PerfTest.likwidEventsRetrieve(test_res, $(QuoteNode(group)),
                                                      $(QuoteNode(ev))) .* $weight))
    end
    body = foldl((a, b) -> :($a .+ $b), terms)
    return :(sum($body))
end

"""
    formulaGetFlop(test_res, properties)

Total floating-point operations.

Specifiers (any order):
  * type:          :double (default) | :single | :integer
  * vectorization: :scalar | :vector_128 | :vector_256 | :vector_512 | :vector
                   (omit ⇒ all widths summed)
"""
function PerfTest.formulaGetFlop(properties)
    spec = classify(properties,
                    :type => flop_submetrics_type,
                    :vec  => flop_submetrics_vectorize)

    ftype = something(spec[:type], :double)   # default: double precision
    fvec  = spec[:vec]                         # default (nothing): all widths

    if ftype === :integer
        # Integer "ops" come from a different counter set.
        #return :(sum(PerfTest.likwidMetricsRetrieve($test_res, :FLOPS_DP,
        # TODO                                            "Operations [OPS/s]")))
        return :(0)
    end

    events = ftype === :single ? _flop_events_single : _flop_events_double
    group  = ftype === :single ? :FLOPS_SP : :FLOPS_DP

    push!(PerfTest.ctx._local.enabled_likwid_groups, group)

    if fvec === nothing || fvec === :vector
        # All widths (or all vector widths). Filter scalar out for :vector.
        chosen = fvec === :vector ?
                 filter(e -> e[3] !== :scalar, events) : events
        return _flop_event_expr( chosen, group)
    else
        chosen = filter(e -> e[3] === fvec, events)
        isempty(chosen) && error("No FLOP event for vectorization '$fvec' " *
                                  "and type '$ftype'.")
        return _flop_event_expr( chosen, group)
    end
end

"""
    formulaGetFlops(test_res, properties)

Floating-point operation *rate* (FLOP/s). Same specifiers as
[`formulaGetFlop`](@ref); uses LIKWID's precomputed rate metrics when no
vectorization breakdown is requested.
"""
function PerfTest.formulaGetFlops(properties)
    spec = classify(properties,
                    :type => flop_submetrics_type,
                    :vec  => flop_submetrics_vectorize)

    ftype = something(spec[:type], :double)
    fvec  = spec[:vec]

    if fvec === nothing && haskey(_flop_metric_by_type, ftype)
        group, metric = _flop_metric_by_type[ftype]
        push!(PerfTest.ctx._local.enabled_likwid_groups, Symbol(group))
        return :(sum(PerfTest.likwidMetricsRetrieve(test_res,
                                                     $(QuoteNode(Symbol(group))),
                                                     $metric)) * 1e6) # LIKWID reports MFLOP/s
    end

    error("Per-vectorization FLOP/s requires a timed reduction; request " *
          "raw counts via :flop instead, or omit the vectorization specifier.")
end

# ============================================================================
#  Bandwidth formulas
# ============================================================================
# LIKWID groups: L2 / L3 / MEM expose "<lvl> bandwidth [MBytes/s]" plus
# directional "load"/"evict" variants.
const _bw_group = Dict(
    :l1  => :L1,    # may not exist on all archs; left for completeness
    :l2  => :L2,
    :l3  => :L3,
    :mem => :MEM,
)

const _bw_metric = Dict(
    (:l2,  :read_write) => "L2 bandwidth [MBytes/s]",
    (:l2,  :read)       => "L2D load bandwidth [MBytes/s]",
    (:l2,  :write)      => "L2D evict bandwidth [MBytes/s]",
    (:l3,  :read_write) => "L3 bandwidth [MBytes/s]",
    (:l3,  :read)       => "L3 load bandwidth [MBytes/s]",
    (:l3,  :write)      => "L3 evict bandwidth [MBytes/s]",
    (:mem, :read_write) => "Memory bandwidth [MBytes/s]",
    (:mem, :read)       => "Memory read bandwidth [MBytes/s]",
    (:mem, :write)      => "Memory write bandwidth [MBytes/s]",
)

"""
    formulaGetBandwidth(test_res, properties)

Memory/cache bandwidth in MBytes/s.

Specifiers:
  * level: :l1 | :l2 | :l3 | :mem  (default :mem)
  * kind:  :read | :write | :read_write  (default :read_write)
"""
function PerfTest.formulaGetBandwidth(properties)
    spec  = classify(properties,
                     :level => bw_metrics_level,
                     :kind  => bw_metrics_kind)
    level = something(spec[:level], :mem)
    kind  = something(spec[:kind], :read_write)

    haskey(_bw_metric, (level, kind)) ||
        error("Bandwidth not available for level '$level' kind '$kind'.")
    haskey(_bw_group, level) ||
        error("Unknown bandwidth level '$level'.")

    group  = _bw_group[level]
    metric = _bw_metric[(level, kind)]
    push!(PerfTest.ctx._local.enabled_likwid_groups, group)
    return :(sum(PerfTest.likwidMetricsRetrieve(test_res,
                                                $(QuoteNode(group)), $metric)))
end

# ============================================================================
#  Energy / Power formulas
# ============================================================================
const _energy_metric = Dict(
    :package => "Energy [J]",
    :dram    => "Energy DRAM [J]",
)
const _power_metric = Dict(
    :package => "Power [W]",
    :dram    => "Power DRAM [W]",
)

"""
    formulaGetEnergy(test_res, properties)

Consumed energy in Joules. Specifier: :package | :dram | :all (default).
"""
function PerfTest.formulaGetEnergy( properties)
    spec = classify(properties, :part => energy_metrics_part)
    part = something(spec[:part], :all)
    return _energy_or_power( part, _energy_metric)
end

"""
    formulaGetPower(test_res, properties)

Average power draw in Watts. Specifier: :package (default) | :dram | :all.
"""
function PerfTest.formulaGetPower( properties)
    spec = classify(properties, :part => energy_metrics_part)
    part = something(spec[:part], :all)
    return _energy_or_power( part, _power_metric)
end

function _energy_or_power( part, table)
    if part === :all
        terms = [:(sum(PerfTest.likwidMetricsRetrieve(test_res, :ENERGY, $m)))
                 for m in values(table)]
        return foldl((a, b) -> :($a + $b), terms)
    end
    push!(PerfTest.ctx._local.enabled_likwid_groups, :ENERGY)
    haskey(table, part) || error("No energy/power metric for part '$part'.")
    return :(sum(PerfTest.likwidMetricsRetrieve(test_res, :ENERGY,
                                                $(table[part]))))
end

# ============================================================================
#  Cache-miss formulas
# ============================================================================
"""
    formulaGetMisses(test_res, properties)

Cache miss counts/ratios. Specifier: level (:l2 default | :l3).
"""
function PerfTest.formulaGetMisses( properties)
    spec  = classify(properties, :level => bw_metrics_level)
    level = something(spec[:level], :l2)
    metric = level === :l3 ? "L3 miss ratio" : "L2 miss ratio"
    group  = level === :l3 ? :L3CACHE : :L2CACHE
    return :(sum(PerfTest.likwidMetricsRetrieve(test_res,
                                                $(QuoteNode(group)), $metric)))
end

# ============================================================================
#  GPU formula (placeholder; depends on NVMON availability)
# ============================================================================
"""
TODO    formulaGetGPU(test_res, properties)

GPU metrics via LIKWID's NVMON backend. Specifier list is forwarded as the
metric name for now (extend as needed).
"""
function PerfTest.formulaGetGPU( properties)
    isempty(properties) &&
        error("Specify a GPU metric, e.g. :gpu with a metric specifier.")
    metric = String(properties[1])
    return :(sum(PerfTest.likwidMetricsRetrieve(test_res, :GPU, $metric)))
end

# ============================================================================
#  Alias dictionary (defined AFTER the functions it references)
# ============================================================================
PerfTest.newSymbols(::Val{:flop})    = PerfTest.formulaGetFlop
PerfTest.newSymbols(::Val{:flops})  = PerfTest.formulaGetFlops
PerfTest.newSymbols(::Val{:flop_s})  = PerfTest.formulaGetFlops
PerfTest.newSymbols(::Val{:bw})     = PerfTest.formulaGetBandwidth
PerfTest.newSymbols(::Val{:energy}) = PerfTest.formulaGetEnergy
PerfTest.newSymbols(::Val{:power})  = PerfTest.formulaGetPower
PerfTest.newSymbols(::Val{:miss})   = PerfTest.formulaGetMisses

"""
    resolveAlias(alias, test_res, properties) :: Expr

Entry point for the shortcut nomenclature: given a main `alias` and a chain of
specifier symbols `properties`, dispatch to the right formula function.
"""
function PerfTest.resolveAlias(alias::Symbol, properties)
    haskey(additional_metric_aliases, alias) ||
        error("Unknown metric alias ':$alias'. Known aliases: " *
              "$(collect(keys(additional_metric_aliases))).")
    return additional_metric_aliases[alias]( properties)
end

# ============================================================================
#  Retrieval primitives (native LIKWID names)
# ============================================================================
function PerfTest.likwidEventsRetrieve(test_res, group, event_name)
    for extension in test_res.extensions
        if extension isa LIKWIDExtensionData
            return _likwidThingsRetrieve(extension.events, group :: Union{String, Symbol}, event_name :: Union{String, Symbol})
        end
    end
    throw(ArgumentError("Test result does not contain LIKWID extension data"))
end

function PerfTest.likwidMetricsRetrieve(test_res, group :: Union{String, Symbol}, metric_name :: Union{String, Symbol})
    for extension in test_res.extensions
        if extension isa LIKWIDExtensionData
            return _likwidThingsRetrieve(extension.metrics, group, metric_name)
        end
    end
    throw(ArgumentError("Test result does not contain LIKWID extension data"))
end

function _likwidThingsRetrieve(dict, group :: Union{String, Symbol}, name :: Union{String, Symbol})
    if group isa Symbol
        group = String(group)
    end
    if name isa Symbol
        name = String(name)
    end
    haskey(dict, group) ||
        throw(ArgumentError("LIKWID group '$group' not found in test results"))
    group_data = dict[group]
    ret_val = []
    for thread_id in keys(group_data)
        if haskey(group_data[thread_id], name)
            push!(ret_val, group_data[thread_id][name])
        else
            throw(ArgumentError("Event/Metric '$name' not found in LIKWID " *
                                "group '$group' (at least for thread '$thread_id')"))
        end
    end
    return ret_val
end

end # module