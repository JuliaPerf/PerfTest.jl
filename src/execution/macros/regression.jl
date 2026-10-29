

define_regression_validation = defineMacroParams([
    MacroParameter(:low_is_bad,
                    Union{Bool,Vector{Bool}},
                    true,
                    false),
    # No default, a missing threshold comes from regression.default_threshold, see defaultRegressionThresholds
    MacroParameter(:threshold,
                   Union{Float64,Vector{Float64}};
                   validation_function = (x) -> x isa Float64 ? 0.0 <= x : all(0.0 <= t for t in x),
                   mandatory = false),
    MacroParameter(:metrics,
        Union{metricID(),Vector{metricID()}},
        always_true,
        [:median_time], #default
        false),
    MacroParameter(:showvar,
        Bool,
        false, #default
        false),
])
"""
This macro is used to define regression tests with a customized configuration. Redefining the macro in the same testset will overwrite the previous configuration.

A test compares the ratio new/reference of each metric, between the new value and the one of the reference execution, with its threshold.

# Arguments
 - low_is_bad: whether a lower value of the metric is bad, `true` by default. With `low_is_bad=true` (e.g. for a throughput) the test passes if the ratio is above the threshold, with `low_is_bad=false` (e.g. for a time) if it is below. It can be a single boolean that applies to all metrics or a vector of booleans that applies to each metric separately.
 - threshold : the ratio new/reference the metric must stay above (`low_is_bad=true`, e.g. 0.9 fails if the new value is 90% of the reference or less) or below (`low_is_bad=false`, e.g. 1.1 fails if the new value is 110% of the reference or more). It can be a single float that applies to all metrics or a vector of floats that applies to each metric separately.
   Without it, each metric takes its threshold from the configuration key `regression.default_threshold` (1.1 by default): the value itself for a metric with `low_is_bad=false`, and 2 − that value for one with `low_is_bad=true` (1.1 gives 0.9), so the default tolerates a 10% change in the bad direction either way. A `regression.default_threshold` of 2 or more leaves no threshold for a metric with `low_is_bad=true`, it is reported as a parse error.
 - metrics: track regression in the metrics whose names are passed as argument, it accepts a single string or a vector of strings. Non-existent metrics are ignored.
 - showvar: when true, print a "(± X)" standard-error-of-the-mean interval alongside the ratio metric and any auxiliary metrics in scope. Ignored (no interval shown) whenever the underlying sample count is below 30.
# Examples:

```julia
    # Tests will fail if the median time is 110% of the reference value or more
    @regression threshold=1.1 low_is_bad=false metrics=:median_time

    # Tests will fail if the metric results are 90% of the reference value or less
    @regression threshold=0.9 low_is_bad=true metrics=[:custom_metric1, :custom_metric2]

    # Without threshold, with the default regression.default_threshold = 1.1: the median time fails at 110% of the
    # reference or more (threshold 1.1), custom_metric1 at 90% or less (threshold 2 − 1.1 = 0.9)
    @regression low_is_bad=[false, true] metrics=[:median_time, :custom_metric1]
```
"""
macro regression(args...)
    return :(
        begin end
    )
end
