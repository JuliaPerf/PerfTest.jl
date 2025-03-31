
"""

Called when a regression macro is detected, sets up the regression methodology

"""
function onRegressionDefinition(_::ExtendedExpr, ctx::Context, info)
    if !(Configuration.CONFIG["regression"]["enabled"])
        return
    end

    if haskey(info, :threshold)
    else
        info[:threshold] = Configuration.CONFIG["regression"]["default_threshold"]
    end
    push!(ctx._local.enabled_methodologies[end], MethodologyParameters(
        id=:regression,
        name="Metric regression tracking",
        override=true,
        params=info,
    ))

    addLog("metrics", "[METHODOLOGY] Defined REGRESSION on $([i.set_name for i in ctx._local.depth_record])")
end



"""
  Syntax sugar

  Returns an expression that returns the percentage difference of the new value vs the old value

  If there is no old value 0 will be returned
"""
function regression(kind_index :: Symbol, ident_index :: Symbol)

    expr_old = quote
        (by_index(_PRFT_GLOBAL[:old], _PRFT_LOCAL[:depth]))
    end
    expr_new = quote
        _PRFT_LOCAL
    end

    # Kind indexation must be primitives, metrics or auxiliar
    expr_old = Expr(:., expr_old, QuoteNode(kind_index))
    expr_new = Expr(:ref, expr_new, QuoteNode(kind_index))
    # Identifier indexation (in the old, the result is saved in a struct so we get the value property)
    expr_old = Expr(:., Expr(:ref, expr_old, QuoteNode(ident_index)), QuoteNode(:value))
    expr_new = Expr(:ref, expr_new, QuoteNode(ident_index))

    expr = quote
        try
            $expr_new / $expr_old - 1
        catch e
            @show $expr_new
            @show $expr_old
            addLog("regression", "Failed to compare new to old at $([d.name for d in _PRFT_LOCAL[:depth]])")
            0.0
        end
    end
    return expr
end


"""
  Returns an expression used to evaluate regression over a test target
"""
function buildRegression(context::Context)::Expr


    info = captureMethodologyInfo(:regression, context._local.enabled_methodologies)
    if info isa Nothing
        return quote end
    else
        return quote
            let
                # For all metrics if new worse than old by given threshold fail the test
                # TODO: Find the reference to OLD VALUES
                # TODO: Plug enable and disable
                # Make config for parsing which primitives and metrics to use
                # Primitives
                success = $(regression(:primitives,:median_time)) < $(info.params[:threshold])

                result = newMetricResult($mode,
                                       name="Median Time Difference",
                                       units="%",
                                       value=$(regression(:primitives, :median_time))*100)
                test = Metric_Test(
                    reference=0,
                    threshold_min_percent=$(info.params[:threshold]),
                    threshold_max_percent=nothing,
                    low_is_bad=false,
                    succeeded=success,
                    custom_plotting=Symbol[],
                    full_print=true
                )

                # Custom metrics
                $(
                #     for metric in context._local.custom_metrics
                #         success = -$(info.params[:threshold]) < $(@regression :metrics metric.symbol) < $(info.params[:threshold])

                # result = newMetricResult($mode,
                #                        name=metric.name * " Difference",
                #                        units="%",
                #                        value=value*100)
                # test = Metric_Test(
                #     reference=0,
                #     threshold_min_percent=-$(info.params[:threshold]),
                #     threshold_max_percent=$(info.params[:threshold]),
                #     low_is_bad=false,
                #     succeeded=success,
                #     custom_plotting=Symbol[],
                #     full_print=true
                # )
                #    end
                )

                methodology_res = Methodology_Result(
                    name="Regression"
                )

                push!(methodology_res.metrics, (result => test))


                # Printing
                if $(Configuration.CONFIG["general"]["verbose"]) || !(test.succeeded)
                    PerfTest.printMethodology(methodology_res, $(length(context._local.depth_record)), $(Configuration.CONFIG["general"]["plotting"]))
                end

                # Saving
                push!(by_index(_PRFT_GLOBAL[:new], _PRFT_LOCAL[:depth]).methodology_results, methodology_res)

                # Testing
                try
                    @test test.succeeded
                catch end
            end
        end
    end
end
