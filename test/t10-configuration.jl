using Test
using PerfTest
using TOML

const C = PerfTest.Configuration
recipe(name) = joinpath(@__DIR__, "test-recipes", name)

# Every file based case runs in a fresh temporary directory, so test/perftest_config.toml is never touched
intempdir(f) = mktempdir(dir -> cd(f, dir))

const DEFAULT_SNAPSHOT = deepcopy(C.DEFAULT)
const PRECOMPILATION_SNAPSHOT = deepcopy(C.PRECOMPILATION_CONFIG)

# Must run before anything else loads a configuration in this process
@testset "Configuration - state right after using PerfTest" begin
    @test C.CONFIG !== C.PRECOMPILATION_CONFIG
    @test C.CONFIG !== C.DEFAULT
    @test C.CONFIG == C.DEFAULT
    @test isempty(C.PARENT_CONFIGS)
    @test PerfTest.ctx === nothing
    @test PerfTest.LOG_FOLDER == ""
    # The callbacks installed by the dummy transform reference ctx, they must not outlive it
    @test PerfTest.Topology.addLog === PerfTest.Topology.defaultAddLog
    @test PerfTest.Topology.throwParseError! === PerfTest.Topology.defaultThrowParseError!
end

@testset "Configuration - PRECOMPILATION_CONFIG is valid" begin
    @test @test_logs C.validate_config(C.PRECOMPILATION_CONFIG, C.CONFIG_SHAPE)
    @test C.validate_config(C.DEFAULT, C.CONFIG_SHAPE)

    # The precompile workload swallows its errors, so its dummy transform is checked here
    intempdir() do
        PerfTest.init_dummy_flag = true
        try
            PerfTest.transform(joinpath(pkgdir(PerfTest), "src", "transform", "dummy.jl"))
            @test PerfTest.num_errors() == 0
            @test C.CONFIG == C.PRECOMPILATION_CONFIG
            @test C.CONFIG !== C.PRECOMPILATION_CONFIG
        finally
            PerfTest.init_dummy_flag = false
        end
    end
end

@testset "Configuration - missing file is created with the defaults" begin
    intempdir() do
        cfg = @test_logs (:info, r"not found") C.load_config()
        @test cfg == C.DEFAULT
        @test TOML.parsefile(C.CONFIG_FILE) == C.DEFAULT
    end
end

@testset "Configuration - every transform starts from a fresh configuration" begin
    intempdir() do
        # Sets memory_bandwidth.default_threshold with @perftest_config
        PerfTest.transform(recipe("ex15-recursive-config.jl"))
        @test C.CONFIG["memory_bandwidth"]["default_threshold"] == 0.75

        # As left behind by a transform that threw inside a recursive include
        push!(C.PARENT_CONFIGS, deepcopy(C.CONFIG))

        PerfTest.transform(recipe("ex1-hierarchy-basic.jl"))
        @test C.CONFIG == C.DEFAULT
        @test isempty(C.PARENT_CONFIGS)
    end
end

@testset "Configuration - included recipes layer their configuration over the parent's" begin
    intempdir() do
        # Value of regression.default_threshold before any recipe changes it
        write(C.CONFIG_FILE, "[regression]\ndefault_threshold = 1.3\n")

        PerfTest.transform(recipe("ex15-recursive-config.jl"))
        @test PerfTest.num_errors() == 0
        log = PerfTest.dumpLogsString()

        # Every top level testset gets a default regression, which uses regression.default_threshold
        regression_th(set, th) = occursin("Defined REGRESSION on [\"$set\"] METRICS: [:median_time] TH: [$th]", log)
        memory_th(set, th) = occursin("Defined Effective Memory Throughput on [\"$set\"] with benchmark MEM_STREAM_COPY and threshold $th\n", log)

        # Outer recipe: its own memory_bandwidth value, the file's regression value
        @test memory_th("BEFORE", 0.75)
        @test regression_th("BEFORE", 1.3)
        # Included recipe: its values take priority
        @test memory_th("INNER", 0.25)
        @test regression_th("INNER", 2.5)
        # Back in the outer recipe: both are restored
        @test memory_th("AFTER", 0.75)
        @test regression_th("AFTER", 1.3)

        @test C.CONFIG["memory_bandwidth"]["default_threshold"] == 0.75
        @test C.CONFIG["regression"]["default_threshold"] == 1.3
        @test isempty(C.PARENT_CONFIGS)
    end
end

