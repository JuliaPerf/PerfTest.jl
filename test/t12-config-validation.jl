using Test
using PerfTest
using TOML

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

# The default configuration with some (section, key, value) entries changed
function defaultWith(changes...)
    config = deepcopy(C.DEFAULT)
    for (section, key, value) in changes
        config[section][key] = value
    end
    return config
end

# Messages of the parse errors of the last transform
parseErrors() = [e.name for e in PerfTest.ctx._global.errors.errors]

# A recipe with the given @perftest_config calls, each one a TOML string without double quotes
configRecipe(tomls...) = """
    using Test, PerfTest
    x = 5
    $(join(["@perftest_config \"\n$toml\n\"" for toml in tomls], "\n"))
    @on_perftest_exec begin
        # Records the configuration seen by the executing suite in its working directory
        open(io -> PerfTest.TOML.print(io, PerfTest.Configuration.CONFIG), "config_T.toml", "w")
    end
    @testset "T" begin
        @perftest samples = 1 sin(1.0)
    end
    """

# Transforms a recipe written in the working directory, returns the generated expression
function transformRecipe(text)
    write("recipe.jl", text)
    return PerfTest.transform("recipe.jl")
end

parsingFailed(expr) = occursin("Parsing failed", string(expr))

# What an unknown entry is reported along with: the names its table can have, never a guess of the one it stands for
const SECTIONS = "The sections are: " * join(sort!(collect(keys(C.CONFIG_SHAPE))), ", ")
keysOf(section) = "The keys of section $section are: " * join(sort!(collect(keys(C.CONFIG_SHAPE[section]))), ", ")

@testset "Configuration - description of unknown entries" begin
    @test SECTIONS == "The sections are: MPI, bencher, general, machine_benchmarking, memory_bandwidth, perfcompare, regression, roofline"
    @test keysOf("MPI") == "The keys of section MPI are: enabled, mode"

    @test C.describe_unknown("verbse", 1, "general.", C.CONFIG_SHAPE["general"]) == ("key general.verbse", keysOf("general"))
    @test C.describe_unknown("genral", Dict(), "", C.CONFIG_SHAPE) == ("section genral", SECTIONS)
    @test C.describe_unknown("verbose", 1, "", C.CONFIG_SHAPE) == ("key verbose outside of any section", SECTIONS)
    @test C.describe_unknown("x", Dict(), "MPI.", C.CONFIG_SHAPE["MPI"]) == ("key MPI.x", keysOf("MPI"))
end

@testset "@perftest_config - unknown sections and keys are parse errors" begin
    intempdir() do
        expr = transformRecipe(configRecipe("[general]\nverbse = 3\nmax_saved_results = 7"))
        @test PerfTest.num_errors() == 1
        @test parseErrors() == ["Unknown configuration key general.verbse in the @perftest_config of recipe recipe.jl. $(keysOf("general"))"]
        @test parsingFailed(expr)
        # The valid sibling applies to the rest of the transform, the unknown key is not kept
        @test C.CONFIG == defaultWith(("general", "max_saved_results", 7))

        transformRecipe(configRecipe("[genral]\nverbose = 3"))
        @test parseErrors() == ["Unknown configuration section genral in the @perftest_config of recipe recipe.jl. $SECTIONS"]
        @test C.CONFIG == C.DEFAULT

        # A key out of its section
        transformRecipe(configRecipe("verbose = 3"))
        @test parseErrors() == ["Unknown configuration key verbose outside of any section in the @perftest_config of recipe recipe.jl. $SECTIONS"]

        # Every one of them is reported
        transformRecipe(configRecipe("[cuda]\nenabled = true", "[general]\nfoo = 1"))
        @test parseErrors() == ["Unknown configuration section cuda in the @perftest_config of recipe recipe.jl. $SECTIONS",
                                "Unknown configuration key general.foo in the @perftest_config of recipe recipe.jl. $(keysOf("general"))"]
        @test C.CONFIG == C.DEFAULT

        # In an included recipe, its own path is named
        write("child.jl", "@perftest_config \"\n[roofline]\nenable = false\n\"\n")
        transformRecipe("using Test, PerfTest\n@testset \"P\" begin\n    include(\"child.jl\")\n    @perftest samples = 1 sin(1.0)\nend\n")
        @test parseErrors() == ["Unknown configuration key roofline.enable in the @perftest_config of recipe child.jl. $(keysOf("roofline"))"]
    end
