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


"""
Complete a possibly partial configuration following a schema.

Args:
- config: Dictionary to complete, e.g. the contents of a configuration file
- base: Configuration that provides the missing entries
- schema: Dictionary defining expected structure and types

Returns:
- A new configuration dictionary that shares no data with `config` or `base`. Entries missing from `config`
  or with an incorrect type (reported as an error) take their value from `base`, entries outside the schema are kept.
"""
function fill_config(config::Dict, base::Dict = DEFAULT, schema::Dict = CONFIG_SHAPE)
    function fill_recursive(cfg, bc, sch, prefix)
        filled = Dict{String,Any}(key => deepcopy(value) for (key, value) in cfg if !haskey(sch, key))

        for (key, expected_type) in sch
            name = prefix * key
            if expected_type isa Dict
                section = get(cfg, key, Dict())
                if !isa(section, Dict)
                    @error "Expected a table for configuration section $name, got $(typeof(section)), using its default values"
                    section = Dict()
                end
                filled[key] = fill_recursive(section, bc[key], expected_type, name * ".")
            elseif !haskey(cfg, key)
                filled[key] = deepcopy(bc[key])
            elseif isa(cfg[key], expected_type)
                filled[key] = deepcopy(cfg[key])
            else
                @error "Incorrect type for configuration key $name. Expected $(expected_type), got $(typeof(cfg[key])), using the default value $(repr(bc[key]))"
                filled[key] = deepcopy(bc[key])
            end
        end
        return filled
    end

    return fill_recursive(config, base, schema, "")
end


"""
Recursively merge two configs, with values from override_config taking precedence.
"""
function merge_configs(base_config::Dict, override_config::Dict)

    function _mc(bc::Dict, oc::Dict)::Dict
        local merged = deepcopy(bc)

        for (key, value) in oc
            if value isa Dict && haskey(merged, key) && merged[key] isa Dict
                a = _mc(merged[key], value)
                merged[key] = a
            else
                merged[key] = deepcopy(value)
            end
        end

        return merged
    end

    merged = _mc(base_config, override_config)

    if validate_config(merged, CONFIG_SHAPE)
        return merged
    else
        @info "Malformed configuration added, ignoring"
        return deepcopy(base_config)
    end
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
  if it cannot be parsed it is left untouched and the default configuration is used.
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
        DEFAULT
    end

    return load_config(config)
end

"""
Make a copy of `config` the current configuration, missing or malformed entries take their default value.
"""
function load_config(config :: Dict)::Dict
    global CONFIG = fill_config(config)

    return CONFIG
end

function load_dummy_config()::Dict
    return load_config(PRECOMPILATION_CONFIG)
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

end # module


using TOML

function parseConfigurationMacro(_::ExtendedExpr, ctx::Context, info::Dict)::Expr

    raw = info[Symbol("")]
    interpolated = raw isa Expr && raw.head === :string

    # For an interpolated string, substitute each non-literal (interpolated)
    # fragment with "" so keys that don't depend on interpolation are still
    # resolvable now, and can affect the rest of this transform pass exactly
    # as they do today (e.g. regression.enabled gates code generation).
    preview = interpolated ? join(a isa AbstractString ? a : "" for a in raw.args) : raw

    parsed = TOML.parse(preview)

    old = Configuration.CONFIG

    Configuration.CONFIG = Configuration.merge_configs(Configuration.CONFIG, parsed)

    if Configuration.CONFIG["general"]["verbose"] != old["general"]["verbose"]
        addLog("general", "Verbosity level changed from $(old["general"]["verbose"]) to $(Configuration.CONFIG["general"]["verbose"])")
    end

    if interpolated
        # The real value (e.g. $(gethostname())) is only known once the
        # generated suite executes; splice the original expression so
        # PerfTest._perftest_config re-parses/merges it for real at that point.
        return quote
            begin
                PerfTest._perftest_config($(raw))
            end
        end
    end

    io = IOBuffer()
    TOML.print(nothing, io, Configuration.CONFIG)
    serialized_config = String(take!(io))

    return quote
        begin
            PerfTest._perftest_config($(serialized_config))
        end
    end
end

function parseThreadsMacro(_::ExtendedExpr, ctx::Context, info::Dict)::Expr
    try
        specs = info[Symbol("")]

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

    catch
        return quote
            "INVALID THREAD ARRANGEMENT"
        end
    end
end


"""
  Used on a generated test suite to import the configuration set during generation
"""
function _perftest_config(config_string::String)
    # Parse, and merge
    parsed = TOML.parse(config_string)

    Configuration.CONFIG = Configuration.merge_configs(Configuration.CONFIG, parsed)
end

