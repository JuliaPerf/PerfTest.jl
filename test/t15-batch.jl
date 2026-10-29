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

# Message of the error thrown by f
thrown(f) = try f(); "" catch e; sprint(showerror, e) end

# Executes a saved suite in a fresh process with `dir` as working directory, as runperftests does
function execute(suite, dir)
    out = IOBuffer()
    cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $suite`; dir=dir)
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    output = String(take!(out))
    ok || println(output)
    return ok, output
end

const PERFTEST = "@testset \"T\" begin\n    @perftest samples = 1 sin(1.0)\nend\n"
recipeWith(lines...) = "using Test, PerfTest\n" * join(lines, "\n") * "\n" * PERFTEST
configCall(toml) = "@perftest_config \"\n$toml\n\""
# A recipe with `lines` inside its testset, before its @perftest
inTestset(lines...) = "using Test, PerfTest\n@testset \"T\" begin\n" * join(lines, "\n") * "\n    @perftest samples = 1 sin(1.0)\nend\n"

# Transforms a recipe and saves the generated suite next to it
function generate(recipe; kw...)
    suite = abspath(replace(recipe, r"\.jl$" => "_perfsuite.jl"))
    PerfTest.saveExprAsFile(PerfTest.transform(recipe; kw...), suite)
    return suite
end

# ---------------------------------------------------------------------------------------------------------------------
# C23, a top level @testset for
# ---------------------------------------------------------------------------------------------------------------------

@testset "Generated suite - a top level @testset for saves each iteration, compared on the next execution" begin
    intempdir() do
        # Far apart durations, so an iteration compared against another one's reference is a ratio of 4 or 1/4
        write("recipe.jl", """
            using Test, PerfTest
            durations = Dict(1 => 0.05, 2 => 0.2)
            @testset "Root" for n in [1, 2]
                @perftest samples = 3 sleep(durations[n])
                @testset "Inner" begin
                    @perftest samples = 3 sleep(durations[n] / 2)
                end
            end
            """)
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0

        mktempdir() do dir
            results = joinpath(dir, ".perftests", "recipe.jl_PERFORMANCE.JLD2")
            paths = Set(["Root_1 > Test 1", "Root_1 > Inner > Test 1", "Root_2 > Test 1", "Root_2 > Inner > Test 1"])

            # Used to throw a MethodError, testsSucceeded(::Vector{Any}), before saving the results
            ok, out = execute(suite, dir)
            @test ok
            @test !occursin("MethodError", out)
            @test !occursin("Some tests failed or errored.", out)
            @test isfile(results)
            @test length(PerfTest.openDataFile(results).results) == 1
            # Each iteration under its name and iterator, as a nested @testset for
            @test Set(PerfTest.retrievePerfTests(results; pathonly=true)) == paths
            @test Set(PerfTest.retrievePerfTests(results; get=:testsets)) == Set(["Root_1", "Root_2", "Root_1/Inner", "Root_2/Inner"])
            tests = PerfTest.retrievePerfTests(results)
            @test sort([t.primitives[:iterator] for t in tests if t.primitives[:iterator] !== nothing]) == [1, 2]
            # No reference yet
            @test isempty(PerfTest.retrievePerfTests(results; get=:methodologies)[1].metrics)

            ok, out = execute(suite, dir)
            @test ok
            @test occursin("Previous performance reference for this configuration has been found", out)
            @test length(PerfTest.openDataFile(results).results) == 2
            @test Set(PerfTest.retrievePerfTests(results; pathonly=true)) == paths

            # Each iteration is compared against its own reference
            methodologies = PerfTest.retrievePerfTests(results; get=:methodologies)
            located = PerfTest.retrievePerfTests(results; get=:methodologies, pathonly=true)
            @test Set(located) == Set(p * " > Performance Regression Testing" for p in paths)
            for (m, path) in zip(methodologies, located)
                @test length(m.metrics) == 1
                ratio = m.metrics[1][1].value
                @test 60 < ratio < 160
            end
        end
    end
end

@testset "Generated suite - a top level @testset for fails when any of its iterations fails" begin
    intempdir() do
        write("recipe.jl", """
            using Test, PerfTest
            @testset "Root" for n in [1, 2]
                @perfcompare :iterator < 2
                @perftest samples = 1 sin(1.0)
            end
            """)
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0

        mktempdir() do dir
            ok, out = execute(suite, dir)
            @test ok
            @test occursin("Some tests failed or errored.", out)
            results = joinpath(dir, ".perftests", "recipe.jl_PERFORMANCE.JLD2")
            @test PerfTest.retrievePerfTests(results; where_pred=PerfTest.testPassed, pathonly=true) == ["Root_1 > Test 1"]
            @test PerfTest.retrievePerfTests(results; where_pred=PerfTest.testFailed, pathonly=true) == ["Root_2 > Test 1"]
        end
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# C27, automatic flop counting is not supported
# ---------------------------------------------------------------------------------------------------------------------

const AUTOFLOP = "Automatic flop counting is outdated and not supported, the :autoflop primitive is always 0."
const INSTEAD = "Give the flop count of the target explicitly instead: pass it to @roofline with actual_flops (a number, " *
                "or a formula as its operational intensity one), or write it in the formula in place of :autoflop."
const ROOFLINE_INSTEAD = "Pass the flop count of the target to @roofline with actual_flops instead (a number, or a formula as its operational intensity one)"
autoflopError(construct, how; instead = INSTEAD) = "$construct of recipe recipe.jl $how. $AUTOFLOP $instead"
rooflineAutoflopError(where) = autoflopError("The @roofline", "uses :autoflop in $where";
                                             instead = ROOFLINE_INSTEAD * ", and write it in place of :autoflop in its formulas.")
noActualFlopsError(from) = autoflopError("The @roofline", "gives no actual_flops, so with general.autoflops = true (from $from) " *
                                         "the flops of its target would be counted automatically"; instead = ROOFLINE_INSTEAD * ".")

@testset "Automatic flop counting - :autoflop in a formula or as a metric is a parse error" begin
    intempdir() do
        regression_instead = "Track a metric defined with @define_metric from the flop count of the target instead, or pass the flop count to @roofline with actual_flops."
        cases = [
            "@roofline actual_flops=:autoflop begin\n 4\n end" => rooflineAutoflopError("actual_flops"),
            "@roofline actual_flops=10 begin\n :autoflop / 4\n end" => rooflineAutoflopError("its operational intensity formula"),
            "@roofline actual_flops=:autoflop * 2 target_ratio=0.5 begin\n :autoflop / 4\n end" =>
                rooflineAutoflopError("actual_flops and in its operational intensity formula"),
            "@define_metric name=\"m\" units=\"FLOP/s\" begin\n :autoflop / :median_time\n end" =>
                autoflopError("The @define_metric name = \"m\"", "uses :autoflop in its formula"),
            "@auxiliary_metric name=\"a\" units=\"FLOP\" begin\n :autoflop\n end" =>
                autoflopError("The @auxiliary_metric name = \"a\"", "uses :autoflop in its formula"),
            "@perfcompare :autoflop > 1" => autoflopError("The @perfcompare :autoflop > 1", "uses :autoflop"),
            "@define_eff_memory_throughput begin\n :autoflop / :median_time\n end" =>
                autoflopError("The @define_eff_memory_throughput", "uses :autoflop in its formula"),
            "@regression metrics=:autoflop" => autoflopError("The @regression", "tracks the metric :autoflop"; instead = regression_instead),
            "@regression metrics=[:median_time, :autoflop] low_is_bad=false" =>
                autoflopError("The @regression", "tracks the metric :autoflop"; instead = regression_instead),
        ]
        for (line, message) in cases
            write("recipe.jl", inTestset(line))
            expr = PerfTest.transform("recipe.jl")
            @test parseErrors() == [message]
            @test parsingFailed(expr)
        end

        # The transform goes on, every use is reported
        write("recipe.jl", inTestset("@perfcompare :autoflop > 1", "@roofline actual_flops=10 begin\n :autoflop / 4\n end", "@regression metrics=:nope"))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [autoflopError("The @perfcompare :autoflop > 1", "uses :autoflop"),
                                rooflineAutoflopError("its operational intensity formula"),
                                "Metric nope is not available in the current context."]

        # Not a use when the methodology is disabled
        write("recipe.jl", replace(inTestset("@roofline actual_flops=:autoflop begin\n 4\n end", "@perfcompare :autoflop > 1"),
                                   "@testset" => configCall("[roofline]\nenabled = false\n[perfcompare]\nenabled = false") * "\n@testset"; count=1))
        PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0

        # With the flop count given, as the ex3-roofline.jl fixture
        write("recipe.jl", inTestset("@roofline actual_flops=2 * 10 target_ratio=0.5 begin\n 20 / 4\n end"))
        PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
    end
end

@testset "Automatic flop counting - general.autoflops = true is a parse error for a @roofline without actual_flops only" begin
    intempdir() do
        roofline = inTestset("@roofline begin\n 4\n end")

        # From the configuration file, the config argument or a @perftest_config, each one named
        write(C.CONFIG_FILE, "[general]\nautoflops = true\n")
        write("recipe.jl", roofline)
        expr = PerfTest.transform("recipe.jl")
        @test parseErrors() == [noActualFlopsError("the configuration file perftest_config.toml")]
        @test parsingFailed(expr)
        rm(C.CONFIG_FILE)

        PerfTest.transform("recipe.jl"; config=Dict("general" => Dict("autoflops" => true)))
        @test parseErrors() == [noActualFlopsError("the config argument of PerfTest.transform")]

        write("recipe.jl", replace(roofline, "@testset" => configCall("[general]\nautoflops = true") * "\n@testset"; count=1))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [noActualFlopsError("the @perftest_config of recipe recipe.jl")]

        # The key alone is not an error: with the flop count given, without a @roofline, or with it disabled
        for recipe in (inTestset("@roofline actual_flops=10 begin\n 4\n end"), recipeWith(),
                       replace(roofline, "@testset" => configCall("[roofline]\nenabled = false") * "\n@testset"; count=1))
            write("recipe.jl", recipe)
            PerfTest.transform("recipe.jl"; config=Dict("general" => Dict("autoflops" => true)))
            @test PerfTest.num_errors() == 0
        end

        # Without it, as before, the attained flops are not tested
        write("recipe.jl", roofline)
        PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# C33, launcher flags
# ---------------------------------------------------------------------------------------------------------------------

# Arguments of the command between the interpreter and the suite
interpreterArgs(cmd, suite) = cmd.exec[2:findfirst(==(suite), cmd.exec)-1]
suiteArgs(cmd, suite) = cmd.exec[findfirst(==(suite), cmd.exec)+1:end]

const CONFIG_CHANGE = "set general.numas and general.threads_per_numa (in the configuration file perftest_config.toml, with " *
                      "the config argument of runperftests or with a @perftest_config of the recipe), or give the recipe a " *
                      "@perftest_threads, which takes priority over them"
threadsFlagError(suite, flag, n, origin, literal, change, options) =
    "Cannot launch the suite $suite with the interpreter flag `$flag` of interpreter_flags: the launcher sets the number of " *
    "threads of the process that executes the suite, from the thread arrangement of the suite, to $n (--threads=$n), given " *
    "by $origin, which is $literal (#numas, #threads_per_numa) on this machine. Remove `$flag` from interpreter_flags. To " *
    "change the number of threads, $change, then generate the suite again (runperftests does). $options"

@testset "Launcher - the command the suite is launched with" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0
        defaults = ["--check-bounds=no", "--project=."]

        # An empty suite_flags used to be passed as an empty argument
        for suite_flags in ("", "  ")
            cmd = L.suiteCommand(suite, "", suite_flags)
            @test cmd.exec[end] == suite
            @test interpreterArgs(cmd, suite) == [defaults; "--threads=1"]
        end
        @test suiteArgs(L.suiteCommand(suite, "", "--size=3"), suite) == ["--size=3"]

        # In the given order, a flag whose value is a separate token used to be split from it
        cmd = L.suiteCommand(suite, "-L setup.jl -O3 -e x=1 -L more.jl")
        @test interpreterArgs(cmd, suite) == [defaults; "-L"; "setup.jl"; "-O3"; "-e"; "x=1"; "-L"; "more.jl"; "--threads=1"]
        # A flag given several times is passed each time, the interpreter decides
        @test interpreterArgs(L.suiteCommand(suite, "--depwarn=yes --depwarn=no"), suite) == [defaults; "--depwarn=yes"; "--depwarn=no"; "--threads=1"]
        # A default flag is replaced when given
        @test interpreterArgs(L.suiteCommand(suite, "--check-bounds=yes --project=other"), suite) == ["--check-bounds=yes", "--project=other", "--threads=1"]
        @test interpreterArgs(L.suiteCommand(suite, "--project"), suite) == ["--check-bounds=no", "--project", "--threads=1"]
    end
end

@testset "Launcher - the number of threads cannot be set with interpreter_flags" begin
    intempdir() do
        write("recipe.jl", recipeWith())
        suite = generate("recipe.jl")
        origin = "the thread setting of the suite, general.numas = \"single\" and general.threads_per_numa = \"single\""

        @test thrown(() -> L.suiteCommand(suite, "-t 4")) == threadsFlagError(suite, "-t 4", 1, origin, "(1, 1)", CONFIG_CHANGE, T.CONFIG_THREADS_OPTIONS)
        # Used to slip through, launching with two thread flags
        @test thrown(() -> L.suiteCommand(suite, "-t4")) == threadsFlagError(suite, "-t4", 1, origin, "(1, 1)", CONFIG_CHANGE, T.CONFIG_THREADS_OPTIONS)
        for (flags, flag) in ("-tauto" => "-tauto", "--threads=4" => "--threads=4", "--threads 4,1" => "--threads 4,1", "-O3 -t 2 -q" => "-t 2", "-t" => "-t")
            message = thrown(() -> L.suiteCommand(suite, flags))
            @test startswith(message, "Cannot launch the suite $suite with the interpreter flag `$flag` of interpreter_flags: ")
            @test occursin("to 1 (--threads=1)", message)
        end

        # From a @perftest_threads
        write("recipe.jl", recipeWith("@perftest_threads (1, 1)"))
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0
        change = "change the @perftest_threads of the recipe, or remove it to use the thread setting of the configuration " *
                 "(general.numas and general.threads_per_numa)"
        @test thrown(() -> L.suiteCommand(suite, "--threads=8")) ==
              threadsFlagError(suite, "--threads=8", 1, "the @perftest_threads (1, 1) of the recipe", "(1, 1)", change, PerfTest.THREADS_OPTIONS)
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# C34, general.logs_enabled
# ---------------------------------------------------------------------------------------------------------------------

@testset "Logs - general.logs_enabled = false writes no log folder nor log file" begin
    logsSaved(f) = intempdir() do
        quiet(f)
        @test PerfTest.num_errors() == 0
        ispath(".perftest_logs")
    end

    # Used to be saved anyway with general.verbose >= 2
    @test !logsSaved(() -> (write(C.CONFIG_FILE, "[general]\nlogs_enabled = false\nverbose = 2\n");
                            write("recipe.jl", recipeWith());
                            PerfTest.transform("recipe.jl")))
    @test !logsSaved(() -> (write("recipe.jl", recipeWith());
                            runperftests("recipe.jl"; execute=false, verbose=2, config=Dict("general" => Dict("logs_enabled" => false)))))
    # As general.verbose, decided by the configuration in force at the end of the recipe
    @test !logsSaved(() -> (write("recipe.jl", recipeWith(configCall("[general]\nverbose = 2")) * configCall("[general]\nlogs_enabled = false"));
                            PerfTest.transform("recipe.jl")))
    @test logsSaved(() -> (write(C.CONFIG_FILE, "[general]\nlogs_enabled = false\n");
                           write("recipe.jl", recipeWith(configCall("[general]\nverbose = 2\nlogs_enabled = true")));
                           PerfTest.transform("recipe.jl")))
    # Unchanged when enabled
    @test logsSaved(() -> (write("recipe.jl", recipeWith(configCall("[general]\nverbose = 2")));
                           PerfTest.transform("recipe.jl")))

    intempdir() do
        # Nothing is logged in memory either
        write(C.CONFIG_FILE, "[general]\nlogs_enabled = false\n")
        write("recipe.jl", recipeWith())
        PerfTest.transform("recipe.jl")
        @test !occursin("[TESTSET]", PerfTest.dumpLogsString())
        rm(C.CONFIG_FILE)
        PerfTest.transform("recipe.jl")
        @test occursin("[TESTSET]", PerfTest.dumpLogsString())
    end
end

@testset "Logs - general.logs_enabled = false applies to the executed suite" begin
    intempdir() do
        write(C.CONFIG_FILE, "[general]\nlogs_enabled = false\nverbose = 2\n")
        write("recipe.jl", recipeWith())
        suite = generate("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test !ispath(".perftest_logs")

        mktempdir() do dir
            ok, out = execute(suite, dir)
            @test ok
            # Its logs are neither printed nor saved, its other output is
            @test !occursin("[MACHINE]", out)
            @test occursin("AT: T", out)
            @test !ispath(joinpath(dir, ".perftest_logs"))
            @test isfile(joinpath(dir, ".perftests", "recipe.jl_PERFORMANCE.JLD2"))
        end
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# C36, @regression low_is_bad and threshold of another length than metrics
# ---------------------------------------------------------------------------------------------------------------------

lengthError(key, value, metrics) =
    "Invalid $key in the @regression of recipe recipe.jl: $key = $value gives $metrics. $key is either a single " *
    "$(key == "low_is_bad" ? Bool : Float64), which applies to every metric, or a vector with one " *
    "$(key == "low_is_bad" ? Bool : Float64) per metric, in the order of metrics"

@testset "@regression - low_is_bad and threshold give one value per metric, otherwise a parse error" begin
    intempdir() do
        cases = [
            # Used to report the error, then throw a MethodError, iterate(::Nothing)
            "metrics=:median_time low_is_bad=[true, false]" => [lengthError("low_is_bad", "[true, false]", "2 values for 1 metric (:median_time)")],
            "metrics=:median_time threshold=[0.9, 0.8]" => [lengthError("threshold", "[0.9, 0.8]", "2 values for 1 metric (:median_time)")],
            "metrics=:median_time threshold=[0.9, 0.8] low_is_bad=[true, false]" =>
                [lengthError("low_is_bad", "[true, false]", "2 values for 1 metric (:median_time)"),
                 lengthError("threshold", "[0.9, 0.8]", "2 values for 1 metric (:median_time)")],
            # The inverse ones, used to say "either 1 to apply to all" for a vector of 1 value
            "metrics=[:median_time, :min_time] low_is_bad=[true]" => [lengthError("low_is_bad", "[true]", "1 value for 2 metrics (:median_time, :min_time)")],
            "metrics=[:median_time, :min_time] threshold=[0.9]" => [lengthError("threshold", "[0.9]", "1 value for 2 metrics (:median_time, :min_time)")],
            "metrics=[:median_time, :min_time] threshold=[0.9, 0.8, 0.7]" => [lengthError("threshold", "[0.9, 0.8, 0.7]", "3 values for 2 metrics (:median_time, :min_time)")],
            "metrics=[:median_time, :min_time] low_is_bad=[true, false, true] threshold=[0.9]" =>
                [lengthError("low_is_bad", "[true, false, true]", "3 values for 2 metrics (:median_time, :min_time)"),
                 lengthError("threshold", "[0.9]", "1 value for 2 metrics (:median_time, :min_time)")],
            # Too many arguments, used to throw a MethodError, haskey(::Nothing, ...)
            "a=1 b=2 c=3 d=4 e=5" => ["Invalid number of arguments in @regression, expected from 0 to 4, got 5"],
        ]
        for (args, messages) in cases
            # At the top level testset, which already has a regression, and in a nested one
            for recipe in (inTestset("@regression $args"),
                           "using Test, PerfTest\n@testset \"T\" begin\n@testset \"N\" begin\n@regression $args\n@perftest samples = 1 sin(1.0)\nend\nend\n")
                write("recipe.jl", recipe)
                expr = PerfTest.transform("recipe.jl")
                @test parseErrors() == messages
                @test parsingFailed(expr)
            end
        end

        # The transform goes on collecting the errors of the recipe
        write("recipe.jl", inTestset("@regression metrics=:median_time low_is_bad=[true, false]", "@regression metrics=:nope",
                                     "@define_metric name=\"m\" units=\"x\" begin\n :autoflop\n end"))
        PerfTest.transform("recipe.jl")
        @test parseErrors() == [lengthError("low_is_bad", "[true, false]", "2 values for 1 metric (:median_time)"),
                                "Metric nope is not available in the current context.",
                                autoflopError("The @define_metric name = \"m\"", "uses :autoflop in its formula")]

        # One value per metric, or a single one for every metric
        # The comparisons of the generated suite, see regression()
        for (args, present, absent) in (("metrics=:median_time low_is_bad=[false] threshold=[1.2]", ["ratio < 1.2"], ["ratio < 1.1", "ratio >"]),
                                        ("metrics=[:median_time, :min_time] low_is_bad=false threshold=1.3", ["ratio < 1.3"], ["ratio < 1.1", "ratio >"]),
                                        ("metrics=[:median_time, :min_time] low_is_bad=[false, true]", ["ratio < 1.1", "ratio > 0.9"], []))
            write("recipe.jl", inTestset("@regression $args"))
            code = string(PerfTest.transform("recipe.jl"))
            @test PerfTest.num_errors() == 0
            @test all(c -> occursin(c, code), present)
            @test !any(c -> occursin(c, code), absent)
        end
    end
end
