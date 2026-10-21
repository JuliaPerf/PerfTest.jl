module Launch

export launchPerfTestSuite

using ..PerfTest
using MacroTools
using TOML

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


"""
Thread setting (general.numas, general.threads_per_numa) of a generated suite, `nothing` for a key no configuration call sets.
A suite has a single thread setting regardless of recursivity: each key takes its value from the last configuration call
of the suite that sets it, even when that call comes from an included recipe. The first call of the suite holds the whole
configuration it was generated with. An interpolated value is only known once the suite executes, it is not considered.
"""
function retrieveConfigThreadSpecs(suite::Expr)
    specs = Dict{String,Any}("numas" => nothing, "threads_per_numa" => nothing)
    MacroTools.prewalk(suite) do x
        if @capture(x, PerfTest._perftest_config(serializedconfig_))
            try
                general = get(TOML.parse(PerfTest.interpolationPreview(serializedconfig)), "general", Dict())
                for key in keys(specs)
                    if haskey(general, key) && !PerfTest.isInterpolated(general[key])
                        specs[key] = general[key]
                    end
                end
            catch e
                @error("Generated suite configuration is malformed TOML error: $e")
            end
        end
        return x
    end
    return specs["numas"], specs["threads_per_numa"]
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
        # One thread setting per suite, see retrieveConfigThreadSpecs
        # TODO: apply it, the values of these keys still need a conversion to an arrangement (e.g. their default "single")
        specs = retrieveConfigThreadSpecs(suite)
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