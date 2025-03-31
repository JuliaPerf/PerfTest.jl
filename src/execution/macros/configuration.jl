

config_validation = defineMacroParams([
    MacroParameter(Symbol(""),
                   String,
                   true)
])

"""
Captures a set of configuration parameters that will override the default configuration. The parameters shall be written in TOML syntax, like a subset of the complete configuration (see config.toml generated by executing transform, or transform/configuration.jl for more information). Order is irrelevant. This macro shall be put as high as possible in the test file (code that is above will be transformed using the default configuration).

# Recursive transformation:
This macro will set the new configuration keys for the current file and any other included files. If the included files have the macro as well, those macros will override the configuration locally for each file.

# Arguments
 - A String, with the TOML declaration of configuration keys

# Example

@perftest_config "
[roofline]
  enabled = false
[general]
  max_saved_results = 1
  recursive = false
"

"""
macro perftest_config(anything)
    return :(begin end)
end