end

@testset "@perftest_config - wrong types are parse errors, the valid keys still apply" begin
    intempdir() do
        # Without regression.enabled = false every top level testset gets a default regression
        PerfTest.clearLogs()
        transformRecipe(configRecipe("[general]\nmax_saved_results = 7"))
        @test occursin("Defined REGRESSION", PerfTest.dumpLogsString())

        PerfTest.clearLogs()
        expr = transformRecipe(configRecipe("[general]\nverbose = 2.5\nmax_saved_results = 7\n[roofline]\ndefault_threshold = 'high'\nenabled = false",
                                            "MPI = 3\n[regression]\nenabled = false"))
        @test parseErrors() == ["Incorrect type for configuration key general.verbose in the @perftest_config of recipe recipe.jl. Expected Int64, got Float64",
                                "Incorrect type for configuration key roofline.default_threshold in the @perftest_config of recipe recipe.jl. Expected Number, got String",
                                "Expected a table for configuration section MPI in the @perftest_config of recipe recipe.jl, got Int64"]
        @test parsingFailed(expr)
        # Every valid key of both calls applies during the transform
        @test C.CONFIG == defaultWith(("general", "max_saved_results", 7), ("roofline", "enabled", false), ("regression", "enabled", false))
        # and the rules after them behave as usual, e.g. no default regression with regression.enabled = false
        @test !occursin("Defined REGRESSION", PerfTest.dumpLogsString())
    end
end

@testset "@perftest_config - the argument must be a string literal" begin
    intempdir() do
        for call in ("@perftest_config 3", "@perftest_config x", "@perftest_config", "@perftest_config \"[general]\" \"verbose = 1\"")
            text = "using Test, PerfTest\nx = \"[general]\\nverbose = 1\"\n$call\n@testset \"T\" begin\n    @perftest samples = 1 sin(1.0)\nend\n"
            expr = transformRecipe(text)
            @test PerfTest.num_errors() == 1
            @test occursin("@perftest_config", only(parseErrors()))
            @test parsingFailed(expr)
            @test C.CONFIG == C.DEFAULT
        end
        @test parseErrors() == ["Invalid number of arguments in @perftest_config, expected from 1 to 1, got 2"]
    end
end

@testset "@perftest_config - an interpolated value can only set a key that takes a string" begin
    intempdir() do
        transformRecipe(configRecipe("[general]\nverbose = '\$(x)'\nmax_saved_results = 7"))
        @test parseErrors() == ["Incorrect type for configuration key general.verbose in the @perftest_config of recipe recipe.jl. Expected Int64, got an interpolated String (interpolation is only supported inside string values)"]
        @test C.CONFIG == defaultWith(("general", "max_saved_results", 7))

        # Keys that take a string, alone or among other types
        transformRecipe(configRecipe("[general]\nnumas = '\$(x)'\nsave_folder = 'results_\$(x)'\nmax_saved_results = 7"))
        @test PerfTest.num_errors() == 0
        @test C.CONFIG == defaultWith(("general", "max_saved_results", 7))
    end
end

