using Test
using PerfTest

const C = PerfTest.Configuration
const T = PerfTest.Topology
const L = PerfTest.Launch

# Every file based case runs in a fresh temporary directory, so test/perftest_config.toml is never touched
intempdir(f) = mktempdir(dir -> cd(f, dir))

quiet(f) = redirect_stdout(f, devnull)

# Messages of the parse errors of the last transform
parseErrors() = [e.name for e in PerfTest.ctx._global.errors.errors]

parsingFailed(expr) = occursin("Parsing failed", string(expr))

# Messages of the errors logged while running f
function loggedErrors(f)
    logs, _ = Test.collect_test_logs(f)
    return [string(l.message) for l in logs if l.level == Base.CoreLogging.Error]
end

# Message of the error thrown by f
thrown(f) = try f(); "" catch e; sprint(showerror, e) end

const PERFTEST = "@testset \"T\" begin\n    @perftest samples = 1 sin(1.0)\nend\n"
recipeWith(lines...) = "using Test, PerfTest\n" * join(lines, "\n") * "\n" * PERFTEST
configCall(toml) = "@perftest_config \"\n$toml\n\""

# Transforms a recipe and saves the generated suite next to it
function generate(recipe; kw...)
    suite = abspath(replace(recipe, r"\.jl$" => "_perfsuite.jl"))
    PerfTest.saveExprAsFile(PerfTest.transform(recipe; kw...), suite)
    return suite
end

const FILE = "the configuration file perftest_config.toml"
const DEFAULT = "the default configuration"
inRecipe(recipe) = "the @perftest_config of recipe $recipe"

# The thread setting of a suite, as named in its errors, with where each key comes from
setting(numas, numas_from, threads, threads_from) =
    "general.numas = $(repr(numas)) (from $numas_from) and general.threads_per_numa = $(repr(threads)) (from $threads_from)"
threadError(setting, problems...) =
    "Invalid thread setting of the generated suite, $setting: $(join(problems, ", ")). $(T.THREAD_SETTING_RULE) $(T.CONFIG_THREADS_OPTIONS)"
launchError(suite, numas, threads, problems...) =
    "Cannot launch the suite $suite, the thread setting of the generated suite is invalid, general.numas = $(repr(numas)) " *
    "and general.threads_per_numa = $(repr(threads)): $(join(problems, ", ")). $(T.THREAD_SETTING_RULE) $(T.CONFIG_THREADS_OPTIONS)"

# Number of threads the launcher starts the suite with
launchThreads(suite) = only(a for a in L.suiteCommand(suite).exec if startswith(a, "--threads="))

# Must run before anything else loads a configuration in this process
@testset "Configuration - no source nor thread setting is left by the precompilation" begin
    @test isempty(C.SOURCES)
    @test isempty(C.PARENT_SOURCES)
    @test isempty(PerfTest.THREAD_SETTING)
end

# ---------------------------------------------------------------------------------------------------------------------
# C8, general.numas and general.threads_per_numa give the thread setting the launcher uses
# ---------------------------------------------------------------------------------------------------------------------

