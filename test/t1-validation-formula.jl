using MacroTools

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
        _PRFT_LOCAL[:primitives][:autoflop] / _PRFT_LOCAL[:primitives][:min_time] * a
    end)

    # illegal symbol
    form = quote
        :aflops
    end
    PerfTest.transformFormula(form, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 1

    # For now admitted, may be restricted in the future
    form = quote
        const a = 54
        :autoflop
    end
    PerfTest.transformFormula(form, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 1

    PerfTest.printErrors(ctx._global.errors)
end
