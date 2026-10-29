using Test
using PerfTest
using TOML
using MacroTools

const C = PerfTest.Configuration

# Every file based case runs in a fresh temporary directory, so test/perftest_config.toml is never touched
intempdir(f) = mktempdir(dir -> cd(f, dir))

# Executes a saved suite in a fresh process with `dir` as working directory, as runperftests does
function execute(suite, dir)
    out = IOBuffer()
    cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $suite`; dir=dir)
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    output = String(take!(out))
    ok || println(output)
    return ok, output
end

# Messages of the parse errors of the last transform
parseErrors() = [e.name for e in PerfTest.ctx._global.errors.errors]

parsingFailed(expr) = occursin("Parsing failed", string(expr))

# Messages of the errors logged while running f
function loggedErrors(f)
    logs, _ = Test.collect_test_logs(f)
    return [string(l.message) for l in logs if l.level == Base.CoreLogging.Error]
end

# Configuration a saved suite starts executing with, its first configuration call (see treeRun)
function generatedConfig(suite)
    found = nothing
    MacroTools.prewalk(PerfTest.loadFileAsExpr(suite)) do x
        if found === nothing && @capture(x, PerfTest._perftest_config(s_String))
            found = TOML.parse(s)
        end
        return x
    end
    return found
end

keysOf(section) = "The keys of section $section are: " * join(sort!(collect(keys(C.CONFIG_SHAPE[section]))), ", ")
const SECTIONS = "The sections are: " * join(sort!(collect(keys(C.CONFIG_SHAPE))), ", ")

const PERFTEST = "@testset \"T\" begin\n    @perftest samples = 1 sin(1.0)\nend\n"
recipeWith(lines...) = "using Test, PerfTest\n" * join(lines, "\n") * "\n" * PERFTEST
configCall(toml) = "@perftest_config \"\n$toml\n\""

quiet(f) = redirect_stdout(f, devnull)

@testset "@roofline - without actual_flops, general.autoflops = true is a parse error" begin
    intempdir() do
        write("recipe.jl", "using Test, PerfTest\n@testset \"R\" begin\n    @roofline begin\n        4\n    end\n    @perftest samples = 1 sin(1.0)\nend\n")

        # Used to throw a KeyError, reading CONFIG["autoflops"]
        code = string(PerfTest.transform("recipe.jl"))
        @test PerfTest.num_errors() == 0
        @test C.CONFIG["general"]["autoflops"] == false
        @test occursin("name = \"Attained Flops\", units = \"FLOP/s\", value = 0,", code)

        # Automatic flop counting is not supported (its flop test always failed), see t15-batch.jl for the message
        expr = PerfTest.transform("recipe.jl"; config=Dict("general" => Dict("autoflops" => true)))
        @test PerfTest.num_errors() == 1
        @test parsingFailed(expr)
    end
end

@testset "Logs - the dumps hold only the written content" begin
    intempdir() do
        PerfTest.transform(joinpath(@__DIR__, "test-recipes", "ex1-hierarchy-basic.jl"))
        written(ch) = String(take!(copy(PerfTest.LOGS.io_streams[ch])))

        all = PerfTest.dumpLogsString()
        @test !occursin('\0', all)
        @test all == join(["=== Channel: $ch ===\n" * written(ch) for ch in PerfTest.LOGS.channels])
        for (i, ch) in enumerate(PerfTest.LOGS.channels)
            @test PerfTest.dumpLogsString(i) == written(ch)
        end
        @test occursin("[TESTSET] New Group", PerfTest.dumpLogsString(1))

        printed = mktemp() do path, io
            redirect_stdout(() -> PerfTest.dumpLogs(), io)
            close(io)
            read(path, String)
        end
        @test !occursin('\0', printed)
        @test printed == all
    end
end

@testset "runperftests - the verbose argument only overrides the configuration when given" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        write(C.CONFIG_FILE, "[general]\nverbose = 1\nmax_saved_results = 5\n")
        suite = "recipe_perfsuite.jl"

        # Used to always set general.verbose to 0
        quiet(() -> runperftests("recipe.jl"; execute=false))
        @test C.CONFIG["general"]["verbose"] == 1
        @test generatedConfig(suite)["general"]["verbose"] == 1
        @test generatedConfig(suite)["general"]["max_saved_results"] == 5

        quiet(() -> runperftests("recipe.jl"; execute=false, config=Dict("general" => Dict("verbose" => 2))))
        @test C.CONFIG["general"]["verbose"] == 2
        @test generatedConfig(suite)["general"]["verbose"] == 2

        # Given, it overrides both the file and the config argument
        quiet(() -> runperftests("recipe.jl"; execute=false, verbose=0, config=Dict("general" => Dict("verbose" => 2))))
        @test C.CONFIG["general"]["verbose"] == 0
        @test generatedConfig(suite)["general"]["verbose"] == 0
        @test generatedConfig(suite)["general"]["max_saved_results"] == 5

        # A @perftest_config of the recipe takes priority over it
        write("recipe.jl", recipeWith(configCall("[general]\nverbose = 1")))
        quiet(() -> runperftests("recipe.jl"; execute=false, verbose=0))
        @test C.CONFIG["general"]["verbose"] == 1
        @test generatedConfig(suite)["general"]["verbose"] == 0
    end
end

@testset "runperftests - priority of the configuration: @perftest_config > config argument > file" begin
    intempdir() do
        write(C.CONFIG_FILE, "[general]\nmax_saved_results = 5\n[roofline]\ndefault_threshold = 0.1\n[regression]\ndefault_threshold = 1.5\n")
        config = Dict("general" => Dict("max_saved_results" => 6), "roofline" => Dict("default_threshold" => 0.2))
        write("recipe.jl", recipeWith(configCall("[general]\nmax_saved_results = 7")))

        for run in (() -> runperftests("recipe.jl"; execute=false, config=config),
                    () -> PerfTest.saveExprAsFile(PerfTest.transform("recipe.jl"; config=config), "recipe_perfsuite.jl"))
            rm("recipe_perfsuite.jl"; force=true)
            run()
            @test PerfTest.num_errors() == 0
            @test C.CONFIG["general"]["max_saved_results"] == 7
            @test C.CONFIG["roofline"]["default_threshold"] == 0.2
            @test C.CONFIG["regression"]["default_threshold"] == 1.5
            # Before the recipe changes it
            initial = generatedConfig("recipe_perfsuite.jl")
            @test initial["general"]["max_saved_results"] == 6
            @test initial["roofline"]["default_threshold"] == 0.2
            @test initial["regression"]["default_threshold"] == 1.5
        end
        # The config argument is not modified
        @test config == Dict("general" => Dict("max_saved_results" => 6), "roofline" => Dict("default_threshold" => 0.2))
    end
end

@testset "runperftests - the configuration file is loaded and reported once" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        write(C.CONFIG_FILE, "[general]\nverbse = 1\nmax_saved_results = \"5\"\n")
        file = "the configuration file perftest_config.toml"
        unknown = "Unknown configuration key general.verbse in $file, ignoring it. $(keysOf("general"))"
        wrongtype = "Incorrect type for configuration key general.max_saved_results in $file. Expected $Int, got String, using the default value 20"

        for run in (() -> runperftests("recipe.jl"; execute=false),
                    () -> runperftests("recipe.jl"; execute=false, verbose=0, config=Dict("general" => Dict("plotting" => false))),
                    () -> PerfTest.transform("recipe.jl"),
                    () -> PerfTest.transform("recipe.jl"; config=Dict("general" => Dict("plotting" => false))))
            @test loggedErrors(run) == [unknown, wrongtype]
            @test PerfTest.num_errors() == 0
        end
    end
end

@testset "Configuration argument - unknown sections and keys are errors, the rest applies" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        config = Dict("general" => Dict("foo" => 1, "max_saved_results" => 6), "genral" => Dict("verbose" => 1),
                      "roofline" => Dict("default_threshold" => "high"))

        for (run, source) in ((() -> runperftests("recipe.jl"; execute=false, config=config), "the config argument of runperftests"),
                              (() -> PerfTest.transform("recipe.jl"; config=config), "the config argument of PerfTest.transform"))
            @test loggedErrors(run) == [
                "Unknown configuration key general.foo in $source, ignoring it. $(keysOf("general"))",
                "Unknown configuration section genral in $source, ignoring it. $SECTIONS",
                "Incorrect type for configuration key roofline.default_threshold in $source. Expected Number, got String, ignoring it"]
            @test PerfTest.num_errors() == 0
            # They are not parse errors, the valid entries apply
            @test C.CONFIG["general"]["max_saved_results"] == 6
            @test C.CONFIG["roofline"]["default_threshold"] == C.DEFAULT["roofline"]["default_threshold"]
        end
    end
end

@testset "runperftests - clean deletes the suite, the configuration file, the results and the logs" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        # Of previous runs
        mkpath(joinpath(".perftest_logs", "previous"))
        mkpath(".perftests")

        # Used to throw removing ./perftest_logs instead of ./.perftest_logs. general.verbose >= 2 saves the logs of
        # the transform in that folder as well
        quiet(() -> runperftests("recipe.jl"; execute=false, verbose=2, clean=true))
        @test readdir() == ["recipe.jl"]
    end
end

@testset "Generated suite - the end message names failures only when there are" begin
    intempdir() do
        write("pass.jl", recipeWith())
        write("fail.jl", "using Test, PerfTest\n@testset \"T\" begin\n    @perfcompare :median_time < 0\n    @perftest samples = 1 sin(1.0)\nend\n")
        write("reference.jl", recipeWith(configCall("[regression]\ndedicated_reference_file = 'ref.JLD2'")))
        suite(name) = (PerfTest.saveExprAsFile(PerfTest.transform("$name.jl"), "$(name)_perfsuite.jl"); abspath("$(name)_perfsuite.jl"))

        mktempdir() do dir
            # Without regression.dedicated_reference_file it was printed even when every test passed
            ok, out = execute(suite("pass"), dir)
            @test ok
            @test !occursin("Some tests failed or errored.", out)
            @test isfile(joinpath(dir, ".perftests", "pass.jl_PERFORMANCE.JLD2"))

            ok, out = execute(suite("reference"), dir)
            @test ok
            @test !occursin("Some tests failed or errored.", out)
            @test occursin("All performance tests have passed. Values will be registered as reference for regression testing.", out)
            @test isfile(joinpath(dir, "ref.JLD2"))

            ok, out = execute(suite("fail"), dir)
            @test ok
            @test occursin("Some tests failed or errored.", out)
        end
    end
end

@testset "Generated suite - general.save_results" begin
    intempdir() do
        write(C.CONFIG_FILE, "[general]\nsave_results = false\n[regression]\ndedicated_reference_file = \"ref.JLD2\"\n")
        write("recipe.jl", recipeWith())
        PerfTest.saveExprAsFile(PerfTest.transform("recipe.jl"), "recipe_perfsuite.jl")
        @test PerfTest.num_errors() == 0

        mktempdir() do dir
            # The configuration of the executing directory does not apply
            write(joinpath(dir, C.CONFIG_FILE), "[general]\nsave_results = true\n")
            ok, out = execute(abspath("recipe_perfsuite.jl"), dir)
            @test ok
            @test occursin("The results of this execution have not been saved (general.save_results is false).", out)
            @test !occursin("Values will be registered", out)
            @test !occursin("Some tests failed or errored.", out)
            @test readdir(dir) == [C.CONFIG_FILE]
        end

        # From its place in the recipe onwards: the first top level testset saves its results, the second does not
        rm(C.CONFIG_FILE)
        write("recipe.jl", "using Test, PerfTest\n" * replace(PERFTEST, "\"T\"" => "\"A\"") * configCall("[general]\nsave_results = false") *
                           "\n" * replace(PERFTEST, "\"T\"" => "\"B\""))
        PerfTest.saveExprAsFile(PerfTest.transform("recipe.jl"), "recipe_perfsuite.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG["general"]["save_results"] == false

        mktempdir() do dir
            ok, out = execute(abspath("recipe_perfsuite.jl"), dir)
            @test ok
            @test count("have not been saved", out) == 1
            results = joinpath(dir, ".perftests", "recipe.jl_PERFORMANCE.JLD2")
            @test isfile(results)
            @test length(PerfTest.openDataFile(results).results) == 1
        end
    end
end

@testset "@perftest_threads - a malformed argument is a parse error" begin
    intempdir() do
        invalid(reason) = "Invalid thread arrangement in the @perftest_threads of recipe recipe.jl: $reason $(PerfTest.THREADS_OPTIONS)"
        notliteral(x) = invalid("`$x` is not a literal, the arrangement is read when the recipe is transformed so a variable or any other expression is not supported.")
        cases = [
            # Used to throw a MethodError
            "" => "Invalid number of arguments in @perftest_threads, expected from 1 to 1, got 0",
            ":single :numa" => "Invalid number of arguments in @perftest_threads, expected from 1 to 1, got 2",
            "x = 1" => "Last parameter cannot be a keyword (x) parameter on macro @perftest_threads",
            "(1, 2, 3)" => invalid("(1, 2, 3) has 3 element(s), expected exactly 2 (#numas, #threads_per_numa)."),
            "(1.5, 1)" => invalid("(1.5, 1), the elements of an arrangement must be integers or ratios of integers, got 1.5 (Float64)."),
            "(:numa, 1)" => invalid("(:numa, 1), the elements of an arrangement must be integers or ratios of integers, got :numa (Symbol)."),
            "[1.5]" => invalid("1.5 (Float64) is not a thread arrangement."),
            # Used to be evaluated in the PerfTest module during the transform, throwing an UndefVarError
            "n" => notliteral("n"),
            "(1, n)" => notliteral("(1, n)"),
            "f(1)" => notliteral("f(1)"),
            # Used to be reported along with "Invalid expression in macro @perftest_threads"
            ":foo" => invalid("symbol :foo is unrecognised, the symbols are :single, :numa and :all."),
            "[(1, 1), :foo]" => invalid("symbol :foo is unrecognised, the symbols are :single, :numa and :all."),
            "(1, 0)" => invalid("(1, 0), #threads_per_numa must be a positive integer, got 0."),
            "(0, 1)" => invalid("(0, 1), #numas must be a positive integer, got 0."),
            "(1, 3//2)" => invalid("(1, 3//2), thread ratio 3//2 is out of range, it must satisfy 0 < ratio ≤ 1."),
            "[0, 1]" => invalid("[0, 1], the thread ids of a manual pinning must be positive integers, got 0."),
            # Used to be accepted, the generated suite then threw
            "[]" => invalid("an empty list has no arrangement to use."),
            # Used to report only the expected type of the macro argument
            "\"numa\"" => invalid("\"numa\" (String) is not a thread arrangement."),
            "3" => invalid("3 (Int64) is not a thread arrangement."),
        ]
        for (arg, message) in cases
            write("recipe.jl", recipeWith("n = 2", "@perftest_threads $arg"))
            expr = PerfTest.transform("recipe.jl")
            @test parseErrors() == [message]
            @test parsingFailed(expr)
        end

        # Every invalid one of a list is reported
        write("recipe.jl", recipeWith("@perftest_threads [(0, 1), :foo, (1, 1)]"))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [invalid("(0, 1), #numas must be a positive integer, got 0."),
                                invalid("symbol :foo is unrecognised, the symbols are :single, :numa and :all.")]

        # In an included recipe, its own path is named
        write("child.jl", "@perftest_threads :foo\n")
        write("recipe.jl", "using Test, PerfTest\n@testset \"P\" begin\n    include(\"child.jl\")\n    @perftest samples = 1 sin(1.0)\nend\n")
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [replace(invalid("symbol :foo is unrecognised, the symbols are :single, :numa and :all."), "recipe recipe.jl" => "recipe child.jl")]

        # The valid ones
        for arg in (":single", ":numa", ":all", "(1, 1)", "(1, 1//2)", "(1//1, 1//1)", "[1, 2]", "[(1, 1), (1, 1//2)]")
            write("recipe.jl", recipeWith("@perftest_threads $arg"))
            code = string(PerfTest.transform("recipe.jl"))
            @test PerfTest.num_errors() == 0
            @test occursin("PerfTest.Topology.literallizeArrangement($(Meta.parse(arg)))", code)
        end
    end
end
