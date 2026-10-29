
function onPerfcmpDefinition(expr :: ExtendedExpr, ctx :: Context, info)
    # Adds to the inner scope the request to build the methodology and its needed metrics
    if info isa Nothing || !(Configuration.CONFIG["perfcompare"]["enabled"])
        return
    end
    if usesAutoflop(info[Symbol("")])
        reportAutoflopUse!("The @perfcompare $(info[Symbol("")])", "uses :autoflop", ctx)
    end


    params = Dict{Symbol, Any}(
        gensym("expr") => info[Symbol("")],
        :showvar => get(info, :showvar, false),
    )
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id = :perfcmp,
        name = "@perfcompare Testing",
        override = false,
        params = params,
    ))

    addLog("metrics", "[METHODOLOGY] Defined Performance Assertion on $([i.set_name for i in ctx._local.depth_record]) with expression $(info[Symbol("")])")
end


function buildPerfcmp(context :: Context) :: Expr

    info = captureMethodologyInfo(:perfcmp, context._local.enabled_methodologies)
    if info isa Nothing
        return quote end
    else
        buffer = quote
            all_succeeded = true
        end
        showvar = get(info.params, :showvar, false)
        # Get all metrics in the info. `:showvar` is a fixed, non-expression key stored
        # alongside the gensym'd per-assertion keys (see onPerfcmpDefinition) — skip it here,
        # every other entry is a formula expression to compile.
        for (k,expr) in info.params
            if k === :showvar
                continue
            end
            buffer = quote
                $buffer
                metric = newMetricResult(
                    $mode,
                    name=$(repr(expr)),
                    units="bool",
                    value=$(transformFormula(expr, context))
                )

                success = metric.value

                # Create result and test structures
                test = Metric_Test(
                    reference=0,
                    threshold_min_percent=1.,
                    threshold_max_percent=nothing,
                    low_is_bad=true,
                    succeeded=success,
                    custom_plotting=Symbol[],
                    full_print=false,
                    showvar=$(showvar)
                )

                push!(methodology_res.metrics, (metric => test))

                all_succeeded &= success
            end
        end
        return quote
            let
                methodology_res = Methodology_Result(
                    name="Performance Assertion"
                )

                $buffer

                #if $(Configuration.CONFIG["general"]["verbose"]) || !(all_succeeded)
                #    PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)), $(Configuration.CONFIG["general"]["plotting"]))
                #end

                for (r,test) in methodology_res.metrics
                    PerfTest.@_prftest test.succeeded
                end

                saveMethodologyData(test_res.name, methodology_res)
            end
        end
    end
end
