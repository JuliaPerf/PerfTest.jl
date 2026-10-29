module PerfTest

export @perftest, @on_perftest_exec, @on_perftest_ignore, @perftest_config, @export_vars, @define_benchmark,
    @define_eff_memory_throughput, @def_eff_mem, @define_metric, @roofline, @define_test_metric, magnitudeAdjust, @perfcompare, @perfcmp, runperftests, @regression

using Test
using MacroTools
using MLStyle.Modules.AST
using Configurations
using Printf

using BenchmarkTools
using LinearAlgebra
using Hwloc


var"@capture" = MacroTools.var"@capture"

include("extension_stubs.jl")

### PARSING TIME

# Data structures used in the parse and transform procedures
include("transform/datastruct.jl")

# Structures and defaults of the package configuration
include("transform/configuration.jl")     # NOTE

# Formatting
include("printing.jl")
include("logs.jl")

# General validation
include("transform/validation/errors.jl")
include("transform/validation/formula.jl")
include("transform/validation/macro.jl")
include("transform/validation/export_vars.jl")

# Metric transformation
include("transform/metrics/primitives.jl")
include("transform/metrics/custom.jl")

# Methodology transformation
include("transform/methodologies/common.jl")
include("transform/methodologies/regression.jl")
include("transform/methodologies/manual.jl")
include("transform/methodologies/mem_bandwidth.jl")
include("transform/methodologies/roofline.jl")

include("transform/prefix.jl")
include("transform/suffix.jl")

# EXECUTION PART

include("execution/variance.jl")
include("execution/structs.jl")
include("execution/testset.jl")

# Machine features extraction
include("execution/machine_topology.jl")
include("execution/machine_benchmarking.jl")

# Separate Macro definitions
include("execution/macros/perftest.jl")
include("execution/macros/perfcompare.jl")
include("execution/macros/roofline.jl")
include("execution/macros/regression.jl")
include("execution/macros/exec_ignore.jl")
include("execution/macros/customs.jl")
include("execution/macros/configuration.jl")
include("execution/macros/topology.jl")

# Rules of the ruleset
include("transform/parsing/hierarchy_transform.jl")
include("transform/parsing/target_transform.jl")
include("transform/parsing/formula_transform.jl")
include("transform/parsing/rules.jl")

# Additional
include("transform/auxiliar.jl")

# Functions used by the generated suites
include("execution/printing.jl")
include("execution/data_handling.jl")
include("execution/retrieve.jl")
include("execution/units.jl")
include("execution/misc.jl")

# Multithread suite launcher
include("execution/launch_suite.jl")

# Bencher Interface
include("bencher/BencherREST.jl")

# Base active rules
first_pass_rules = ASTRule[testset_macro_rule,
    test_macro_rule,
    test_throws_macro_rule,
    test_logs_macro_rule,
    inferred_macro_rule,
    test_deprecated_macro_rule,
    test_warn_macro_rule,
    test_nowarn_macro_rule,
    test_broken_macro_rule,
    test_skip_macro_rule,
    perftest_macro_rule,
    back_macro_rule,
    config_macro_rule,
    threads_macro_rule,
    on_perftest_exec_rule,
    on_perftest_ignore_rule,
    define_memory_throughput_rule,
    regression_macro_rule,
    define_metric_rule,
    define_benchmark_rule,
    export_vars_rule,
    auxiliary_metric_rule, roofline_macro_rule,
    manual_macro_rule,
    recursive_rule
]

second_pass_rules = ASTRule[
    prefix_macro_rule,
    suffix_macro_rule,
]


# Transform routines in target_transform.jl
perftest_expression_ruleset = [
    perftest_scope_assignment_macro_rule,
    perftest_scope_arg_macro_rule,
    perftest_scope_vecf_arg_macro_rule,
    perftest_scope_ref_rule,
    perftest_dot_interpolation_rule,
]

function parseTarget(expr::Expr, context::Context)::Expr
    return MacroTools.prewalk(ruleSet(context, perftest_expression_ruleset), expr)
end


"""
This method builds what is known as a rule set. Which is a function that will evaluate if an expression triggers a rule in a set and if that is the case apply the rule modifier. See the ASTRule documentation for more information.

WARNING: the rule set will apply the FIRST rule that matches with the expression, therefore other matches will be ignored

# Arguments
 - `context` the context structure of the tree run, it will be ocassinally used by some rules on the set.
 - `rules` the collection of rules that will belong to the resulting set.
"""
function ruleSet(context::Context, rules::Vector{ASTRule})
    function _ruleSet(x)
        for rule in rules
            if rule.match(x)
                info = rule.validation(x, context)
                return rule.transformation(x, context, info)
            end
        end
        return x
    end

    return _ruleSet
end


"""
This method gets a input julia expression, and a context register and executes a transformation of the input that converts a recipe script (input) into a fully-fledged testing suite (return value).

# Arguments
 - `input_expr` the recipe/source expression. (internally, a.k.a source code space)
 - `context` a register that will store information useful for the transformation over its run over the AST of the input

"""
function _treeRun(input_expr::Expr, context::Context, args...)

    first_pass = MacroTools.prewalk(ruleSet(context, first_pass_rules), input_expr)
    second_pass = MacroTools.prewalk(ruleSet(context, second_pass_rules), first_pass)
    return second_pass
