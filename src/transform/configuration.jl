module Configuration

using Base: DEFAULT_STABLE
using TOML
"""
Validate configuration against a predefined schema.

Args:
- config: Dictionary to validate
- schema: Dictionary defining expected structure and types

Returns:
- Boolean indicating whether configuration is valid
"""
function validate_config(config::Dict, schema::Dict)
    function validate_recursive(cfg, sch)
        for (key, expected_type) in sch
            if !haskey(cfg, key)
                @warn "Missing configuration key: $key"
                return false
            end

            if expected_type isa Dict
                if !isa(cfg[key], Dict)
                    @warn "Expected nested dictionary for $key"
                    return false
                end
                if !validate_recursive(cfg[key], expected_type)
                    return false
                end
            else
                if !isa(cfg[key], expected_type)
                    @warn "Incorrect type for $key. Expected $(expected_type), got $(typeof(cfg[key]))"
                    return false
                end
            end
        end
        return true
    end

    return validate_recursive(config, schema)
end


# Names where an entry comes from in the reported errors, e.g. " in the configuration file perftest_config.toml"
in_source(source::AbstractString) = isempty(source) ? "" : " in $source"

"""
Complete a possibly partial configuration following a schema.

Args:
- config: Dictionary to complete, e.g. the contents of a configuration file
- base: Configuration that provides the missing entries
- schema: Dictionary defining expected structure and types
- source: Where `config` comes from (e.g. "the configuration file perftest_config.toml"), named in the reported errors

Returns:
- A new configuration dictionary that shares no data with `config` or `base`. Entries missing from `config`
  or with an incorrect type (reported as an error) take their value from `base`, entries outside the schema are kept.
"""
function fill_config(config::Dict, base::Dict = DEFAULT, schema::Dict = CONFIG_SHAPE; source::AbstractString = "")
    at = in_source(source)

    function fill_recursive(cfg, bc, sch, prefix)
        filled = Dict{String,Any}(key => deepcopy(value) for (key, value) in cfg if !haskey(sch, key))

        for (key, expected_type) in sch
            name = prefix * key
            if expected_type isa Dict
                section = get(cfg, key, Dict())
                if !isa(section, Dict)
                    @error "Expected a table for configuration section $name$at, got $(typeof(section)), using its default values"
                    section = Dict()
                end
                filled[key] = fill_recursive(section, bc[key], expected_type, name * ".")
            elseif !haskey(cfg, key)
                filled[key] = deepcopy(bc[key])
            elseif isa(cfg[key], expected_type)
                filled[key] = deepcopy(cfg[key])
            else
                @error "Incorrect type for configuration key $name$at. Expected $(expected_type), got $(typeof(cfg[key])), using the default value $(repr(bc[key]))"
                filled[key] = deepcopy(bc[key])
            end
        end
        return filled
    end

    return fill_recursive(config, base, schema, "")
end


"""
Describe an entry of a configuration that is not in the schema, e.g. a misspelled key.

Args:
- key: Name of the entry in its table
- value: Value of the entry
- prefix: Full name of its table followed by a dot, empty at the top level
- schema: Schema of its table

Returns:
- Its kind and full name, e.g. "key general.verbse" or "section genral", and the entries its table can have,
  e.g. "The keys of section general are: autoflops, ..."
"""
function describe_unknown(key, value, prefix::AbstractString, schema::Dict)::Tuple{String,String}
    name = prefix * string(key)
    valid = join(sort!(string.(collect(keys(schema)))), ", ")

    if prefix != ""
        return "key $name", "The keys of section $(chop(prefix)) are: $valid"
    elseif value isa Dict
        return "section $name", "The sections are: $valid"
    else
        # Every key belongs to a section, e.g. general.verbose
        return "key $name outside of any section", "The sections are: $valid"
    end
end

"""
Find the entries of a possibly partial configuration that are not in a schema, described as in `describe_unknown`.
The contents of an unknown section are not looked into.
"""
function unknown_entries(config::Dict, schema::Dict = CONFIG_SHAPE, prefix::String = "")::Vector{Tuple{String,String}}
    found = Tuple{String,String}[]
    for key in sort!(collect(keys(config)); by=string)
        if !haskey(schema, key)
            push!(found, describe_unknown(key, config[key], prefix, schema))
        elseif schema[key] isa Dict && config[key] isa Dict
            append!(found, unknown_entries(config[key], schema[key], prefix * string(key) * "."))
        end
    end
    return found