@testset "Generated suite - a wrongly typed entry is ignored on its own at execution" begin
    intempdir() do
        expr = transformRecipe(configRecipe("[general]\nmax_saved_results = 5\n[roofline]\ndefault_threshold = 0.3"))
        @test PerfTest.num_errors() == 0
        suite = abspath("recipe_perfsuite.jl")
        PerfTest.saveExprAsFile(expr, suite)

        # As in a suite generated by a version of the package with a different configuration schema, the transform
        # reports a wrongly typed entry as a parse error
        code = read(suite, String)
        @test count("default_threshold = 0.3", code) == 1
        write(suite, replace(code, "default_threshold = 0.3" => "default_threshold = 'low'"))

        mktempdir() do dir
            ok, out = execute(suite, dir)
            @test ok
            @test occursin("Incorrect type for configuration key roofline.default_threshold in a configuration call of the executing suite. Expected Number, got String, ignoring it", out)
            # Its sibling still applies
            @test TOML.parsefile(joinpath(dir, "config_T.toml")) == defaultWith(("general", "max_saved_results", 5))
        end
    end
end

@testset "Configuration merges - a wrongly typed entry is ignored on its own" begin
    override = Dict("general" => Dict("verbose" => "bad", "max_saved_results" => 2), "MPI" => 3, "roofline" => Dict("enabled" => false))
    merged = @test_logs (:error, "Incorrect type for configuration key general.verbose in the override. Expected Int64, got String, ignoring it") (:error, "Expected a table for configuration section MPI in the override, got Int64, ignoring it") match_mode=:any C.merge_configs(C.DEFAULT, override; source = "the override")
    @test merged == defaultWith(("general", "max_saved_results", 2), ("roofline", "enabled", false))

    # At execution
    C.load_config(C.DEFAULT)
    @test_logs (:error, r"general\.verbose in a configuration call of the executing suite") PerfTest._perftest_config("[general]\nverbose = 'x'\nmax_saved_results = 3\n")
    @test C.CONFIG == defaultWith(("general", "max_saved_results", 3))

    # config keyword of the transform
    intempdir() do
        write("recipe.jl", configRecipe("[roofline]\nenabled = false"))
        @test_logs (:error, r"general\.verbose in the config argument of PerfTest\.transform") match_mode=:any PerfTest.transform("recipe.jl"; config=Dict("general" => Dict("verbose" => "bad", "max_saved_results" => 2)))
        @test PerfTest.num_errors() == 0
        @test C.CONFIG == defaultWith(("general", "max_saved_results", 2), ("roofline", "enabled", false))
    end
end

@testset "Configuration file - unknown sections and keys are errors, the rest of the file applies" begin
    intempdir() do
        write(C.CONFIG_FILE, """
            [genral]
            verbose = 1
            [general]
            foo = 1
            verbse = 1
            verbose = "2"
            max_saved_results = 7
            """)

        file = "the configuration file perftest_config.toml"
        cfg = @test_logs((:error, "Unknown configuration key general.foo in $file, ignoring it. $(keysOf("general"))"),
                         (:error, "Unknown configuration key general.verbse in $file, ignoring it. $(keysOf("general"))"),
                         (:error, "Unknown configuration section genral in $file, ignoring it. $SECTIONS"),
                         (:error, "Incorrect type for configuration key general.verbose in $file. Expected Int64, got String, using the default value 0"),
                         C.load_config())
        # The rest of the file applies
        @test cfg["general"]["max_saved_results"] == 7
        @test cfg["general"]["verbose"] == C.DEFAULT["general"]["verbose"]

        # They are not parse errors of the transform
        write("recipe.jl", configRecipe("[roofline]\nenabled = false"))
        @test_logs (:error, r"general\.verbse") match_mode=:any PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG["general"]["max_saved_results"] == 7

        # The [bencher] section, read when a suite executes
        write(C.CONFIG_FILE, "[bencher]\napikey = \"KEY\"\nproject_name = \"p\"\n")
        @test_logs (:error, "Unknown configuration key bencher.apikey in $file, ignoring it. $(keysOf("bencher"))") C.load_bencher_config()
        @test C.CONFIG["bencher"]["api_key"] == C.DEFAULT["bencher"]["api_key"]
        @test C.CONFIG["bencher"]["project_name"] == "p"
    end
    C.load_config(C.DEFAULT)
end
