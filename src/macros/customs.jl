
define_metric_validation = defineMacroParams([
    MacroParameter(
        :name,
        String,
        true
    ),
    MacroParameter(
        :units,
        String,
        true
    ),
    MacroParameter(
        Symbol(""),
        ExtendedExpr,
        true
    )
])
"""
This macro is used to define a new custom metric.

# Arguments
 - `name` : the name of the metric for identification purposes.
 - `units` : the unit space that the metric values will be in.
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally some special symbols are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable to it.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: will be substituted by the FLOP count the target.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.
"""
macro define_metric(args...)
    return :(
        begin end
    )
end


define_test_metric_validation = defineMacroParams([
    MacroParameter(
        :name,
        String,
        true
    ),
    MacroParameter(
        :units,
        String,
        true
    ),
    MacroParameter(
        :reference,
        ExtendedExpr,
        true
    ),
    MacroParameter( # By default lower than threshold is considered as a failure
        :low_is_bad,
        Bool,
        true,
        false
    ),
    MacroParameter(
        Symbol(""),
        ExtendedExpr,
        true
    )
])

macro define_test_metric(args...)
    return :(begin end)
end

# Same parameters
auxiliary_metric_validation = define_metric_validation
"""
  Defines a custom metric for informational purposes that will not be used for testing but will be printed as output.

# Arguments
 - `name` : the name of the metric for identification purposes.
 - `units` : the unit space that the metric values will be in.
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally some special symbols are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable to it.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: will be substituted by the FLOP count the target.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.
"""
macro auxiliary_metric(formula, name, units)
    return :(
        begin end
    )
end


define_eff_memory_throughput_validation = defineMacroParams([
    MacroParameter(Symbol(""),
                   ExtendedExpr,
                   true),
    MacroParameter(:ratio,
                   Float64,
                   (x) -> 0.0 <= x <= 1.0,
                   0.7, #default
                   false)
])
"""
This macro is used to define the memory bandwidth of a target in order to execute the effective memory thorughput methodology.

# Arguments
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally some special symbols are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable to it.
 - ratio : the allowed minimum percentage over the maximum attainable that is allowed to pass the test

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: will be substituted by the FLOP count the target.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.

# Example:

The following definition assumes that each execution of the target expression involves transacting 1000 bytes. Therefore the bandwith is 1000 / execution time.

    @define_eff_memory_throughput begin
          1000 / :median_time
    end

"""
macro define_eff_memory_throughput(args...)
    return :(
        begin end
    )
end
