module Launch

export launchPerfTestSuite

using ..PerfTest
using MacroTools

DEFAULT_INTERPRETER_FLAGS = Dict{String,String}(
    "--check-bounds" => "no",
    "--project" => "."
)

function parseFlags(flagstring::AbstractString, default::Dict{String,String})
    flags = copy(default)
    for token in split(flagstring)
        key, _, val = partition(token, '=')
        flags[key] = val
    end
    return flags
end

function printFlags(flags::Dict{String,String}, separate :: Bool = false) ::Union{String, Vector}
    flags =[isempty(v) ? k : "$k=$v" for (k, v) in flags]
    return separate ? flags : join(flags, " ")
end

# Small helper since Julia's `split` on '=' with limit=2 needs unpacking care
function partition(s::AbstractString, c::Char)
    parts = split(s, c, limit=2)
    return length(parts) == 1 ? (parts[1], "", "") : (parts[1], string(c), parts[2])
end


function retrieveThreadConfig(path::AbstractString)
    suite = PerfTest.loadFileAsExpr(path)

    # Extract the thread specifications
    specs = nothing
    stop = false
    MacroTools.prewalk((x -> @capture(x, specs = thr_) ? (specs = thr; stop = true; nothing) : (stop ? nothing : x)), suite)

    defthrpernuma = 1
    defnumas = 1

    thr_config = (1, 1)
    if specs isa Nothing
        # Extract the configuration string
        config_string = ""
        MacroTools.prewalk((x -> @capture(x, PerfTest._perftest_config(serializedconfig_)) ? (config_string = serializedconfig; nothing) : x), suite)

        # Parse configuration TOML
        config_dict = nothing
        try
            config_dict = TOML.parse(config_string)

            # Access thread spec fields
            specs = [config_dict["general"]["numas"], config_dict["general"]["threads_per_numa"]]
        catch e
            @error("Generated suite configuration is malformed TOML error: $e")
        end
    else
        thr_config = eval(specs)
    end
    # Parse thread specifications

    return PerfTest.Topology.literallizeArrangement(thr_config)
end

"""
    Runs the julia interpreter to execute a performance test suite, setting up adequately (e.g. thread number, flags)
"""
function launchPerfTestSuite(path::AbstractString, interpreter_flags::AbstractString="", suite_flags::AbstractString="")
    # Retrieve current interpreter
    exename = joinpath(Sys.BINDIR, Base.julia_exename())
    # Convert to absolute path
    _abspath = abspath(path)
    # Check flags
    parsed_flags = parseFlags(interpreter_flags, DEFAULT_INTERPRETER_FLAGS)
    # Check thread configurations
    configurations = retrieveThreadConfig(path)
    threads_needed = configurations[1] * configurations[2]
    # Add thread argument
    if !haskey(parsed_flags, "-t") && !haskey(parsed_flags, "--threads")
        parsed_flags["--threads"] = "$threads_needed"
    else
        error("Thread should be set automatically to $threads_needed treads.")
    end
    interpreter_flags = printFlags(parsed_flags, true)
    # Spawn process
    run(`$exename $(arg for arg in interpreter_flags) $_abspath $suite_flags`)
end

end