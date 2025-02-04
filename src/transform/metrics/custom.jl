
function defineCustomMetric(type :: Symbol, ctx :: Context, info)

    if info isa Nothing
        return
    end

    push!(ctx._local.custom_metrics[end], CustomMetric(
        name=info[:name],
        units=info[:units],
        formula=transformFormula(info[Symbol("")], ctx),
        symbol=Symbol(info[:name]),
        auxiliary= type == :aux
    ))


    addLog("metrics", "[METRIC] Defined $(info[:name]) [$(info[:units])] on $([i.set_name for i in ctx._local.depth_record])")
end


function buildCustomMetrics(custom_metrics :: Vector{Vector{CustomMetric}})::Expr

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
            _PRFT_LOCAL[:metrics][$(QuoteNode(symbol))] = newMetricResult(
                $mode,
                name=$(metric_def.name),
                units=$(metric_def.units),
                value=$(metric_def.formula),
                auxiliary=$(metric_def.auxiliary)
            )
        end
        addLog("metrics", "[METRIC] Building $(metric_def.name)")
    end
    return buffer
end
