using MacroTools
using Test
using PerfTest
@testset "Formula validation tests" begin


    ctx = PerfTest.Context(PerfTest.GlobalContext("path", PerfTest.VecErrorCollection(), PerfTest.formula_symbols))

    # VALID
    form = quote
        a = 54
        :autoflop / :min_time * a
    end

    r = PerfTest.transformFormula(form, ctx)
    @test r == MacroTools.prettify(quote
        a = 54
        test_res.primitives[:autoflop] / test_res.primitives[:min_time] * a
    end)

    form = quote
        a.b = 54
        a.c = :min_time
    end
    r = PerfTest.transformFormula(form, ctx)
    @test r == MacroTools.prettify(quote
        a.b = 54
        a.c = test_res.primitives[:min_time]
    end)

    form = quote
        A.b(C.D)
    end
    r = PerfTest.transformFormula(form, ctx)
    @test r == MacroTools.prettify(quote
        A.b(C.D)
    end)

    form = quote
        :time.median
    end
    r = PerfTest.transformFormula(form, ctx)
    @test r == MacroTools.prettify(quote
        test_res.primitives[:median_time]
    end)

    form = quote
        :penguin
    end
    r = PerfTest.transformFormula(form, ctx)
    @test r == MacroTools.prettify(quote
            if haskey(_PRFT_GLOBALS.custom_benchmarks, :penguin)
            PerfTest.metricSampledValue(_PRFT_GLOBALS.custom_benchmarks[:penguin])
        else
            if haskey(_PRFT_GLOBALS.builtins, :penguin)
                _PRFT_GLOBALS.builtins[:penguin]
            else
                if haskey(test_res.metrics, :penguin)
                    PerfTest.metricSampledValue(test_res.metrics[:penguin])
                else
                    if haskey(test_res.auxiliar, :penguin)
                        PerfTest.metricSampledValue(test_res.auxiliar[:penguin])
                    else
                        error("Unrecognized metric :penguin, it is not a custom metric, a benchmark or an alias of a loaded extension.")
                    end
                end
            end
        end
    end)

    form = quote
        :LIKWID.EVENTS.FLOPS_DP.FP_ARITH_INST_RETIRED_128B_PACKED_SINGLE
    end
    @test_throws ErrorException PerfTest.transformFormula(form, ctx)
    #= # illegal symbol
    form = quote
        :aflops
    end
    PerfTest.transformFormula(form, ctx)
    @test PerfTest.num_errors(ctx) == 1

    # For now admitted, may be restricted in the future
    form = quote
        const a = 54
        :autoflop
    end
    PerfTest.transformFormula(form, ctx)
    @test PerfTest.num_errors(ctx) == 1 =#

    PerfTest.printErrors(ctx)
end