end


ctx = nothing
function setupContext(path::AbstractString)

    global ctx = Context(GlobalContext(path, VecErrorCollection(), formula_symbols))
    ctx._global.original_file_path = path
end

"""
Load the configuration a top level transform starts from, and make it the current one: the configuration file,
overridden by `config` (e.g. the config argument of runperftests, `source` names it in the reported errors), overridden
by `overrides` (`overrides_source` names them). The configuration file is loaded, and its errors reported, once. A top
level transform never inherits the configuration of a previous one. Where each value comes from is recorded in
Configuration.SOURCES.
"""
function loadTransformConfig(config::Union{Dict,Nothing}, source::AbstractString, overrides::Dict = Dict{String,Any}(),
                             overrides_source::AbstractString = "the keyword arguments of runperftests")::Dict
    empty!(Configuration.PARENT_CONFIGS)
    empty!(Configuration.PARENT_SOURCES)
    if init_dummy_flag
        return Configuration.load_dummy_config()
    end

    loaded = Configuration.load_config()
    sources = copy(Configuration.SOURCES)
    if config !== nothing
        Configuration.report_unknown_entries(config, source)
        loaded = Configuration.merge_configs(loaded, config; source = source)
        Configuration.record_sources!(sources, config, source)
    end
    if !isempty(overrides)
        loaded = Configuration.merge_configs(loaded, overrides)
        Configuration.record_sources!(sources, overrides, overrides_source)
    end
    loaded = Configuration.load_config(loaded)
    merge!(Configuration.SOURCES, sources)
    return loaded
end

"""
This method implements the transformation that converts a recipe script into a fully-fledged testing suite.
The function will return a Julia expression with the resulting performance testing suite. This can be then executed or saved in a file for later usage.
# Arguments
 - `path` the path of the script to be transformed.

# Keyword arguments
 - `config` configuration parameters that override the configuration file, see runperftests.

"""
function treeRun(path::AbstractString; config::Union{Dict,Nothing}=nothing)
    return transformWith(path, config, "the config argument of PerfTest.transform")
end

"""
Transform the recipe at `path`, see `treeRun`. `source` names where `config` comes from in the reported errors,
`overrides` take priority over it (e.g. the verbose argument of runperftests, `overrides_source` names them).
"""
function transformWith(path::AbstractString, config::Union{Dict,Nothing}, source::AbstractString, overrides::Dict = Dict{String,Any}(),
                       overrides_source::AbstractString = "the keyword arguments of runperftests")

    # Set log directory
    setLogFolder()
    # Clear logs
    #clearLogs()
    # The configuration the transform starts from, a @perftest_config changes it from its place in the recipe onwards
    config = loadTransformConfig(config, source, overrides, overrides_source)
    initThreadSetting!()

    if config["general"]["verbose"] >= 1
        verboseOutput()
    end

    if config["MPI"]["enabled"] == true
        if isdefined(Main, :MPI)
            global mode = MPIMode
            addLog("general", "[MPI] MPI enabled in configuration and MPI package found, switching to MPI aware generation")
        else
            @warn "[MPI] MPI enabled in configuration but MPI package not found, defaulting to non-MPI mode"
        end
    else
        global mode = NormalMode
    end

    # The generated suite starts from this configuration, never from the one of the process that executes it. Except for
    # the [bencher] section, which the suite reads when it executes so the credentials are never written into it.
    # TODO: the display keys (general.verbose, general.plotting) are fixed at generation as well, a later update shall
    # let them be set when an already generated suite is executed
    initial_config = deepcopy(Configuration.CONFIG)
    delete!(initial_config, "bencher")
    initial_config = sprint(TOML.print, initial_config)

    # Load original
    input_expr = loadFileAsExpr(path)

    setupContext(path)

    Topology.setupLog(addLog, x -> throwParseError!("Invalid thread arrangement: $x", ctx))

    # Run through AST and build new expressions
    full = _treeRun(input_expr, ctx)

    # The thread setting the launcher will use, once every configuration call is known
    validateThreadSetting!(ctx)

    # Insert suffix
    #full = MacroTools.postwalk(ruleSet(ctx, [suffix_macro_rule]), full)

    # Mount inside a module environment
    module_full = Expr(:toplevel,
        Expr(:module, true, :__PERFTEST__,
            Expr(:block, :(import PerfTest), :(PerfTest._perftest_config($initial_config)),
                :(PerfTest.Configuration.load_bencher_config()), full.args...)))

    if num_errors(ctx) > 0
        printErrors(ctx)
        return quote
            @warn "Parsing failed"
        end
    end


    # The configuration in force at the end of the recipe, the included recipes give theirs back after them. Nothing is
    # saved if general.logs_enabled is false there
    if Configuration.CONFIG["general"]["verbose"] >= 2
        saveLogFolder(Configuration.CONFIG)
    end

    return rewrapDoBlockBodies(MacroTools.prettify(module_full))
