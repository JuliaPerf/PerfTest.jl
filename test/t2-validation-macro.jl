# Here the macro parser is tested, common errors are put to check if they are caught
@testset "Macro validation tests" begin

    ctx = PerfTest.Context(PerfTest.GlobalContext("path", PerfTest.VecErrorCollection(), PerfTest.formula_symbols))

    params = Dict{Symbol,PerfTest.MacroParameter}(
        :aparam => PerfTest.MacroParameter(:aparam, Float64, (x) -> true),
        :bparam => PerfTest.MacroParameter(:bparam, Float64, (x) -> (x > 0)),
        Symbol("") => PerfTest.MacroParameter(Symbol(""), Expr, (x) -> (x.args[1] == :+), true, true)
    )

    f = PerfTest.validateMacro(params)

    # VALID
    expr = quote
        @macro aparam = 3.45 4 + 5
    end

    f(expr, ctx)

    @test PerfTest.num_errors(ctx._global.errors) == 0


    # VALID
    expr = quote
        @macro aparam = 3.45 bparam = 3.0 4 + 5
    end

    parsed = f(expr, ctx)

    @test PerfTest.num_errors(ctx._global.errors) == 0

    # Test parameter parsing
    @test parsed[:aparam] == 3.45
    @test parsed[Symbol("")] == :(4+5)
    @test parsed[:bparam] == 3.0

    # aparam should be a float
    expr = quote
        @macro aparam = "eaf" 4 + 5
    end

    parsed = f(expr, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 1

    # Test parameter parsing
    @test parsed[Symbol("")] == :(4+5)
    @test !haskey(parsed, :aparam)


    # missing the final expression which is mandatory
    expr = quote
        @macro aparam = 4.45
    end

    f(expr, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 2

    # missing all arguments
    expr = quote
        @macro
    end

    f(expr, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 3

    # bparam should be positive
    expr = quote
        @macro bparam = -5.45 4+5
    end

    f(expr, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 4

    # expression should be a sum
    expr = quote
        @macro bparam = 5.45 4*5
    end

    f(expr, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 5

    # non-existent parameter
    expr = quote
        @macro zparam = 5.45 4 + 5
    end

    f(expr, ctx)
    @test PerfTest.num_errors(ctx._global.errors) == 6

    # Uncomment to see error messages
    #PerfTest.printErrors(ctx._global.errors)

end
