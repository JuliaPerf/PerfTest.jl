using Test
using PerfTest

# The symbol parameter of @define_metric, @auxiliary_metric and @define_benchmark sets the symbol other formulas and
# macros refer to them by, Symbol(name) when absent

# Every file based case runs in a fresh temporary directory, so test/perftest_config.toml is never touched
intempdir(f) = mktempdir(dir -> cd(f, dir))

# Messages of the parse errors of the last transform
parseErrors() = [e.name for e in PerfTest.ctx._global.errors.errors]

# Executes a saved suite in a fresh process with `dir` as working directory, as runperftests does
function execute(suite, dir)
    out = IOBuffer()
    cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $suite`; dir=dir)
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    output = String(take!(out))
    ok || println(output)
    return ok, output
end

# A recipe with `lines` inside its testset, before its @perftest
inTestset(lines...) = "using Test, PerfTest\n@testset \"T\" begin\n" * join(lines, "\n") * "\n    @perftest samples = 1 sin(1.0)\nend\n"

# Source of the suite generated from a recipe with `lines` inside its testset
function transformed(lines...)
    write("recipe.jl", inTestset(lines...))
    return string(PerfTest.transform("recipe.jl"))
end

const CT = """
    @define_metric name = "Custom time" units = "1/s" symbol = :ct begin
        1 / :median_time
    end"""

@testset "Custom metric symbol - formulas and @regression refer to the metric by its symbol" begin
    intempdir() do
        for symbol in (":ct", "\"ct\"")
            source = transformed(replace(CT, ":ct" => symbol),
                                 """@define_metric name = "Double" units = "1/s" begin
                                        2 * :ct
                                    end""",
                                 "@regression metrics = :ct")
            @test PerfTest.num_errors() == 0
            @test occursin("test_res.metrics[:ct]", source)
            # Without symbol, its name as a symbol, as before
            @test occursin("test_res.metrics[:Double]", source)
            @test !occursin("Symbol(\"Custom time\")", source)
        end

        # The name as a symbol is the default
        source = transformed("""@define_metric name = "custom_time" units = "1/s" begin
                                    1 / :median_time
                                end""",
                             "@regression metrics = \"custom_time\"")
        @test PerfTest.num_errors() == 0
        @test occursin("test_res.metrics[:custom_time]", source)
    end
end

@testset "Custom metric symbol - @auxiliary_metric and @define_benchmark" begin
    intempdir() do
        source = transformed(CT,
                             """@auxiliary_metric name = "Aux thing" units = "s" symbol = :ax begin
                                    2 * :ct
                                end""")
        @test PerfTest.num_errors() == 0
        @test occursin("test_res.auxiliar[:ax]", source)

        # A benchmark is referred to by its symbol too, e.g. by the effective memory throughput methodology
        source = transformed("""@define_benchmark name = "My bench" units = "GB/s" symbol = :bw begin
                                    2.0
                                end""",
                             """@define_eff_memory_throughput custom_benchmark = :bw begin
                                    1 / :median_time
                                end""")
        @test PerfTest.num_errors() == 0
        @test occursin("custom_benchmarks[:bw]", source)

        # Its name is no longer the symbol
        transformed("""@define_benchmark name = "bw" units = "GB/s" symbol = :other begin
                           2.0
                       end""",
                    """@define_eff_memory_throughput custom_benchmark = :bw begin
                           1 / :median_time
                       end""")
        @test parseErrors() == ["Undefined custom benchmark bw"]
    end
end

@testset "Custom metric symbol - errors" begin
    intempdir() do
        # A built-in formula symbol would be shadowed by the built-in value in formulas
        for (macro_name, kind) in (("@define_metric", "metric"), ("@auxiliary_metric", "metric"), ("@define_benchmark", "benchmark"))
            transformed("""$macro_name name = "m" units = "s" symbol = :median_time begin
                               1.0
                           end""")
            errors = parseErrors()
            @test length(errors) == 1
            @test startswith(only(errors), "The $macro_name name = \"m\" of recipe ")
            @test occursin("sets symbol = :median_time, which is a built-in formula symbol", only(errors))
        end

        transformed("""@define_metric name = "m" units = "s" symbol = "" begin
                           1.0
                       end""")
        @test length(parseErrors()) == 1
        @test occursin("sets an empty symbol", only(parseErrors()))

        # Not a symbol nor a string
        transformed("""@define_metric name = "m" units = "s" symbol = 3 begin
                           1.0
                       end""")
        @test parseErrors() == ["Invalid parameter type Int64 for symbol in macro @define_metric, expected Union{String, Symbol}"]

        # Referred to by its name instead of its symbol
        transformed(CT, "@regression metrics = \"Custom time\"")
        @test parseErrors() == ["Metric Custom time is not available in the current context. " *
                                "The metric named \"Custom time\" is referred to by its symbol :ct."]
    end
end

@testset "Generated suite - custom metrics, auxiliary metrics and benchmarks are resolved by their symbol" begin
    intempdir() do
        write("recipe.jl", inTestset(
            """@define_benchmark name = "My bench" units = "GB/s" symbol = :bw begin
                   2.0
               end""",
            CT,
            """@define_metric name = "Double" units = "1/s" begin
                   2 * :ct
               end""",
            """@auxiliary_metric name = "Aux thing" units = "s" symbol = "ax" begin
                   :ct * :bw
               end""",
            "@regression metrics = :ct"))
        suite = abspath("recipe_perfsuite.jl")
        PerfTest.saveExprAsFile(PerfTest.transform("recipe.jl"), suite)
        @test PerfTest.num_errors() == 0

        mktempdir() do dir
            results = joinpath(dir, ".perftests", "recipe.jl_PERFORMANCE.JLD2")
            # The first execution saves the reference, the second one compares against it
            for _ in 1:2
                ok, _ = execute(suite, dir)
                @test ok
            end

            test = PerfTest.retrievePerfTests(results)[end]
            @test Set(keys(test.metrics)) == Set([:ct, :Double])
            @test Set(keys(test.auxiliar)) == Set([:ax])
            @test test.metrics[:Double].value ≈ 2 * test.metrics[:ct].value
            # :bw is the benchmark, 2.0
            @test test.auxiliar[:ax].value ≈ 2 * test.metrics[:ct].value

            regression = PerfTest.retrievePerfTests(results; get=:methodologies)[end]
            @test ":ct Difference" in [m[1].name for m in regression.metrics]
        end
    end
end
