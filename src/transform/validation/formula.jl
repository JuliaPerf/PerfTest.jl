

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

# Automatic flop counting is outdated: the :autoflop primitive is always 0 (see transformPerftest), so every use of it
# (general.autoflops = true for a @roofline without actual_flops, or :autoflop in a formula or as a metric) is reported
# as a parse error, see reportAutoflopUse!
AUTOFLOP_UNSUPPORTED = "Automatic flop counting is outdated and not supported, the :autoflop primitive is always 0."
AUTOFLOP_INSTEAD = "Give the flop count of the target explicitly instead: pass it to @roofline with actual_flops (a " *
                   "number, or a formula as its operational intensity one), or write it in the formula in place of :autoflop."

# Whether a formula, as written in the recipe, uses the :autoflop primitive, e.g. `:autoflop / :median_time`
usesAutoflop(x::QuoteNode) = x.value === :autoflop
usesAutoflop(x::Expr) = any(usesAutoflop, x.args)
usesAutoflop(x) = false

"""
Report as a parse error that `construct` (e.g. "The @define_metric name = \"m\""), of the recipe being transformed,
uses automatic flop counting `how` (e.g. "uses :autoflop in its formula"), which is not supported, see
AUTOFLOP_UNSUPPORTED. `instead` says what to do instead.
"""
function reportAutoflopUse!(construct::AbstractString, how::AbstractString, ctx; instead::AbstractString = AUTOFLOP_INSTEAD)
    throwParseError!("$construct of recipe $(ctx._global.original_file_path) $how. $AUTOFLOP_UNSUPPORTED $instead", ctx)
end

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
    # Reads go through PerfTest.metricSampledValue (not the bare .value field) so a metric
    # that carries a variance (see execution/variance.jl) keeps propagating it through
    # whatever arithmetic the surrounding formula performs.
    return quote (haskey(_PRFT_GLOBALS.custom_benchmarks,$(QuoteNode(sym))) ?
        PerfTest.metricSampledValue(_PRFT_GLOBALS.custom_benchmarks[$(QuoteNode(sym))]) :
        haskey(_PRFT_GLOBALS.builtins, $(QuoteNode(sym))) ?
        _PRFT_GLOBALS.builtins[$(QuoteNode(sym))] :
        haskey(test_res.metrics,$(QuoteNode(sym))) ?
        PerfTest.metricSampledValue(test_res.metrics[$(QuoteNode(sym))]) :
        haskey(test_res.auxiliar,$(QuoteNode(sym))) ?
        PerfTest.metricSampledValue(test_res.auxiliar[$(QuoteNode(sym))]) :
        newSymbols(Val($(QuoteNode(sym))))(Symbol[]))
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
