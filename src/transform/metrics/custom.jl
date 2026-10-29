
# Symbol that identifies a custom metric or benchmark: its symbol parameter if given, otherwise its name as a symbol
metricSymbol(info) = haskey(info, :symbol) ? metricID(info[:symbol]) : Symbol(info[:name])

"""
Report as a parse error that `construct` (e.g. "The @define_metric name = \"m\""), of the recipe being transformed, sets
a symbol that formulas cannot refer to: an empty one, or a built-in formula symbol (e.g. :median_time), which formulas
resolve to the built-in value instead. Only an explicit symbol is checked, the default one (the name) is left as it was.
"""
function checkMetricSymbol!(construct::AbstractString, info, ctx::Context)
    haskey(info, :symbol) || return
    sym = metricSymbol(info)
    if sym === Symbol("")
        throwParseError!("$construct of recipe $(ctx._global.original_file_path) sets an empty symbol. Give it a non empty " *
                         "symbol, or leave symbol out to refer to it by its name.", ctx)
    elseif sym in ctx._global.valid_symbols
        throwParseError!("$construct of recipe $(ctx._global.original_file_path) sets symbol = $(repr(sym)), which is a " *
                         "built-in formula symbol, so formulas would get the built-in value instead. Choose another symbol.", ctx)
    end
end

function defineCustomMetric(type :: Symbol, ctx :: Context, info)

    if info isa Nothing
        return
    end

    construct = "The $(type == :aux ? "@auxiliary_metric" : "@define_metric") name = $(repr(info[:name]))"
    if usesAutoflop(info[Symbol("")])
        reportAutoflopUse!(construct, "uses :autoflop in its formula", ctx)
    end
    checkMetricSymbol!(construct, info, ctx)
    symbol = metricSymbol(info)

   push!(ctx._local.custom_metrics[end], CustomMetric(
        name=info[:name],
        units=info[:units],
        formula=transformFormula(info[Symbol("")], ctx),
        symbol=symbol,
        auxiliary= type == :aux
    ))


    addLog("metrics", "[METRIC] Defined $(info[:name]) ($(repr(symbol))) [$(info[:units])] on $([i.set_name for i in ctx._local.depth_record])")
end


function buildCustomMetrics(custom_metrics :: Vector{Vector{CustomMetric}}, ctx::Context)::Expr

    # Auxiliary/custom metrics have no Metric_Test companion to consult a showvar flag from at
    # print time, so the decision is made here at construction time: show variance for this
    # scope's metrics iff some enclosing @regression/@perfcompare in the scope chain asked for
    # it. captureMethodologyInfo already implements the innermost-first inherit/override walk,
    # so this correctly inherits across nested testsets for free.
    scope_has_showvar = let
        reg = captureMethodologyInfo(:regression, ctx._local.enabled_methodologies)
        cmp = captureMethodologyInfo(:perfcmp, ctx._local.enabled_methodologies)
        (reg !== nothing && get(reg.params, :showvar, false) === true) ||
        (cmp !== nothing && get(cmp.params, :showvar, false) === true)
    end

    buffer = :(begin end)
    built_set = Set{Symbol}()


    # Evaluate all available metrics
    for metric_def in Iterators.flatten(custom_metrics)
        symbol = metric_def.symbol isa Nothing ? Symbol(metric_def.name) : metric_def.symbol
        if symbol in built_set # Metric already built
            @warn "Metric collision, this might be intended or might be a mistake, the inner scope is prioritized"
            addLog("metrics", "[METRIC] METRIC COLLISION")
            continue
        else
            push!(built_set, symbol)
        end
        buffer = quote
            $buffer
            # Auxiliary metrics are not tested for regression, they shall be saved in the auxiliar dictionary
            let m = newMetricResult(
                $mode,
                name=$(metric_def.name),
                units=$(metric_def.units),
                value=$(metric_def.formula),
                auxiliary=$(metric_def.auxiliary),
                showvar=$scope_has_showvar
            )
                $(if metric_def.auxiliary
                    :(test_res.auxiliar[$(QuoteNode(symbol))] = m)
                else
                    :(test_res.metrics[$(QuoteNode(symbol))] = m)
                end)
            end
        end
        addLog("metrics", "[METRIC] Building $(metric_def.name)")
    end
    return buffer
end


function defineCustomBenchmark(ctx::Context, info) :: Expr

    checkMetricSymbol!("The @define_benchmark name = $(repr(info[:name]))", info, ctx)
    symbol = metricSymbol(info)

    addLog("metrics", "[BENCHMARK] Defining $(info[:name]) ($(repr(symbol))) [$(info[:units])] on $([i.set_name for i in ctx._local.depth_record])")

    # Cannot be called inside a testset TODO
    if length(ctx._local.depth_record) < 0
        throwParseError!("Cannot define benchmark $(info[:name]) inside a testset", ctx)
    else
        # Add benchmark name to recognized custom benchmarks
        push!(ctx._global.custom_benchmarks, symbol)
        # Transform
        return quote
            _PRFT_GLOBALS.custom_benchmarks[$(QuoteNode(symbol))] = newMetricResult(
                $mode,
                name=$(info[:name]),
                units=$(info[:units]),
                value=$(info[Symbol("")]),
                auxiliary=false
            )
        end
    end

end

function isCustomMetricDefined(ctx::Context, name :: Symbol)
    for custom_metric in Iterators.flatten(ctx._local.custom_metrics)
        if custom_metric.symbol == name
            return true
        end
    end
    return false
end

# The custom metric in scope named `name` (as a symbol), or nothing. Used to hint at its symbol when a metric is referred to by its name
function customMetricByName(ctx::Context, name :: Symbol)
    for custom_metric in Iterators.flatten(ctx._local.custom_metrics)
        if Symbol(custom_metric.name) == name
            return custom_metric
        end
    end
    return nothing
end