end

"""
Report as errors the entries of a configuration read from `source` (e.g. "the configuration file perftest_config.toml")
that are not in the schema. They are ignored, the rest of the configuration still applies.
"""
function report_unknown_entries(config::Dict, source::AbstractString, schema::Dict = CONFIG_SHAPE)
    for (entry, valid) in unknown_entries(config, schema)
        @error "Unknown configuration $entry in $source, ignoring it. $valid"
    end
end


"""
Recursively merge two configs, with values from override_config taking precedence.

Each entry of override_config is checked against the schema on its own: one with an incorrect type is reported as an
error, naming `source` (where override_config comes from) if given, and ignored, the rest still apply. Entries outside
the schema are kept as they are.

Returns:
- A new configuration dictionary that shares no data with `base_config` or `override_config`
"""
function merge_configs(base_config::Dict, override_config::Dict, schema::Dict = CONFIG_SHAPE; source::AbstractString = "")
    at = in_source(source)

    function _mc(bc::Dict, oc::Dict, sch, prefix)::Dict
        local merged = deepcopy(bc)

        for (key, value) in oc
            name = prefix * string(key)
            # nothing for an entry outside the schema
            expected = sch isa Dict ? get(sch, key, nothing) : nothing

            if expected === nothing
                if value isa Dict && haskey(merged, key) && merged[key] isa Dict
                    merged[key] = _mc(merged[key], value, nothing, name * ".")
                else
                    merged[key] = deepcopy(value)
                end
            elseif expected isa Dict
                if value isa Dict
                    section = get(merged, key, nothing)
                    merged[key] = _mc(section isa Dict ? section : Dict{String,Any}(), value, expected, name * ".")
                else
                    @error "Expected a table for configuration section $name$at, got $(typeof(value)), ignoring it"
                end
            elseif value isa expected
                merged[key] = deepcopy(value)
            else
                @error "Incorrect type for configuration key $name$at. Expected $(expected), got $(typeof(value)), ignoring it"
            end
        end

        return merged
    end

    return _mc(base_config, override_config, schema, "")
end


"""
Save configuration to a TOML file.

Args:
- config: Configuration dictionary
- filepath: Path to save the TOML file
- schema: Optional schema for validation

Returns:
- Boolean indicating successful save
"""
function save_config(config::Dict, filepath::AbstractString = CONFIG_FILE)
    if !validate_config(config, CONFIG_SHAPE)
        @error "Configuration validation failed"
        return false
    end

    try
        open(filepath, "w") do io
            TOML.print(io, config)
        end
        return true
    catch e
        @error "Error saving configuration: $e"
        return false
    end
end

"""
Load configuration from a TOML file over the default configuration, and make it the current one.

Args:
- filepath: Path to the TOML file, CONFIG_FILE in the working directory if empty

Returns:
- Loaded configuration dictionary. If the file does not exist it is created with the default configuration,
  if it cannot be parsed it is left untouched and the default configuration is used. Its entries that are not in the
  schema are reported as errors and ignored, the rest of the file still applies.
"""
function load_config(filepath::AbstractString = "")::Dict
    path = filepath == "" ? CONFIG_FILE : filepath

    if !ispath(path)
        @info "Configuration not found, saving the default configuration in $path"
        save_config(DEFAULT, path)
        return load_config(DEFAULT)
    end

    config = try
        TOML.parsefile(path)
    catch e
        # Never overwrite a file written by the user, even a broken one
        @error "Configuration file $path could not be parsed, it has been left untouched and the default configuration will be used" exception = e
        return load_config(DEFAULT)
    end

    source = "the configuration file $path"
    report_unknown_entries(config, source)

    return load_config(config; source = source)
end

"""
Make a copy of `config` the current configuration, missing or malformed entries take their default value. `source` is
where `config` comes from, named in the reported errors and recorded in SOURCES for the entries that apply.
"""
function load_config(config :: Dict; source::AbstractString = "")::Dict
    global CONFIG = fill_config(config; source = source)
    empty!(SOURCES)
    isempty(source) || record_sources!(SOURCES, config, source)

    return CONFIG
end

