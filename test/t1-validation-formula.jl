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
