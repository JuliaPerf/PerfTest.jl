using Test
using PerfTest
using TOML

const C = PerfTest.Configuration
recipe(name) = joinpath(@__DIR__, "test-recipes", name)

# Every file based case runs in a fresh temporary directory, so test/perftest_config.toml is never touched
intempdir(f) = mktempdir(dir -> cd(f, dir))

# Transforms a fixture recipe and saves the generated suite in the working directory
function generate(name)
    suite = abspath(replace(name, r"\.jl$" => "_perfsuite.jl"))
    PerfTest.saveExprAsFile(PerfTest.transform(recipe(name)), suite)
    return suite
end

# Executes a saved suite in a fresh process with `dir` as working directory, as runperftests does
function execute(suite, dir)
    out = IOBuffer()
    cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $suite`; dir=dir)
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    output = String(take!(out))
    ok || println(output)
    return ok, output
end

# Configuration seen by the executing suite at a point of a fixture, see dumpConfig in the fixtures
dumped(dir, name) = TOML.parsefile(joinpath(dir, "config_$(name).toml"))

# The default configuration with some (section, key, value) entries changed
function defaultWith(changes...)
    config = deepcopy(C.DEFAULT)
    for (section, key, value) in changes
        config[section][key] = value
    end
    return config
end

@testset "Generated suite - executes with the configuration it was generated with" begin
    intempdir() do
        write(C.CONFIG_FILE, """
            [general]
            save_folder = "resultsA"
            verbose = 1
            max_saved_results = 3
            [regression]
            dedicated_reference_file = "refA.JLD2"
            """)
        generated = defaultWith(("general", "save_folder", "resultsA"), ("general", "verbose", 1),
                                ("general", "max_saved_results", 3), ("regression", "dedicated_reference_file", "refA.JLD2"))

        # No @perftest_config in the recipe
        suite = generate("ex16-config-generated-suite.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG == generated
        # Transforming does not create the results folder
        @test !ispath("resultsA")

        # Executed elsewhere, next to a different configuration file
        mktempdir() do dir
            other = "[general]\nsave_folder = \"resultsB\"\nverbose = 0\n[regression]\ndedicated_reference_file = \"refB.JLD2\"\n"
            write(joinpath(dir, C.CONFIG_FILE), other)

            ok, out = execute(suite, dir)
            @test ok
            @test dumped(dir, "GENERATED") == generated

            # general.save_folder, regression.dedicated_reference_file and regression.enabled
            @test isfile(joinpath(dir, "resultsA", "ex16-config-generated-suite.jl_PERFORMANCE.JLD2"))
            @test isfile(joinpath(dir, "refA.JLD2"))
            @test !ispath(joinpath(dir, "resultsB"))
            @test !ispath(joinpath(dir, "refB.JLD2"))
            @test !ispath(joinpath(dir, ".perftests"))
            # general.verbose, used by the testset output and the logs
            @test occursin("AT: GENERATED", out)
            @test occursin("[MACHINE]", out)

            @test read(joinpath(dir, C.CONFIG_FILE), String) == other
        end
    end
end

@testset "Generated suite - included recipes configure only their part of the executed suite" begin
    intempdir() do
        outer = defaultWith(("general", "max_saved_results", 11))
        inner = defaultWith(("general", "max_saved_results", 3), ("general", "verbose", 1))

        suite = generate("ex17-config-recursive.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG == outer
        @test isempty(C.PARENT_CONFIGS)

        mktempdir() do dir
            ok, out = execute(suite, dir)
            @test ok

            @test dumped(dir, "BEFORE") == outer
            @test dumped(dir, "INNER") == inner
            # Back in the outer recipe, in the rest of the suite and after it
            @test dumped(dir, "AFTER") == outer
            @test dumped(dir, "END") == outer

            # general.verbose, used by the testset output
            @test occursin("AT: INNER", out)
            @test !occursin("AT: AFTER", out)
            @test !occursin("AT: OUTER", out)
        end
    end
end

@testset "Generated suite - interpolated keys take their value at execution" begin
    intempdir() do
        # The keys that are not interpolated take effect during the transform
        generated = defaultWith(("general", "max_saved_results", 4), ("roofline", "default_threshold", 0.3))

        suite = generate("ex18-config-interpolation.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG == generated

        # No placeholder of the interpolated values, neither in the configuration nor in the suite
        code = read(suite, String)
        @test occursin("results_\$(tag)", code)
        @test !occursin(r"results_(?!\$)", code)
        @test !occursin(r"ref_(?!\$)", code)
        @test !ispath("results_")
        @test !ispath(".perftests")

        mktempdir() do dir
            ok, out = execute(suite, dir)
            @test ok

            executed = defaultWith(("general", "max_saved_results", 4), ("roofline", "default_threshold", 0.3),
                                   ("general", "save_folder", "results_run2"), ("regression", "dedicated_reference_file", "ref_run2.JLD2"))
            @test dumped(dir, "INTERPOLATION") == executed

            @test isfile(joinpath(dir, "results_run2", "ex18-config-interpolation.jl_PERFORMANCE.JLD2"))
            @test isfile(joinpath(dir, "ref_run2.JLD2"))
            @test !ispath(joinpath(dir, "results_"))
            @test !ispath(joinpath(dir, "ref_.JLD2"))
            @test !ispath(joinpath(dir, ".perftests"))
        end
    end
end

@testset "Generated suite - the Bencher configuration is read at execution" begin
    intempdir() do
        write(C.CONFIG_FILE, "[bencher]\napi_key = \"GENERATION_KEY\"\nproject_name = \"generation_project\"\n")

        suite = generate("ex19-config-bencher.jl")
        @test PerfTest.num_errors() == 0
        # Available to the transform as any other section
        @test C.CONFIG["bencher"]["api_key"] == "GENERATION_KEY"
        # but never written into the suite
        code = read(suite, String)
        @test !occursin("GENERATION_KEY", code)
        @test !occursin("generation_project", code)

        mktempdir() do dir
            write(joinpath(dir, C.CONFIG_FILE), "[general]\nmax_saved_results = 2\n[bencher]\napi_key = \"EXECUTION_KEY\"\n")
            ok, out = execute(suite, dir)
            @test ok

            # Only the [bencher] section comes from the file of the executing directory
            @test dumped(dir, "BENCHER_FILE") == defaultWith(("bencher", "api_key", "EXECUTION_KEY"))
            # A @perftest_config of the recipe takes priority over it
            @test dumped(dir, "BENCHER_RECIPE") == defaultWith(("bencher", "api_key", "EXECUTION_KEY"), ("bencher", "project_name", "from_recipe"))
        end

        # Without a configuration file the defaults are used, and no file is created
        mktempdir() do dir
            ok, out = execute(suite, dir)
            @test ok
            @test dumped(dir, "BENCHER_FILE") == C.DEFAULT
            @test !ispath(joinpath(dir, C.CONFIG_FILE))
        end
    end
end

@testset "Generated suite - thread arrangements are resolved on the executing machine" begin
    intempdir() do
        write("recipe.jl", "using Test, PerfTest\n@perftest_threads :numa\n@testset \"T\" begin\n    @perftest samples = 1 sin(1.0)\nend\n")
        code = string(PerfTest.transform("recipe.jl").args[1])
        @test PerfTest.num_errors() == 0
        @test occursin("literallizeArrangement(:numa)", code)
    end
end

threadsParent = """
    using Test, PerfTest
    @perftest_config "
    [general]
    numas = 1
    "
    @testset "PARENT" begin
        include("threads_child.jl")
        @perftest samples = 1 sin(1.0)
    end
    # Does not set the thread keys
    @perftest_config "
    [roofline]
    default_threshold = 0.3
    "
    """
threadsChild = """
    x = 5
    @perftest_config "
    [general]
    numas = 3
    threads_per_numa = 8
    "
    # Unknown before the suite executes
    @perftest_config "
    [general]
    threads_per_numa = '\$(x)'
    "
    @testset "CHILD" begin
        @perftest samples = 1 sin(1.0)
    end
    """

@testset "Generated suite - one thread setting per suite, from the last configuration call that sets it" begin
    intempdir() do
        write(C.CONFIG_FILE, "[general]\nnumas = 2\nthreads_per_numa = 4\n")
        threadSpecs(suite) = PerfTest.Launch.retrieveConfigThreadSpecs(PerfTest.loadFileAsExpr(suite))

        # Without @perftest_config, the configuration the suite was generated with
        @test threadSpecs(generate("ex16-config-generated-suite.jl")) == (2, 4)

        # An included recipe sets it for the whole suite, unlike the rest of its configuration
        write("threads_parent.jl", threadsParent)
        write("threads_child.jl", threadsChild)
        PerfTest.saveExprAsFile(PerfTest.transform("threads_parent.jl"), "threads_parent_perfsuite.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG["general"]["numas"] == 1
        @test @test_logs threadSpecs("threads_parent_perfsuite.jl") == (3, 8)
    end
end

@testset "Generated suite - transforming creates no results folder" begin
    intempdir() do
        PerfTest.transform(recipe("ex1-hierarchy-basic.jl"))
        @test PerfTest.num_errors() == 0
        @test readdir() == [C.CONFIG_FILE]
    end
end

# A recipe with a single @perftest_config
configRecipe(toml) = """
    using Test, PerfTest
    x = "general"
    @perftest_config "
    $toml
    "
    @testset "T" begin
        @perftest samples = 1 sin(1.0)
    end
    """

@testset "@perftest_config - TOML errors are parse errors" begin
    intempdir() do
        # Interpolation as a whole value, in a table header, in a key, and invalid TOML
        for toml in ("[regression]\ndefault_threshold = \$(x)", "[\$(x)]\nverbose = 3", "[general]\n\$(x) = 3", "this is = = not toml")
            write("recipe.jl", configRecipe(toml))
            PerfTest.transform("recipe.jl")
            @test PerfTest.num_errors() == 1
            @test C.CONFIG == C.DEFAULT
        end

        # Interpolation inside a string value is the supported case
        write("recipe.jl", configRecipe("[general]\nsave_folder = 'results_\$(x)'\nmax_saved_results = 7"))
        PerfTest.transform("recipe.jl")
        @test PerfTest.num_errors() == 0
        @test C.CONFIG == defaultWith(("general", "max_saved_results", 7))
    end
end

# A recipe that includes another inside a testset
parentRecipe(child) = """
    using Test, PerfTest
    @perftest_config "
    [general]
    max_saved_results = 11
    "
    @testset "PARENT" begin
        include("$child")
        @perftest samples = 1 sin(1.0)
    end
    """

@testset "Included recipes - a failing include leaves the configuration of the including recipe" begin
    intempdir() do
        parent = defaultWith(("general", "max_saved_results", 11))
        child_config = "@perftest_config \"\n[general]\nmax_saved_results = 3\n\"\n"

        # Collected as a parse error
        write("parent_bad_toml.jl", parentRecipe("child_bad_toml.jl"))
        write("child_bad_toml.jl", child_config * "@perftest_config \"this is = = not toml\"\n")
        PerfTest.transform("parent_bad_toml.jl")
        @test PerfTest.num_errors() == 1
        @test C.CONFIG == parent
        @test isempty(C.PARENT_CONFIGS)

        # Thrown out of the transform
        write("parent_throws.jl", parentRecipe("child_throws.jl"))
        write("child_throws.jl", child_config * "include(\"does_not_exist.jl\")\n")
        @test_throws SystemError PerfTest.transform("parent_throws.jl")
        @test C.CONFIG == parent
        @test isempty(C.PARENT_CONFIGS)
    end
end