end


"""
    runperftests(file; ...)

    # Description
        Simplified function to access the perftest transformation and subsequent execution of performance test suites.
        It takes a recipe script, transforms it into a performance testing suite and executes it. The resulting suite is also saved in a file for later usage.           

    # Arguments
        `file    ::AbstractString`: the path of the recipe script to be transformed

    # Keyword arguments
        `execute::Bool = true`             : whether the resulting suite should be executed right after generation, by default true. If false, the resulting suite will only be saved in a file with the name of the input with and added "_perfsuite.jl" suffix.
        `verbose::Union{Int,Nothing} = nothing` : level of verbosity, from 0 to 3 higher is more verbose. When given it overrides general.verbose of the config argument and of the configuration file, otherwise their value is used.
            0 : minimal output, only warnings and errors
            1 : general information about the transformation and execution process
            2 : detailed information about the transformation and execution process, logs are saved in a folder
            3 : debug level, very detailed information about the transformation and execution process
        `clean  ::Bool = false`            : whether to leave the config file, the output test suite and the test results or delete everything after the suite has been executed, !!! including previously done results and logs CAREFUL !!!.
        `config  ::Union{Dict{String,Any},Nothing} = nothing` : other configuration parameters to override the configuration file. Configuration priority: config macro > verbose argument > this argument > configuration file. See configuration for more info.
        `interpreter_flags::AbstractString = ""` : flags of the julia process that executes the suite, split at whitespace and passed in order (e.g. "-O3 -L setup.jl"), --check-bounds=no and --project=. unless they set them. They cannot set the number of threads (-t, --threads), which comes from the thread setting of the suite (general.numas and general.threads_per_numa, or a @perftest_threads), it is an error.
        `suite_flags::AbstractString = ""` : passed to the suite as a single argument, nothing if empty.


    # (!) Do not mistake this method for the perftest macro, which is used to set test targets inside the recipe script.

    # Example of a config parameter value:
        `{"regression" : {"enabled" : true}, "general" : {"recursive" : false}}`
    

    See the macro reference for more details about the recipe script format and the possible configurations.
"""
function runperftests(file::AbstractString; execute::Bool=true, verbose::Union{Int,Nothing}=nothing, clean::Bool=false, config::Union{Dict,Nothing}=nothing, interpreter_flags::AbstractString="", suite_flags::AbstractString="")
    # Only a verbose argument that is given overrides the configuration
    overrides = verbose === nothing ? Dict{String,Any}() : Dict{String,Any}("general" => Dict{String,Any}("verbose" => verbose))

    expr = transformWith(file, config, "the config argument of runperftests", overrides, "the verbose argument of runperftests")
    name = replace(file, r"\.jl$" => "_perfsuite.jl")
    saveExprAsFile(expr, name)
    if num_errors(ctx) == 0
        addLog("general", "[SUCCESS] Performance testing suite generated and saved in $name\n")
        if mode == MPIMode
            addLog("general", "[MPI] Performance testing suite generated in MPI mode, make sure to execute it with an MPI launcher to properly run the tests across all ranks")
        end
        if execute && mode == NormalMode
            addLog("general", "[PERFTEST] Executing performance testing suite $name")
            Launch.launchPerfTestSuite(name, interpreter_flags, suite_flags)
        end
    end
    if clean
        rm(name)
        rm("./perftest_config.toml")
        # Only created if the suite saved its results
        rm("./$(Configuration.CONFIG["general"]["save_folder"])", recursive=true, force=true)
        if ispath("./.perftest_logs")
            rm("./.perftest_logs", recursive=true)
        end
    end
end

"""
  [!] DEPRECATED, do not use, use the Perftest configuration attributes instead. 
"""
function toggleMPI()
    if mode == NormalMode
        global mode = MPIMode
    else
        global mode = NormalMode
    end
end

transform = treeRun

MPItransform(path) = (toggleMPI(); transform(path); toggleMPI())

init_dummy_flag::Bool = false

import PrecompileTools
PrecompileTools.@compile_workload begin
    try
        redirect_stdout(Base.DevNull()) do
            global init_dummy_flag = true
            x = PerfTest.transform(joinpath(dirname(pathof(PerfTest)), "transform/dummy.jl"))
        end
    catch err
    finally
        if ispath("./$(Configuration.PRECOMPILATION_CONFIG["general"]["save_folder"])")
            rm("./$(Configuration.PRECOMPILATION_CONFIG["general"]["save_folder"])", recursive=true)
        end
        global init_dummy_flag = false
        # Leave no state of the dummy transform in the package image
        Configuration.load_config(Configuration.DEFAULT)
        empty!(Configuration.PARENT_CONFIGS)
        empty!(Configuration.PARENT_SOURCES)
        empty!(THREAD_SETTING)
        global ctx = nothing
        global LOG_FOLDER = ""
        Topology.setupLog(Topology.defaultAddLog, Topology.defaultThrowParseError!)
    end
end

end
