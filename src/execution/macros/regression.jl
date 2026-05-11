

define_regression_validation = defineMacroParams([
    MacroParameter(:low_is_bad,
                    Union{Bool,Vector{Bool}},
                    true,
                    false),
    MacroParameter(:threshold,
                   Union{Float64,Vector{Float64}},
                   (x) -> x isa Float64 ? 0.0 <= x : all(0.0 <= t for t in x),
                   0.9, #default
        false),
    MacroParameter(:metrics,
        Union{metricID(),Vector{metricID()}},
        always_true,
        [:median_time], #default
        false),
])
"""
This macro is used to define regression tests with a customized configuration. Redefining the macro in the same testset will overwrite the previous configuration.

# Arguments
 - low_is_bad: whether a lower value of the metric is considered a failure (e.g. for time measurements) or a success (e.g. for throughput measurements). It can be a single boolean that applies to all metrics or a vector of booleans that applies to each metric separately.
 - threshold : the minimum ratio over that is allowed to pass the test (e.g 0.9 means that the test is a success if the new metric is at least 90% of the old). It can be a single float that applies to all metrics or a vector of floats that applies to each metric separately.
 - metrics: track regression in the metrics whose names are passed as argument, it accepts a single string or a vector of strings. Non-existent metrics are ignored.
# Examples:

```julia
    # Tests will fail if median time is lower than 90% of the reference value
    @regression threshold=0.9 low_is_bad=false metrics=:median_time

    # Tests will fail if metric results are higher than 110% of the reference value
    @regression threshold=1.1 low_is_bad=true metrics=[:custom_metric1, :custom_metric2]
```
"""
macro regression(args...)
    return :(
        begin end
    )
end