function load_dummy_config()::Dict
    return load_config(PRECOMPILATION_CONFIG)
end

"""
Where the value in force of a configuration key comes from (e.g. "the configuration file perftest_config.toml"), by its
full name (e.g. "regression.default_threshold"), see SOURCES.
"""
source_of(name::AbstractString)::String = get(SOURCES, name, "the default configuration")

"""
Record `source` in `sources` (see SOURCES) as where the entries of `config` come from, the ones that apply when it is
loaded or merged: those in the schema with the expected type.
"""
function record_sources!(sources::Dict, config::Dict, source::AbstractString, schema::Dict = CONFIG_SHAPE, prefix::String = "")
    for (key, value) in config
        name = prefix * string(key)
        expected = get(schema, key, nothing)
        if expected isa Dict
            value isa Dict && record_sources!(sources, value, source, expected, name * ".")
        elseif expected !== nothing && value isa expected
            sources[name] = source
        end
    end
    return sources
end

"""
Save a copy of the current configuration, so it can be changed (e.g. by an included recipe) and later restored by `pop_config`.
"""
function push_config()
    push!(PARENT_CONFIGS, deepcopy(CONFIG))
    push!(PARENT_SOURCES, copy(SOURCES))
    return nothing
end

"""
Restore the configuration saved by the last `push_config`.
"""
function pop_config()
    global CONFIG = pop!(PARENT_CONFIGS)
    # Empty when the stack was filled by other means
    isempty(PARENT_SOURCES) || (global SOURCES = pop!(PARENT_SOURCES))
    return nothing
end

"""
Set the [bencher] section of the current configuration from the configuration file, used by the generated suites when
they start executing so the Bencher credentials (e.g. api_key) are never written into them. Unlike `load_config`,
a missing file is not created, the default values are used instead.
"""
function load_bencher_config(filepath::AbstractString = CONFIG_FILE)
    file = Dict()
    if isfile(filepath)
        try
            file = TOML.parsefile(filepath)
        catch e
            @error "Configuration file $filepath could not be parsed, the default [bencher] configuration will be used" exception = e
        end
    end

    source = "the configuration file $filepath"
    section = Dict("bencher" => CONFIG_SHAPE["bencher"])
    bencher = Dict("bencher" => get(file, "bencher", Dict()))
    report_unknown_entries(bencher, source, section)
    CONFIG["bencher"] = fill_config(bencher, DEFAULT, section; source = source)["bencher"]
    return nothing
end

CONFIG_FILE = "perftest_config.toml"


CONFIG_SHAPE = Dict(
    "general" => Dict(
        "autoflops" => Bool,
        "numas" => Union{String,Integer,Float64},
        "threads_per_numa" => Union{String,Integer,Float64},
        "save_results" => Bool,
        "logs_enabled" => Bool,
        "save_folder" => String,
        "max_saved_results" => Int,
        "plotting" => Bool,
        "verbose" => Int,
        "recursive" => Bool,
        "safe_formulas" => Bool,
        "suppress_output" => Bool),
    "regression" => Dict(
        "enabled" => Bool,
        "dedicated_reference_file" => String,
        "default_threshold" => Number,
        "use_bencher" => Bool,
    ),
    "roofline" => Dict(
        "enabled" => Bool,
        "default_threshold" => Number,
    ),
    "memory_bandwidth" => Dict(
        "enabled" => Bool,
        "default_threshold" => Number,
    ),
    "perfcompare" => Dict(
        "enabled" => Bool,
    ),
    "machine_benchmarking" => Dict(
        "memory_bandwidth_test_buffer_size" => Int
    ),
    "MPI" => Dict(
        "enabled" => Bool,
        "mode" => String
    ),
    "bencher" => Dict(
        "api_key" => String,
        "api_url" => String,
        "project_name" => String,
        "organization" => String,
        "custom_testbed_name" => String
    )
)

