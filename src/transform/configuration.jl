module Configuration


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
Recursively merge two dictionaries, with values from override_dict taking precedence.
"""
function merge_configs(base_config::Dict, override_config::Dict)
    merged = deepcopy(base_config)

    for (key, value) in override_config
        if value isa Dict && haskey(merged, key) && merged[key] isa Dict
            merged[key] = merge_configs(merged[key], value)
        else
            merged[key] = value
        end
    end

    if validate_config(merged, CONFIG_SHAPE)
        return merged
    else
        @info "Malformed configuration added, ignoring"
        return base_config
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
function save_config(config::Dict)
    if !validate_config(config, CONFIG_SHAPE)
        @error "Configuration validation failed"
        return false
    end

    try
        open(CONFIG_FILE, "w") do io
            TOML.print(io, config)
        end
        return true
    catch e
        @error "Error saving configuration: $e"
        return false
    end
end

"""
Load configuration from a TOML file.

Args:
- filepath: Path to the TOML file
- schema: Optional schema for validation

Returns:
- Loaded configuration dictionary or nothing
"""
function load_config() :: Dict
    try
        config = TOML.parsefile(CONFIG_FILE)

        if !validate_config(config, CONFIG_SHAPE)
            @error "Configuration validation failed"
            return nothing
        end

        return config
    catch e
        @info "Configuration not found, loading default configuration"
        save_config(DEFAULT)
        return DEFAULT
    end
end

CONFIG_FILE = "perftest_config.toml"

CONFIG_SHAPE = Dict(
    "general" => Dict(
        "autoflops" => Bool,
        "save_results" => Bool,
        "logs_enabled" => Bool,
        "save_folder" => String,
        "max_saved_results" => Int,
        "plotting" => Bool,
        "verbose" => Bool,
        "recursive" => Bool,
        "safe_formulas" => Bool,
        "suppress_output" => Bool),
    "regression" => Dict(
        "enabled" => Bool,
        "regression_threshold" => Number
    ),
    "roofline" => Dict(
        "enabled" => Bool,
        "default_threshold" => Number,
    ),
    "memory_bandwidth" => Dict(
        "enabled" => Bool,
        "default_threshold" => Number,
    ),
    "raw_test" => Dict(),
    "machine_benchmarking" => Dict(
        "memory_bandwidth_test_buffer_size" => Union{Bool, Int}
    ),
    "MPI" => Dict(
        "enabled" => Bool,
        "mode" => String
    ),
)

DEFAULT = Dict(
    "general" => Dict(
        "autoflops" => true,
        "save_results" => true,
        "logs_enabled" => true,
        "save_folder" => ".perftests",
        "max_saved_results" => 20,
        "plotting" => true,
        "verbose" => true,
        "recursive" => true,
        "suppress_output" => true,
        "safe_formulas" => false,
    ),
    "regression" => Dict(
        "enabled" => false,
        "regression_threshold" => 0.05
    ),
    "roofline" => Dict(
        "enabled" => true,
        "default_threshold" => 0.5,
    ),
    "memory_bandwidth" => Dict(
        "enabled" => true,
        "default_threshold" => 0.5,
    ),
    "raw_test" => Dict(),
    "machine_benchmarking" => Dict(
        "memory_bandwidth_test_buffer_size" => false
    ),
    "MPI" => Dict(
        "enabled" => false,
        "mode" => "reduce"
    ),
)



end # module


using TOML

function parseConfigurationMacro(_ :: ExtendedExpr, ctx :: Context, info :: Dict) :: Expr

    # Parse, and merge
    string = info[Symbol("")]

    parsed = TOML.parse(string)

    old = ctx._global.configuration["general"]["verbose"]

    ctx._global.configuration = Configuration.merge_configs(ctx._global.configuration, parsed)

    if ctx._global.configuration["general"]["verbose"] != old
        addLog("general", "Verbosity level changed")
        verboseOutput()
    end

    return quote
        begin
        end
    end
end
