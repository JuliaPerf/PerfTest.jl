

formula_symbols = Set([
    :min_time,
    :median_time,
    :autoflop,
    :printed_output,
    :out,
    :return,
    :iterator,
    :peak_flops,
    :peak_bandwidth,
])

function formulaGetTime(properties::Vector{Symbol})
    if properties[1] == :median
        return quote test_res.primitives[:median_time] end
    elseif properties[1] == :min
        return quote test_res.primitives[:min_time] end
    else
        error("Invalid time property: $(properties[1]). Valid options are :median and :min.")
    end
end

new_symbols = Dict{Symbol, Function}(
    :time => formulaGetTime,
)

function SBMID(metric :: metricID())
    sym = metricID(metric)
    return quote (haskey(_PRFT_GLOBALS.custom_benchmarks,$(QuoteNode(sym))) ?
        _PRFT_GLOBALS.custom_benchmarks[$(QuoteNode(sym))].value :
        haskey(_PRFT_GLOBALS.builtins, $(QuoteNode(sym))) ?
        _PRFT_GLOBALS.builtins[$(QuoteNode(sym))] :
        haskey(test_res.metrics,$(QuoteNode(sym))) ? 
        test_res.metrics[$(QuoteNode(sym))].value : 
        haskey(test_res.auxiliar,$(QuoteNode(sym))) ?
        test_res.auxiliar[$(QuoteNode(sym))].value :
        error("Undefined $($(QuoteNode(sym))), wrong spelling or not defined in the current context?")) 
    end 
end

# WARNING, WIP missing error prints for some cases
function SBMID(::Val{:LIKWID}, properties :: Vector{Symbol})
    if is_loaded(:LIKWID)
        if properties[1] == :METRICS
            return quote likwidMetricsRetrieve(test_res, $(QuoteNode(properties[2])), $(QuoteNode(properties[3]))) end
        elseif properties[1] == :EVENTS
            return quote likwidEventsRetrieve(test_res, $(QuoteNode(properties[2])), $(QuoteNode(properties[3]))) end
        else
            error("Invalid selector: $(properties[1]). Valid options are :METRICS and :EVENTS.")
        end
    else
        error("LIKWID is not loaded. Cannot use LIKWID metrics.")
    end
end

function SBMID(metric :: Symbol, properties :: Vector{Symbol})
    if metric in keys(new_symbols)
        return new_symbols[metric](properties)
    else
        if is_loaded(:LIKWID) && haskey(_PRFT_GLOBALS.likwid_metrics, metric)
            return resolveAlias(metric, properties)
        else
            error("Undefined metric $metric, wrong spelling or not defined in the current context?")
        end
    end
end
