

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

function SBMID(metric :: metricID())
    sym = metricID(metric)
    if sym in formula_symbols
        return quote _PRFT_GLOBALS.builtins[$(QuoteNode(sym))] end
    else
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
end