@testset "Configuration - unparsable file is left untouched" begin
    intempdir() do
        broken = "# user comment\n[general]\nsave_folder = \".perftests\nverbose = 2\n"
        write(C.CONFIG_FILE, broken)

        # A non default state that must not survive the failed load
        C.load_config(Dict("general" => Dict("verbose" => 2)))

        cfg = @test_logs (:error, r"could not be parsed") C.load_config()
        @test cfg == C.DEFAULT
        @test read(C.CONFIG_FILE) == codeunits(broken)

        @test_logs (:error, r"could not be parsed") match_mode=:any PerfTest.transform(recipe("ex15-recursive-config.jl"))
        @test_logs (:error, r"could not be parsed") match_mode=:any PerfTest.transform(recipe("ex1-hierarchy-basic.jl"))
        @test C.CONFIG == C.DEFAULT
        @test read(C.CONFIG_FILE) == codeunits(broken)
    end
end

@testset "Configuration - partial file is merged over the defaults" begin
    intempdir() do
        partial = "[general]\nmax_saved_results = 7\n[regression]\nenabled = false\n"
        write(C.CONFIG_FILE, partial)

        expected = deepcopy(C.DEFAULT)
        expected["general"]["max_saved_results"] = 7
        expected["regression"]["enabled"] = false

        cfg = @test_logs C.load_config()
        @test cfg == expected

        # Both entry points used to crash on a partial file
        PerfTest.transform(recipe("ex1-hierarchy-basic.jl"))
        @test C.CONFIG == expected

        cp(recipe("ex1-hierarchy-basic.jl"), "recipe.jl")
        runperftests("recipe.jl"; execute=false)
        @test isfile("recipe_perfsuite.jl")
        @test C.CONFIG == expected

        @test read(C.CONFIG_FILE, String) == partial
    end
end

@testset "Configuration - wrongly typed entries fall back to their default" begin
    intempdir() do
        write(C.CONFIG_FILE, """
            MPI = 3
            [general]
            verbose = "2"
            max_saved_results = 7
            [roofline]
            default_threshold = "high"
            """)

        cfg = @test_logs (:error, r"general\.verbose") (:error, r"roofline\.default_threshold") (:error, r"section MPI") match_mode=:any C.load_config()

        @test cfg["general"]["verbose"] == C.DEFAULT["general"]["verbose"]
        @test cfg["general"]["max_saved_results"] == 7
        @test cfg["roofline"]["default_threshold"] == C.DEFAULT["roofline"]["default_threshold"]
        @test cfg["MPI"] == C.DEFAULT["MPI"]
        @test C.validate_config(cfg, C.CONFIG_SHAPE)
    end
end

@testset "Configuration - DEFAULT and PRECOMPILATION_CONFIG are never handed out" begin
    intempdir() do
        @test C.load_config() !== C.DEFAULT     # no file yet
        @test C.load_config() !== C.DEFAULT     # file just created with the defaults
        @test C.load_config(C.DEFAULT) !== C.DEFAULT
        @test C.load_dummy_config() !== C.PRECOMPILATION_CONFIG

        # load_config(dict) keeps a copy of its argument
        d = deepcopy(C.DEFAULT)
        C.load_config(d)
        d["general"]["verbose"] = 3
        @test C.CONFIG["general"]["verbose"] == 0

        # merge_configs shares nothing with its arguments, even when it ignores part of the override
        section = Dict("x" => 1)
        merged = C.merge_configs(C.DEFAULT, Dict("newsec" => section))
        @test merged["newsec"] == section
        @test merged["newsec"] !== section
        # A wrongly typed key is ignored on its own, its siblings apply
        partial = @test_logs (:error, r"general\.verbose") C.merge_configs(C.DEFAULT, Dict("general" => Dict("verbose" => "bad", "max_saved_results" => 2)))
        @test partial["general"]["verbose"] == C.DEFAULT["general"]["verbose"]
        @test partial["general"]["max_saved_results"] == 2
        @test partial !== C.DEFAULT
        @test partial["general"] !== C.DEFAULT["general"]

        # Mutate everything that was handed out, then keep loading and transforming
        for cfg in (C.load_config(), C.load_dummy_config(), merged, partial)
            cfg["general"]["verbose"] = 3
            cfg["regression"]["enabled"] = false
        end
        PerfTest.transform(recipe("ex15-recursive-config.jl"))
        PerfTest.transform(recipe("ex1-hierarchy-basic.jl"); config=Dict("general" => Dict("max_saved_results" => 2)))
        C.load_config()
    end

    @test C.DEFAULT == DEFAULT_SNAPSHOT
    @test C.PRECOMPILATION_CONFIG == PRECOMPILATION_SNAPSHOT
end
