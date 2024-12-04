

function onMemoryThroughputDefinition(formula :: ExtendedExpr, ctx :: Context, info)

    # Adds to the inner scope the request to build the methodology and its needed metric
    push!(ctx._local.custom_metrics[end], CustomMetric(
        name="Effective memory throughput",
        units="GB/s",
        formula=formula,
        symbol=:effMemTP
    ))
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id = :effMemTP,
        name = "Effective memory throughput",
        override = true,
        params = info,
    ))
end


function captureMethodologyInfo(id::Symbol, methodologies::Vector{Vector{MethodologyParameters}})::Union{MethodologyParameters,Nothing}
    # Initialize empty structures for merging parameters
    name :: Union{Nothing, AbstractString} = nothing
    merged_params = Dict{Symbol, Any}()
    override_found = false

    # Iterate through the methodologies from the end of the vector (backwards)
    for methodology_group in reverse(methodologies)
        for methodology in methodology_group
            if methodology.id == id
                # Set or update the name if it's empty
                if name isa Nothing
                    name = methodology.name
                end

                for (k, v) in methodology.params
                    if !haskey(merged_params, k)
                        merged_params[k] = v
                    end
                end

                # Mark that we found an entry with `override = true`
                override_found = methodology.override

                # If `override` is true, stop searching for more parameters
                if methodology.override
                    break
                end
            end
        end
        if override_found
            break
        end
    end

    if name isa Nothing
        return nothing
    end

    # Construct and return the resulting `MethodologyParameters`
    return MethodologyParameters(id=id, name=name, override=override_found, params=merged_params)
end

function buildMemTRPTMethodology(context :: Context)::Expr

    info = captureMethodologyInfo(:effMemTP, context._local.enabled_methodologies)

    if info isa Nothing
        return quote end
    else
        return quote
	          let
                value = _PRFT_LOCAL[:metrics][:effMemTP].value / _PRFT_GLOBAL[:machine][:empirical][:peakmemBW]
                success = value >= $(info.params[:ratio])

                result = Metric_Result(name="Effective Throughput Ratio",
                                       units="%",
                                       value=value*100)
                test = Metric_Test(
                    reference=100,
                    threshold_min_percent=$(info.params[:ratio]),
                    threshold_max_percent=1.0,
                    low_is_bad=true,
                    succeeded=success,
                    custom_plotting=Symbol[],
                    full_print=true
                )

                # Absolute value as an additional metric
                aux_abs_value = Metric_Result(
                    name="Attained Bandwidth",
                    units="GB/s",
                    value=_PRFT_LOCAL[:metrics][:effMemTP].value
                )
                aux_ref_value = Metric_Result(
                    name="Peak empirical bandwidth",
                    units="GB/s",
                    value=_PRFT_GLOBAL[:machine][:empirical][:peakmemBW]
                )

                # Save results and auxiliary measurements
                methodology_res = Methodology_Result(
                    name="Effective Memory Throughput",
                )
                push!(methodology_res.metrics, (result => test))
                methodology_res.custom_elements[:abs] = aux_abs_value
                methodology_res.custom_elements[:abs_ref] = aux_ref_value

                # Printing
                PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)))

                # Saving TODO

                # Testing
                @test test.succeeded
            end
        end
    end
end