DEFAULT = Dict(
    "general" => Dict(
        "autoflops" => false,
        "numas" => "single",
        "threads_per_numa" => "single",
        "save_results" => true,
        "logs_enabled" => true,
        "save_folder" => ".perftests",
        "max_saved_results" => 20,
        "plotting" => true,
        "verbose" => 0,
        "recursive" => true,
        "suppress_output" => true,
        "safe_formulas" => false,
    ),
    "regression" => Dict(
        "enabled" => true,
        "dedicated_reference_file" => "",
        "default_threshold" => 1.1,
        "use_bencher" => false,
    ),
    "roofline" => Dict(
        "enabled" => true,
        "default_threshold" => 0.5,
    ),
    "memory_bandwidth" => Dict(
        "enabled" => true,
        "default_threshold" => 0.5,
    ),
    "perfcompare" => Dict(
        "enabled" => true,
    ),
    "machine_benchmarking" => Dict(
        "memory_bandwidth_test_buffer_size" => 0
    ),
    "MPI" => Dict(
        "enabled" => false,
        "mode" => "reduce"
    ),
    "bencher" => Dict(
        "api_key" => "",
        "api_url" => "https://api.bencher.dev",
        "project_name" => "",
        "organization" => "",
        "custom_testbed_name" => ""
    )
)

PRECOMPILATION_CONFIG = Dict(
    "general" => Dict(
        "autoflops" => false,
        "numas" => 1,
        "threads_per_numa" => 1,
        "save_results" => false,
        "logs_enabled" => false,
        "save_folder" => ".thisshouldnotexist",
        "max_saved_results" => 0,
        "plotting" => true,
        "verbose" => 0,
        "recursive" => false,
        "suppress_output" => true,
        "safe_formulas" => false,
    ),
    "regression" => Dict(
        "enabled" => false,
        "dedicated_reference_file" => "",
        "default_threshold" => 0.9,
        "use_bencher" => false,
    ),
    "roofline" => Dict(
        "enabled" => true,
        "default_threshold" => 0.5,
    ),
    "memory_bandwidth" => Dict(
        "enabled" => true,
        "default_threshold" => 0.5,
    ),
    "perfcompare" => Dict(
        "enabled" => true,
    ),
    "machine_benchmarking" => Dict(
        "memory_bandwidth_test_buffer_size" => 0
    ),
    "MPI" => Dict(
        "enabled" => false,
        "mode" => "reduce"
    ),
    "bencher" => Dict(
        "api_key" => "",
        "api_url" => "https://api.bencher.dev",
        "project_name" => "",
        "organization" => "",
        "custom_testbed_name" => ""
    )
)

PARENT_CONFIGS = Dict[]
CONFIG = deepcopy(DEFAULT)

# Where the value of each key of CONFIG comes from, by its full name (e.g. "regression.default_threshold" =>
# "the configuration file perftest_config.toml"), named in the errors about that value. A key that is not in it has its
# default value. It follows CONFIG during a transform: `load_config` and the transform set it, `push_config` and
# `pop_config` save and restore it along with CONFIG.
SOURCES = Dict{String,String}()
PARENT_SOURCES = Dict{String,String}[]

end # module


using TOML

# Stands for the interpolated fragments of a @perftest_config string during the transform. It is a valid TOML bare key,
# so interpolation in a key or a table name is reported as such instead of as invalid TOML
INTERPOLATION_MARKER = "__PERFTEST_INTERPOLATION__"

isInterpolated(value) = value isa AbstractString ? occursin(INTERPOLATION_MARKER, value) :
                        value isa AbstractVector ? any(isInterpolated, value) :
                        value isa AbstractDict ? any(isInterpolated, keys(value)) || any(isInterpolated, values(value)) :
                        false

# TOML of a @perftest_config string before the suite executes, its interpolated fragments are replaced by the marker
interpolationPreview(raw) = raw isa Expr && raw.head === :string ?
                            join(a isa AbstractString ? a : INTERPOLATION_MARKER for a in raw.args) : raw

# Names the @perftest_config being transformed in its parse errors
configurationMacroSource(ctx::Context) = "the @perftest_config of recipe $(ctx._global.original_file_path)"

# Configuration keys whose value is used before the recipe is read, so a @perftest_config cannot set them, by their full
# name along with what decides with them
PRE_RECIPE_KEYS = Dict("MPI.enabled" => "the MPI mode")

