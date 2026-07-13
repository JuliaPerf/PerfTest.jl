

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
    if length(properties) == 0 || properties[1] == :median
        return quote test_res.primitives[:median_time] end
    elseif properties[1] == :min
        return quote test_res.primitives[:min_time] end
    else
        error("Invalid time property: $(properties[1]). Valid options are :median and :min.")
    end
end

newSymbols(x::Val{:time}) = formulaGetTime
newSymbols(x::Val) = error("Unrecognized $x.")

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
        $(newSymbols(Val(:flops))(Symbol[])))
    end 
end

# WARNING, WIP missing error prints for some cases
function SBMID(::Val{:LIKWID}, properties :: Vector{Symbol})
    if is_loaded(:LIKWID)
        if properties[1] == :METRICS
            return quote likwidMetricsRetrieve(test_res, $(properties[2]), $(properties[3])) end
        elseif properties[1] == :EVENTS
            return quote likwidEventsRetrieve(test_res, $(properties[2]), $(properties[3])) end
        else
            error("Invalid selector: $(properties[1]). Valid options are :METRICS and :EVENTS.")
        end
    else
        error("LIKWID is not loaded. Cannot use LIKWID metrics.")
    end
end

function SBMID(metric :: Symbol, properties :: Vector{Symbol})
    expr = newSymbols(Val(metric))(properties)
    return expr
end