@testset "Thread setting - conversion of general.numas and general.threads_per_numa" begin
    # A string names a whole arrangement, in both keys
    @test T.arrangementFromConfig("single", "single") === (1, 1)
    @test T.arrangementFromConfig("numa", "numa") === (1, 1 // 1)
    @test T.arrangementFromConfig("all", "all") === (1 // 1, 1 // 1)
    # Numbers: an integer stays, a float in (0, 1] is a ratio
    @test T.arrangementFromConfig(2, 4) === (2, 4)
    @test T.arrangementFromConfig(1, 0.5) === (1, 1 // 2)
    @test T.arrangementFromConfig(0.25, 3) === (1 // 4, 3)
    @test T.arrangementFromConfig(1.0, 1.0) === (1 // 1, 1 // 1)
    @test T.arrangementFromConfig(1, 0.3) === (1, 3 // 10)
    # Every arrangement is one, as for @perftest_threads
    for numas in ("single", "numa", "all"), arrangement in (T.arrangementFromConfig(numas, numas), T.arrangementFromConfig(1, 0.5))
        @test arrangement isa T.ArrangementSpec
        @test T.validateArrangement(arrangement, error)
    end

    # Anything else is not interpreted
    @test T.arrangementFromConfig("singel", "single") == ["general.numas = \"singel\" is not the name of an arrangement"]
    @test T.arrangementFromConfig("single", "Single") == ["general.threads_per_numa = \"Single\" is not the name of an arrangement"]
    @test T.arrangementFromConfig("single", "all") == ["general.numas = \"single\" and general.threads_per_numa = \"all\" name different arrangements, a name is given in both keys"]
    @test T.arrangementFromConfig("numa", 2) == ["general.numas = \"numa\" names an arrangement but general.threads_per_numa = 2 is a number, a name is given in both keys"]
    @test T.arrangementFromConfig(0.5, "all") == ["general.threads_per_numa = \"all\" names an arrangement but general.numas = 0.5 is a number, a name is given in both keys"]
    @test T.arrangementFromConfig(0, 1) == ["general.numas = 0 is an integer below 1"]
    @test T.arrangementFromConfig(1, -2) == ["general.threads_per_numa = -2 is an integer below 1"]
    @test T.arrangementFromConfig(0.0, 1) == ["general.numas = 0.0 is a float outside (0, 1]"]
    @test T.arrangementFromConfig(1, 1.5) == ["general.threads_per_numa = 1.5 is a float outside (0, 1]"]
    @test T.arrangementFromConfig(2.0, 1) == ["general.numas = 2.0 is a float outside (0, 1]"]
    @test T.arrangementFromConfig(-0.5, 1) == ["general.numas = -0.5 is a float outside (0, 1]"]
    # A Bool is an Integer in Julia, and passes the type of the keys
    @test T.arrangementFromConfig(true, 1) == ["general.numas = true is a Bool, neither a number nor the name of an arrangement"]
    # Each invalid key is named
    @test T.arrangementFromConfig("bogus", 0) == ["general.numas = \"bogus\" is not the name of an arrangement", "general.threads_per_numa = 0 is an integer below 1"]
end

@testset "Thread setting - the launcher starts the suite with it" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        literal(arrangement) = T.literallizeArrangement(arrangement)

        # Default, unchanged: one thread
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test L.suiteArrangement(suite) === (1, 1)
        @test L.retrieveThreadConfig(suite) == (1, 1)
        @test launchThreads(suite) == "--threads=1"

        # Resolved on this machine, see literallizeArrangement
        T.hwloc_topology === nothing && T.getMachineTopology!()
        cases = [
            ("\"single\"", "\"single\"") => ((1, 1), (1, 1)),
            ("\"numa\"", "\"numa\"") => ((1, 1 // 1), (1, T.threadsPerNuma()[1])),
            ("\"all\"", "\"all\"") => ((1 // 1, 1 // 1), (T.numberOfNUMAS(), minimum(T.threadsPerNuma()))),
            ("1", "1") => ((1, 1), (1, 1)),
            ("1", "0.5") => ((1, 1 // 2), (1, max(1, floor(Int, T.threadsPerNuma()[1] / 2)))),
            ("1.0", "1.0") => ((1 // 1, 1 // 1), (T.numberOfNUMAS(), minimum(T.threadsPerNuma()))),
        ]
        for ((numas, threads), (arrangement, resolved)) in cases
            write(C.CONFIG_FILE, "[general]\nnumas = $numas\nthreads_per_numa = $threads\n")
            suite = @test_logs generate("recipe.jl")
            @test PerfTest.num_errors() == 0
            @test L.suiteArrangement(suite) === arrangement
            @test L.retrieveThreadConfig(suite) == resolved == literal(arrangement)
            @test launchThreads(suite) == "--threads=$(prod(resolved))"
        end

        # The setting is valid, but this machine cannot satisfy it
        write(C.CONFIG_FILE, "[general]\nnumas = $(T.numberOfNUMAS() + 1)\nthreads_per_numa = 1\n")
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test L.suiteArrangement(suite) === (T.numberOfNUMAS() + 1, 1)
        @test thrown(() -> L.suiteCommand(suite)) ==
              "Cannot launch the suite $suite with the thread arrangement $(repr((T.numberOfNUMAS() + 1, 1))) on this machine: " *
              "Invalid thread arrangement: requested $(T.numberOfNUMAS() + 1) NUMA domain(s) but the host only has $(T.numberOfNUMAS())."
    end
end

@testset "Thread setting - an invalid one from the configuration file or argument is an error, the launcher refuses it" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        cases = [
            ("\"bogus\"", "\"single\"") => ("bogus", "single", ["general.numas = \"bogus\" is not the name of an arrangement"]),
            ("\"single\"", "\"all\"") => ("single", "all", ["general.numas = \"single\" and general.threads_per_numa = \"all\" name different arrangements, a name is given in both keys"]),
            ("\"numa\"", "2") => ("numa", 2, ["general.numas = \"numa\" names an arrangement but general.threads_per_numa = 2 is a number, a name is given in both keys"]),
            ("0", "1") => (0, 1, ["general.numas = 0 is an integer below 1"]),
            ("1", "1.5") => (1, 1.5, ["general.threads_per_numa = 1.5 is a float outside (0, 1]"]),
        ]
        for ((numas, threads), (n, t, problems)) in cases
            write(C.CONFIG_FILE, "[general]\nnumas = $numas\nthreads_per_numa = $threads\n")
            suite = abspath("recipe_perfsuite.jl")
            # Not a parse error, as the other errors of the file, the suite is generated
            @test loggedErrors(() -> generate("recipe.jl")) == [threadError(setting(n, FILE, t, FILE), problems...)]
            @test PerfTest.num_errors() == 0
            # The launcher cannot start it
            @test thrown(() -> L.suiteArrangement(suite)) == launchError(suite, n, t, problems...)
            @test thrown(() -> L.suiteCommand(suite)) == launchError(suite, n, t, problems...)
        end

        # Only one of the keys in the file, the other one has its default value
        write(C.CONFIG_FILE, "[general]\nnumas = \"all\"\n")
        problem = "general.numas = \"all\" and general.threads_per_numa = \"single\" name different arrangements, a name is given in both keys"
        @test loggedErrors(() -> generate("recipe.jl")) == [threadError(setting("all", FILE, "single", DEFAULT), problem)]

        # The config argument, over the file
        rm(C.CONFIG_FILE)
        config = Dict("general" => Dict("threads_per_numa" => 2))
        problem = "general.numas = \"single\" names an arrangement but general.threads_per_numa = 2 is a number, a name is given in both keys"
        @test loggedErrors(() -> PerfTest.transform("recipe.jl"; config=config)) ==
              [threadError(setting("single", DEFAULT, 2, "the config argument of PerfTest.transform"), problem)]
        @test PerfTest.num_errors() == 0

        # runperftests does not launch it. The previous transform created the configuration file, with every key
        message = Ref("")
        errors = loggedErrors(() -> message[] = thrown(() -> quiet(() -> runperftests("recipe.jl"; config=config))))
        @test errors == [threadError(setting("single", FILE, 2, "the config argument of runperftests"), problem)]
        @test message[] == launchError("recipe_perfsuite.jl", "single", 2, problem)
    end
end

@testset "Thread setting - an invalid one set by a recipe is a parse error, naming where each key comes from" begin
    intempdir() do
        write("recipe.jl", recipeWith(configCall("[general]\nnumas = 'numa'\nthreads_per_numa = 'all'")))
        expr = PerfTest.transform("recipe.jl")
        @test parseErrors() == [threadError(setting("numa", inRecipe("recipe.jl"), "all", inRecipe("recipe.jl")),
                                            "general.numas = \"numa\" and general.threads_per_numa = \"all\" name different arrangements, a name is given in both keys")]
        @test parsingFailed(expr)

        for (toml, n, t, problem) in (("numas = 'bogus'\nthreads_per_numa = 'bogus'", "bogus", "bogus", "general.numas = \"bogus\" is not the name of an arrangement, general.threads_per_numa = \"bogus\" is not the name of an arrangement"),
                                      ("numas = 1\nthreads_per_numa = 0", 1, 0, "general.threads_per_numa = 0 is an integer below 1"),
                                      ("numas = 1.5\nthreads_per_numa = 1", 1.5, 1, "general.numas = 1.5 is a float outside (0, 1]"),
                                      ("numas = 2\nthreads_per_numa = 'numa'", 2, "numa", "general.threads_per_numa = \"numa\" names an arrangement but general.numas = 2 is a number, a name is given in both keys"))
            write("recipe.jl", recipeWith(configCall("[general]\n$toml")))
            expr = PerfTest.transform("recipe.jl")
            @test parseErrors() == [threadError(setting(n, inRecipe("recipe.jl"), t, inRecipe("recipe.jl")), problem)]
            @test parsingFailed(expr)
        end

        # One key from the recipe, the other one from the file: still a parse error
        write(C.CONFIG_FILE, "[general]\nnumas = \"all\"\n")
        write("recipe.jl", recipeWith(configCall("[general]\nthreads_per_numa = 2")))
        expr = PerfTest.transform("recipe.jl")
        @test parseErrors() == [threadError(setting("all", FILE, 2, inRecipe("recipe.jl")),
                                            "general.numas = \"all\" names an arrangement but general.threads_per_numa = 2 is a number, a name is given in both keys")]
        @test parsingFailed(expr)
        # The other errors of the recipe are reported as well
        write("recipe.jl", recipeWith(configCall("[general]\nthreads_per_numa = 2\nverbse = 1")))
        PerfTest.transform("recipe.jl")
        @test length(parseErrors()) == 2
    end
end

@testset "Thread setting - one per suite, from the last configuration call that sets each key, even in an included recipe" begin
    intempdir() do
        write(C.CONFIG_FILE, "[general]\nnumas = 2\nthreads_per_numa = 4\n")
        parent(child_toml; after = "") = """
            using Test, PerfTest
            @perftest_config "
            [general]
            numas = 'all'
            threads_per_numa = 'all'
            "
            @testset "PARENT" begin
                include("child.jl")
                @perftest samples = 1 sin(1.0)
            end
            $after
            """
        child(toml) = "@perftest_config \"\n[general]\n$toml\n\"\n@testset \"CHILD\" begin\n    @perftest samples = 1 sin(1.0)\nend\n"

        # The included recipe sets it for the whole suite, the rest of its configuration only applies to its own part
        write("parent.jl", parent(""))
        write("child.jl", child("numas = 1\nthreads_per_numa = 0.5\nmax_saved_results = 3"))
        suite = generate("parent.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG["general"]["numas"] == "all"
        @test C.CONFIG["general"]["max_saved_results"] == 20
        @test L.retrieveConfigThreadSpecs(PerfTest.loadFileAsExpr(suite)) == (1, 0.5)
        @test L.suiteArrangement(suite) === (1, 1 // 2)

        # Only one key in the included recipe, the other one from the parent: the setting of the suite is invalid
        write("child.jl", child("numas = 1"))
        expr = PerfTest.transform("parent.jl")
        @test parseErrors() == [threadError(setting(1, inRecipe("child.jl"), "all", inRecipe("parent.jl")),
                                            "general.threads_per_numa = \"all\" names an arrangement but general.numas = 1 is a number, a name is given in both keys")]
        @test parsingFailed(expr)

        # A later call of the parent sets it back, only the final setting is checked
        write("parent.jl", parent("numas = 1"; after = "@perftest_config \"\n[general]\nnumas = 'all'\n\""))
        suite = generate("parent.jl")
        @test PerfTest.num_errors() == 0
        @test L.suiteArrangement(suite) === (1 // 1, 1 // 1)

        # Neither is the setting between two calls of a recipe
        write("recipe.jl", recipeWith(configCall("[general]\nnumas = 'numa'"), configCall("[general]\nthreads_per_numa = 'numa'")))
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test L.suiteArrangement(suite) === (1, 1 // 1)
    end
end

@testset "Thread setting - @perftest_threads takes priority, the setting is still checked" begin
    intempdir() do
        write(C.CONFIG_FILE, "[general]\nnumas = \"all\"\nthreads_per_numa = \"all\"\n")
        for (arg, arrangement) in (":single" => :single, "(1, 1)" => (1, 1), ":numa" => :numa)
            write("recipe.jl", recipeWith("@perftest_threads $arg"))
            suite = generate("recipe.jl")
            @test PerfTest.num_errors() == 0
            @test L.suiteArrangement(suite) === arrangement
        end
        @test launchThreads(abspath("recipe_perfsuite.jl")) == "--threads=$(prod(T.literallizeArrangement(:numa)))"

        # An invalid setting is reported even when @perftest_threads takes priority over it
        write(C.CONFIG_FILE, "[general]\nnumas = \"bogus\"\nthreads_per_numa = \"bogus\"\n")
        write("recipe.jl", recipeWith("@perftest_threads (1, 1)"))
        problems = ("general.numas = \"bogus\" is not the name of an arrangement", "general.threads_per_numa = \"bogus\" is not the name of an arrangement")
        @test loggedErrors(() -> generate("recipe.jl")) == [threadError(setting("bogus", FILE, "bogus", FILE), problems...)]
        @test L.suiteArrangement(abspath("recipe_perfsuite.jl")) === (1, 1)
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# C14, an explicit @regression without threshold takes it from regression.default_threshold
# ---------------------------------------------------------------------------------------------------------------------

regressionRecipe(regression; before = "") = """
    using Test, PerfTest
    $before
    @testset "T" begin
        @define_metric name = "m1" units = "1/s" begin
            1 / :median_time
        end
        @define_metric name = "m2" units = "s" begin
            :median_time
        end
        $regression
        @perftest samples = 1 sin(1.0)
    end
    """

# Thresholds and low_is_bad of the last regression defined for testset T, as logged
function lastRegression()
    found = collect(eachmatch(r"Defined REGRESSION on \[\"T\"\] METRICS: (\[.*?\]) TH: (\[.*?\]) LOW_IS_BAD: (.*)", PerfTest.dumpLogsString()))
    return Tuple(last(found).captures)
end

regressionError(recipe, metrics, threshold, from) =
    "Invalid regression threshold in the @regression of recipe $recipe: it gives no threshold, so $metrics, where a low value is bad " *
    "(low_is_bad = true), would take 2 − regression.default_threshold, but regression.default_threshold = $(repr(threshold)) " *
    "(from $from) gives 2 − $(repr(threshold)) = $(repr(Float64(2 - parse(BigFloat, string(Float64(threshold)))))), which every " *
    "ratio new/reference passes. Give that @regression an explicit threshold (threshold=..., the ratio new/reference a metric " *
    "with low_is_bad = true must stay above), or set regression.default_threshold below 2"

@testset "@regression - a missing threshold comes from regression.default_threshold, following low_is_bad" begin
    intempdir() do
        # Default configuration: as before for low_is_bad = true, the default of the macro
        for (regression, threshold, low_is_bad) in (("@regression", "[0.9]", "Bool[1]"),
                                                    ("@regression low_is_bad=true", "[0.9]", "Bool[1]"),
                                                    # Used to be 0.9, which needed a 10% faster time to pass
                                                    ("@regression low_is_bad=false", "[1.1]", "Bool[0]"),
                                                    # An explicit threshold is kept
                                                    ("@regression threshold=0.8 low_is_bad=true", "[0.8]", "Bool[1]"),
                                                    ("@regression threshold=1.3 low_is_bad=false", "[1.3]", "Bool[0]"))
            write("recipe.jl", regressionRecipe(regression))
            code = string(PerfTest.transform("recipe.jl"))
            @test PerfTest.num_errors() == 0
            @test lastRegression() == ("[:median_time]", threshold, low_is_bad)
            # Exactly 0.9, not 2 - 1.1 = 0.8999999999999999
            @test occursin("ratio $(low_is_bad == "Bool[1]" ? ">" : "<") $(threshold[2:end-1])", code)
        end

        # Another regression.default_threshold
        write(C.CONFIG_FILE, "[regression]\ndefault_threshold = 1.25\n")
        for (regression, threshold) in (("@regression", "[0.75]"), ("@regression low_is_bad=false", "[1.25]"))
            write("recipe.jl", regressionRecipe(regression))
            PerfTest.transform("recipe.jl")
            @test PerfTest.num_errors() == 0
            @test lastRegression()[2] == threshold
        end

        # Per metric, following each low_is_bad
        write("recipe.jl", regressionRecipe("@regression metrics=[:median_time, :m1, :m2] low_is_bad=[false, true, false]"))
        PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test lastRegression() == ("[:median_time, :m1, :m2]", "[1.25, 0.75, 1.25]", "Any[false, true, false]")
        write("recipe.jl", regressionRecipe("@regression metrics=[:median_time, :m1] low_is_bad=true"))
        PerfTest.transform("recipe.jl")
        @test lastRegression()[2] == "[0.75, 0.75]"

        # From a @perftest_config, an included recipe's one only applies to its own part
        rm(C.CONFIG_FILE)
        write("child.jl", "@perftest_config \"\n[regression]\ndefault_threshold = 1.5\n\"\n@testset \"CHILD\" begin\n    @regression\n    @perftest samples = 1 sin(1.0)\nend\n")
        write("recipe.jl", regressionRecipe("@regression"; before = configCall("[regression]\ndefault_threshold = 1.2") * "\ninclude(\"child.jl\")"))
        PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test lastRegression()[2] == "[0.8]"
        @test occursin("Defined REGRESSION on [\"CHILD\"] METRICS: [:median_time] TH: [0.5] LOW_IS_BAD: Bool[1]", PerfTest.dumpLogsString())
    end
end

@testset "@regression - an integer regression.default_threshold" begin
    intempdir() do
        # Used to throw, as the regression of every top level testset only took a Float64
        write(C.CONFIG_FILE, "[regression]\ndefault_threshold = 1\n")
        write("recipe.jl", recipeWith())
        code = string(PerfTest.transform("recipe.jl"))
        @test PerfTest.num_errors() == 0
        @test occursin("ratio < 1.0", code)

        for (regression, threshold) in (("@regression", "[1.0]"), ("@regression low_is_bad=false", "[1.0]"), ("@regression threshold=0.9", "[0.9]"))
            write("recipe.jl", regressionRecipe(regression))
            PerfTest.transform("recipe.jl")
            @test PerfTest.num_errors() == 0
            @test lastRegression()[2] == threshold
        end

        write("recipe.jl", regressionRecipe("@regression"; before = configCall("[regression]\ndefault_threshold = 3")))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [regressionError("recipe.jl", ":median_time", 3, inRecipe("recipe.jl"))]
    end
end

@testset "@regression - regression.default_threshold of 2 or more leaves no threshold where a low value is bad" begin
    intempdir() do
        write(C.CONFIG_FILE, "[regression]\ndefault_threshold = 2.0\n")
        for regression in ("@regression", "@regression low_is_bad=true")
            write("recipe.jl", regressionRecipe(regression))
            expr = PerfTest.transform("recipe.jl")
            @test parseErrors() == [regressionError("recipe.jl", ":median_time", 2.0, FILE)]
            @test parsingFailed(expr)
        end

        # Only the metrics with low_is_bad = true are named
        write("recipe.jl", regressionRecipe("@regression metrics=[:median_time, :m1, :m2] low_is_bad=[true, false, true]"))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [regressionError("recipe.jl", ":median_time, :m2", 2.0, FILE)]

        # Fine where a high value is bad, or with an explicit threshold
        for regression in ("@regression low_is_bad=false", "@regression threshold=0.9", "@regression metrics=[:median_time, :m1] low_is_bad=[false, false]")
            write("recipe.jl", regressionRecipe(regression))
            PerfTest.transform("recipe.jl")
            @test PerfTest.num_errors() == 0
        end

        # Where it comes from: the config argument, or a @perftest_config of an included recipe
        write("recipe.jl", regressionRecipe("@regression"))
        PerfTest.transform("recipe.jl"; config=Dict("regression" => Dict("default_threshold" => 2.5)))
        @test parseErrors() == [regressionError("recipe.jl", ":median_time", 2.5, "the config argument of PerfTest.transform")]

        rm(C.CONFIG_FILE)
        # The including recipe gets its own value back, the regression of its testset is fine
        write("child.jl", "@perftest_config \"\n[regression]\ndefault_threshold = 2.5\n\"\n@testset \"CHILD\" begin\n    @regression\n    @perftest samples = 1 sin(1.0)\nend\n")
        write("recipe.jl", regressionRecipe("@regression"; before = "include(\"child.jl\")"))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [regressionError("child.jl", ":median_time", 2.5, inRecipe("child.jl"))]
        @test lastRegression()[2] == "[0.9]"
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# C11, MPI.enabled cannot be set by a recipe, the logs are saved from the final configuration
# ---------------------------------------------------------------------------------------------------------------------

mpiError(recipe) = "Configuration key MPI.enabled cannot be set in the @perftest_config of recipe $recipe: the MPI mode is decided " *
                   "with it before the recipe is read, so it would not apply. Set it in the configuration file perftest_config.toml " *
                   "or with the config argument of runperftests or PerfTest.transform"

@testset "@perftest_config - MPI.enabled is a parse error, the rest of the macro applies" begin
    intempdir() do
        # Used to be silently ignored, the MPI mode is decided before the recipe is read
        for value in ("true", "false", "'\$(x)'", "1")
            write("recipe.jl", recipeWith("x = 1", configCall("[MPI]\nenabled = $value\nmode = 'other'\n[general]\nmax_saved_results = 7")))
            expr = PerfTest.transform("recipe.jl")
            @test parseErrors() == [mpiError("recipe.jl")]
            @test parsingFailed(expr)
            @test C.CONFIG["MPI"]["enabled"] == false
            # MPI.mode is not read anywhere, it can still be set
            @test C.CONFIG["MPI"]["mode"] == "other"
            @test C.CONFIG["general"]["max_saved_results"] == 7
            @test PerfTest.mode == PerfTest.NormalMode
        end

        write("child.jl", "@perftest_config \"\n[MPI]\nenabled = true\n\"\n")
        write("recipe.jl", recipeWith("include(\"child.jl\")"))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [mpiError("child.jl")]

        # The configuration file and the config argument still set it. Without the MPI package the suite is not MPI aware
        for run in (() -> PerfTest.transform("recipe.jl"; config=Dict("MPI" => Dict("enabled" => true))),
                    () -> (write(C.CONFIG_FILE, "[MPI]\nenabled = true\n"); PerfTest.transform("recipe.jl")))
            write("recipe.jl", recipeWith())
            @test_logs (:warn, "[MPI] MPI enabled in configuration but MPI package not found, defaulting to non-MPI mode") match_mode=:any run()
            @test PerfTest.num_errors() == 0
            @test C.CONFIG["MPI"]["enabled"] == true
            @test PerfTest.mode == PerfTest.NormalMode
        end
    end
end

@testset "Transform - the logs are saved as decided by the general.verbose in force at the end of the recipe" begin
    logsSaved(f) = intempdir() do
        quiet(f)
        @test PerfTest.num_errors() == 0
        isdir(".perftest_logs") && !isempty(readdir(".perftest_logs"))
    end

    # Used to depend on the value before the recipe is read only
    @test logsSaved(() -> (write("recipe.jl", recipeWith(configCall("[general]\nverbose = 2")));
                           PerfTest.transform("recipe.jl")))
    @test !logsSaved(() -> (write(C.CONFIG_FILE, "[general]\nverbose = 2\n");
                            write("recipe.jl", recipeWith(configCall("[general]\nverbose = 0")));
                            PerfTest.transform("recipe.jl")))
    # At the end of the recipe, after its testsets
    @test logsSaved(() -> (write("recipe.jl", recipeWith() * configCall("[general]\nverbose = 2"));
                           PerfTest.transform("recipe.jl")))
    # The included recipe gives the configuration back after it
    @test !logsSaved(() -> (write("child.jl", configCall("[general]\nverbose = 2"));
                            write("recipe.jl", recipeWith("include(\"child.jl\")"));
                            PerfTest.transform("recipe.jl")))
    # Unchanged without a @perftest_config
    @test logsSaved(() -> (write(C.CONFIG_FILE, "[general]\nverbose = 2\n");
                           write("recipe.jl", recipeWith());
                           PerfTest.transform("recipe.jl")))
    @test logsSaved(() -> (write("recipe.jl", recipeWith());
                           runperftests("recipe.jl"; execute=false, verbose=2)))
    # A @perftest_config takes priority over the verbose argument
    @test !logsSaved(() -> (write("recipe.jl", recipeWith(configCall("[general]\nverbose = 0")));
                            runperftests("recipe.jl"; execute=false, verbose=2)))
end