"""
Check `config`, parsed from a @perftest_config string, against the configuration schema. Each entry that is not in it
(along with the entries its table can have), that has an incorrect type, or that is used before the recipe is read
(see PRE_RECIPE_KEYS) is reported as a parse error and removed, so the rest still applies to the transform. The keys
whose value is interpolated are removed as well, they take their value when the suite is executed. Interpolation in a
key or a table name is reported as a parse error, in which case it returns false.
"""
function validateConfigurationMacro!(config::Dict, ctx::Context, schema::Dict = Configuration.CONFIG_SHAPE, prefix::String = "")::Bool
    source = configurationMacroSource(ctx)
    # Sorted so the errors are reported in a stable order
    for key in sort!(collect(keys(config)))
        name = prefix * key
        value = config[key]
        if occursin(INTERPOLATION_MARKER, key)
            throwParseError!("Interpolation in $source is only supported inside string values, found in the key or table name $(replace(name, INTERPOLATION_MARKER => "\$(...)"))", ctx)
            return false
        elseif !haskey(schema, key)
            entry, valid = Configuration.describe_unknown(key, value, prefix, schema)
            throwParseError!("Unknown configuration $entry in $source. $valid", ctx)
            delete!(config, key)
        elseif schema[key] isa Dict
            if value isa Dict
                validateConfigurationMacro!(value, ctx, schema[key], name * ".") || return false
            else
                throwParseError!("Expected a table for configuration section $name in $source, got $(typeof(value))", ctx)
                delete!(config, key)
            end
        elseif haskey(PRE_RECIPE_KEYS, name)
            throwParseError!("Configuration key $name cannot be set in $source: $(PRE_RECIPE_KEYS[name]) is decided with it " *
                             "before the recipe is read, so it would not apply. Set it in the configuration file " *
                             "$(Configuration.CONFIG_FILE) or with the config argument of runperftests or PerfTest.transform", ctx)
            delete!(config, key)
        elseif !isa(value, schema[key])
            # Interpolation is only supported inside string values, so an interpolated value is always a string, known
            # to have the wrong type here already
            given = isInterpolated(value) ? "an interpolated $(typeof(value)) (interpolation is only supported inside string values)" : typeof(value)
            throwParseError!("Incorrect type for configuration key $name in $source. Expected $(schema[key]), got $given", ctx)
            delete!(config, key)
        elseif isInterpolated(value)
            delete!(config, key)
            addLog("general", "Configuration key $name is interpolated, it will take its value when the suite is executed")
        end
    end
    return true
end

function parseConfigurationMacro(_::ExtendedExpr, ctx::Context, info::Union{Dict,Nothing})::Expr

    # Its validation already reported a missing argument or one that is not a string literal, e.g. a variable, whose
    # value is unknown during the transform
    if info === nothing || !haskey(info, Symbol(""))
        return quote end
    end

    raw = info[Symbol("")]
    interpolated = raw isa Expr && raw.head === :string

    # The interpolated fragments (e.g. $(gethostname())) are only known once the generated suite executes, the keys
    # that depend on them are left out of this transform pass. The other keys affect it as without interpolation
    # (e.g. regression.enabled gates code generation).
    preview = interpolationPreview(raw)

    parsed = try
        TOML.parse(preview)
    catch e
        e isa TOML.ParserError || rethrow()
        message = replace(sprint(showerror, e), INTERPOLATION_MARKER => "\$(...)")
        throwParseError!("Invalid TOML in $(configurationMacroSource(ctx))$(interpolated ? " (interpolation is only supported inside string values)" : ""): $message", ctx)
        return quote end
    end

    if !validateConfigurationMacro!(parsed, ctx)
        return quote end
    end

    old = Configuration.CONFIG

    Configuration.CONFIG = Configuration.merge_configs(Configuration.CONFIG, parsed)
    Configuration.record_sources!(Configuration.SOURCES, parsed, configurationMacroSource(ctx))
    recordThreadSetting!(parsed, configurationMacroSource(ctx))

    if Configuration.CONFIG["general"]["verbose"] != old["general"]["verbose"]
        addLog("general", "Verbosity level changed from $(old["general"]["verbose"]) to $(Configuration.CONFIG["general"]["verbose"])")
    end

    # The generated suite makes the same change at this same point, over the configuration it was generated with
    # (see treeRun), the interpolated keys take their real value there
    return quote
        begin
            PerfTest._perftest_config($(raw))
        end
    end
end

# The configuration keys, of section general, of the thread setting of a suite
THREAD_KEYS = ("numas", "threads_per_numa")

