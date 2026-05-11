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

abstract type Mode end
struct MPIMode <: Mode end
struct NormalMode <: Mode end

mode = NormalMode

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
include("transform/parsing/hierarchy_transform_test_region.jl")
include("transform/parsing/hierarchy_transform_benchmark_region.jl")
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
This method implements the transformation that converts a recipe script into a fully-fledged testing suite.
The function will return a Julia expression with the resulting performance testing suite. This can be then executed or saved in a file for later usage.
# Arguments
 - `path` the path of the script to be transformed.

"""
function treeRun(path::AbstractString; config=nothing)

    # Set log directory
    setLogFolder()
    # Clear logs
    #clearLogs()
    # Load configuration
    if init_dummy_flag
        config = Configuration.load_dummy_config()
    else
        if config === nothing
            config = Configuration.load_config()
        else
            _config = Configuration.load_config()
            config = Configuration.merge_configs(_config, config)
            Configuration.load_config(config)
        end
    end

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

    # Load original
    input_expr = loadFileAsExpr(path)

    setupContext(path)

    Topology.setupLog(addLog, x -> throwParseError!(x, ctx))

    # Run through AST and build new expressions
    full = _treeRun(input_expr, ctx)

    # Insert suffix
    #full = MacroTools.postwalk(ruleSet(ctx, [suffix_macro_rule]), full)

    # Mount inside a module environment
    module_full = Expr(:toplevel,
        Expr(:module, true, :__PERFTEST__,
            Expr(:block, full.args...)))

    if num_errors(ctx) > 0
        printErrors(ctx)
        return quote
            @warn "Parsing failed"
        end
    end


    if config["general"]["verbose"] >= 2
        saveLogFolder()
    end

    return MacroTools.prettify(module_full)
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
        `verbose::Int  = 0`                : level of verbosity, from 0 to 3 higher is more verbose
            0 : minimal output, only warnings and errors
            1 : general information about the transformation and execution process
            2 : detailed information about the transformation and execution process, logs are saved in a folder
            3 : debug level, very detailed information about the transformation and execution process
        `clean  ::Bool = false`            : whether to leave the config file, the output test suite and the test results or delete everything after the suite has been executed, !!! including previously done results and logs CAREFUL !!!.
        `config  ::Dict{String,Any} = {}`   : other configuration parameters to override the configuration file. Configuration priority: config macro > this argument > configuration file. See configuration for more info.
    

    # (!) Do not mistake this method for the macro with the same name, which is used to set test targets inside the recipe script.

    # Example of a config parameter value:
        `{"regression" : {"enabled" : true}, "general" : {"recursive" : false}}`
    

    See the macro reference for more details about the recipe script format and the possible configurations.
"""
function runperftests(file::AbstractString; execute::Bool=true, verbose::Int=0, clean::Bool=false, config::Union{Dict,Nothing}=nothing)
    # Load config file
    Configuration.load_config()
    # Override with config argument
    if config isa Dict
        config = Configuration.merge_configs(Configuration.CONFIG, config)
    else
        config = Configuration.CONFIG
    end
    # Override with parameters
    configp = Dict{String,Any}()
    configp["general"] = Dict{String,Any}()
    if config["general"]["verbose"] != verbose
        configp["general"]["verbose"] = verbose
    end
    config = Configuration.merge_configs(config, configp)

    expr = treeRun(file, config=config)
    name = replace(file, r"\.jl$" => "_perfsuite.jl")
    saveExprAsFile(expr, name)
    if num_errors(ctx) == 0
        addLog("general", "[SUCCESS] Performance testing suite generated and saved in $name\n")
        if mode == MPIMode
            addLog("general", "[MPI] Performance testing suite generated in MPI mode, make sure to execute it with an MPI launcher to properly run the tests across all ranks")
        end
        if execute && mode == NormalMode
            addLog("general", "[PERFTEST] Executing performance testing suite $name")
            Main.include(name)
        end
    end
    if clean
        rm(name)
        rm("./perftest_config.toml")
        rm("./$(Configuration.CONFIG["general"]["save_folder"])", recursive=true)
        if ispath("./.perftest_logs")
            rm("./perftest_logs", recursive=true)
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
    end
end

end
