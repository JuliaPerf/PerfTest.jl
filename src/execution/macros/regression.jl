

define_regression_validation = defineMacroParams([
    MacroParameter(:threshold,
                   Float64,
                   (x) -> 0.0 <= x <= 1.0,
                   0.9, #default
        false),
    MacroParameter(:metrics,
        Union{Symbol,Vector{Symbol}},
        always_true,
        [:median_time], #default
        false),
])
"""
This macro is used to define the memory bandwidth of a target in order to execute the effective memory thorughput methodology.

# Arguments
 - threshold : the minimum ratio over that is allowed to pass the test (e.g 0.9 means that the test is a success if the new metric is at least 90% of the old)
 - enable: track regression in the metrics whose names are passed as argument, it accepts a single string or a vector of strings. Non-existent metrics are ignored.
# Example:
    @regression threshold=0.9 enable=:median_time
"""
macro regression(args...)
    return :(
        begin end
    )
end