"""
Thread setting of the suite being generated, the one its launcher uses (see Launch.retrieveConfigThreadSpecs): for each
of THREAD_KEYS its value, where it comes from, and whether a recipe sets it. A suite has a single thread setting
regardless of recursivity, each key takes its value from the last configuration call that sets it, even in an included
recipe. As for the launcher, an interpolated value is not considered, it is only known once the suite executes.
"""
THREAD_SETTING = Dict{String,Tuple{Any,String,Bool}}()

# Start the thread setting of a transform from the configuration it starts from
function initThreadSetting!()
    empty!(THREAD_SETTING)
    for key in THREAD_KEYS
        THREAD_SETTING[key] = (Configuration.CONFIG["general"][key], Configuration.source_of("general.$key"), false)
    end
end

# Record the thread keys set by a @perftest_config of a recipe, `parsed` once validated (see validateConfigurationMacro!)
# so without its interpolated keys
function recordThreadSetting!(parsed::Dict, source::AbstractString)
    general = get(parsed, "general", nothing)
    general isa Dict || return
    for key in THREAD_KEYS
        haskey(general, key) && (THREAD_SETTING[key] = (general[key], source, true))
    end
end

"""
Check the thread setting of the suite being generated (see THREAD_SETTING), whether or not a @perftest_threads takes
priority over it. An invalid one (see Topology.arrangementFromConfig) is reported naming where each key comes from: as a
parse error when a recipe sets one of them, otherwise, as the other errors of the configuration file and of the config
argument, as an error that does not stop the transform. The launcher reports it again, as it cannot launch the suite.
"""
function validateThreadSetting!(ctx::Context)
    setting = [(key, THREAD_SETTING[key]...) for key in THREAD_KEYS]
    problems = Topology.arrangementFromConfig((value for (_, value, _, _) in setting)...)
    problems isa Vector{String} || return

    values = join(["general.$key = $(repr(value)) (from $source)" for (key, value, source, _) in setting], " and ")
    message = "Invalid thread setting of the generated suite, $values: $(join(problems, ", ")). " *
              "$(Topology.THREAD_SETTING_RULE) $(Topology.CONFIG_THREADS_OPTIONS)"
    if any(from_recipe for (_, _, _, from_recipe) in setting)
        throwParseError!(message, ctx)
    else
        @error message
    end
end

# Names the @perftest_threads being transformed in its parse errors
threadsMacroSource(ctx::Context) = "the @perftest_threads of recipe $(ctx._global.original_file_path)"

function parseThreadsMacro(_::ExtendedExpr, ctx::Context, info::Union{Dict,Nothing})::Expr

    # Its validation already reported a missing argument, more than one, or a keyword one
    if info === nothing || !haskey(info, Symbol(""))
        return quote end
    end

    specs = info[Symbol("")]
    source = threadsMacroSource(ctx)
    report(reason) = throwParseError!("Invalid thread arrangement in $source: $reason $THREADS_OPTIONS", ctx)
    if !validateThreadsArgument(specs, report)
        return quote end
    end

    return quote
        let
            specs = $specs
            arrgmt_l = PerfTest.Topology.literallizeArrangement($specs)
            arrgmt_e = PerfTest.Topology.isExecutableArrangement(arrgmt_l)
            if arrgmt_e === nothing
                @warn "Ignoring pinning."
            else
                try
                    PerfTest.Topology.enforceThreadArrangement(arrgmt_e)
                catch e
                    if Sys.iswindows() || Sys.isapple()
                        @warn "Thread pinning is not supported on this OS. Ignoring specified arrangement."
                    else
                        @warn "Failed to enforce thread pinning: $e, ignoring specified arrangement."
                    end
                end
            end
        end
    end
end


"""
  Used on a generated test suite to make, while it executes, the configuration changes made during its generation:
  the whole configuration it was generated with at its beginning, then each `@perftest_config` where it appears.
  An entry with an incorrect type, which the transform reports as a parse error so only a suite generated by a different
  version of the package can have, is reported as an error and ignored, the rest still apply (see merge_configs)
"""
function _perftest_config(config_string::String)
    # Parse, and merge
    parsed = TOML.parse(config_string)

    Configuration.CONFIG = Configuration.merge_configs(Configuration.CONFIG, parsed; source = "a configuration call of the executing suite")
end

