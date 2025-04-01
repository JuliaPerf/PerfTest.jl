

define_eff_memory_throughput_validation = defineMacroParams([
    MacroParameter(:threshold,
                   Float64,
                   (x) -> 0.0 <= x <= 1.0,
                   0.05, #default
        false),
    MacroParameter(:disable,
        Union{String, Vector{String}},
        always_true,
        [], #default
        false),
    MacroParameter(:enable,
        Union{String,Vector{String}},
        always_true,
        [], #default
        false),
])
"""
This macro is used to define the memory bandwidth of a target in order to execute the effective memory thorughput methodology.

# Arguments
 - threshold : the allowed minimum percentage over the maximum attainable that is allowed to pass the test
 - disable: do not track regression in the metric whose names are passed as argunment, it accepts a single string or a vector of strings. Non-existent metrics are ignored. Has priority over "enable" below
 - enable: do not track regression in the metric whose names are passed as argunment, it accepts a single string or a vector of strings. Non-existent metrics are ignored.
# Example:

The following definition assumes that each execution of the target expression involves transacting 1000 bytes. Therefore the bandwith is 1000 / execution time.

    @regression threshold=0.05
"""
macro regression(args...)
    return :(
        begin end
    )
end
