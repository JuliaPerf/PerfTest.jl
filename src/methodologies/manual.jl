
function onRawDefinition(expr :: ExtendedExpr, ctx :: Context, info)
    # Adds to the inner scope the request to build the methodology and its needed metrics
    if info isa Nothing
        return
    end

    push!(ctx._local.custom_metrics[end], CustomMetric(
        name=info[:name],
        units=info[:units],
        formula=transformFormula(info[Symbol("")], ctx),
        symbol=Symbol(info[:name])
    ))
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name=info[:name],
        units=info[:units],
        formula=transformFormula(info[:reference], ctx),
        symbol=Symbol("ref",info[:name])
    ))
    params = Dict{Symbol, Any}(
        Symbol(info[:name]) => Pair(Symbol("ref", info[:name]), info[:low_is_bad]),
    )
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id = :raw,
        name = "Raw Metric Testing",
        override = false,
        params = params,
    ))
end


function buildRaw(context :: Context) :: Expr

    info = captureMethodologyInfo(:raw, context._local.enabled_methodologies)
    if info isa Nothing
        return quote end
    else
        buffer = quote
        end
        # Get all metrics in the info
        for (metric_id, (reference_id, low_is_bad)) in info.params
            buffer = quote
                $buffer
                metric = _PRFT_LOCAL[:metrics][$(QuoteNode(metric_id))]
                reference = _PRFT_LOCAL[:metrics][$(QuoteNode(reference_id))]
                success = $(low_is_bad ? :(>=) : :(<=))(metric.value,reference.value)

                # Create result and test structures
                test = Metric_Test(
                    reference=reference.value,
                    threshold_min_percent=1.,
                    threshold_max_percent=nothing,
                    low_is_bad=$low_is_bad,
                    succeeded=success,
                    custom_plotting=Symbol[],
                    full_print=false
                )

                push!(methodology_res.metrics, (metric => test))
            end
        end
        return quote
            let
                methodology_res = Methodology_Result(
                    name="Raw Metric Testing"
                )

                $buffer

                # TODO
                PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)))

                for (r,test) in methodology_res.metrics
                    @test test.succeeded
                end
            end
        end
    end
end
