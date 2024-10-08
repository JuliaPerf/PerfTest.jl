
"""
This macro is used to signal that the wrapped expression is a performance test target, and therefore its performance will be sampled and then evaluated following the current suite configuration.

If the macro is evaluated it does not modify the target at all. The effects of the macro only show when the script is transformed into a performance testing suite.

This macro is sensitive to context since other adjacent macros can change how the target will be evaluated.

# Arguments
 - The target expression

# Example
    @perftest 2 + 3
"""
macro perftest(anything)
    return esc(anything)
end

"""
Perftest_config macro, used to set customised configuration on the suite generated by the source script

Configuration inside this macro must follow the syntax below:

    @perftest_config
        key = value
        key.subkey = value
    end

Where key can be any configuration parameter, in some cases parameters will consist on a set of subparameters denoted by the "." to refer to them.

"""
macro perftest_config(expr)
    # It deletes the contents and does nothing since this macro wont
    # be evaluated during performance testing but during functional testing
    # The contents are used by parsing them during the test translation
    return begin end
end

"""
The expression given to this macro will only be executed in the generated suite, and will be deleted if the source code is executed as is.
"""
macro on_perftest_exec(anything)
    return :(
        begin end
    )
end

"""
The expression given to this macro will only be executed in the source code, and will be deleted in the generated performance test suite.
"""
macro on_perftest_ignore(anything)
    return esc(anything)
end


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
macro define_metric(expr)
    return :(
        begin end
    )
end

"""
This macro is used to define the memory bandwidth of a target in order to execute the effective memory thorughput methodology.

# Arguments
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally some special symbols are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable to it.

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
macro define_eff_memory_throughput(expr)
    return :(
        begin end
    )
end

macro metric_def_visible(expr)
    return expr
end

# TODO
macro define_reference(expr)
    return :(
        begin end
    )
end

"""
This macro enables roofline modelling, if put just before a target declaration (`@perftest`) it will proceed to evaluate it using a roofline model.

# Mandatory arguments
  - formula block: the macro has to wrap a block that holds a formula to obtain the operational intensity of target algorithms.

# Optional arguments
  - `cpu_peak` : a manual input value for the maximum attainable FLOPS, this will override the empirical runtime benchmark
  - `membw_peak` : a manual input value for the maximum memory bandwith, this will override the empirical runtime benchmark
  - `target_opint` : a desired operational intensity for the target, this will turn operational intensity into a test metric
  - `actual_flops`: another formula that defines the actual performance of the test.
  - `target_ratio` : the acceptable ratio between the actual performance and the projected performance from the roofline, this will turn actual performance into a test metric.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: will be substituted by the FLOP count the target.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.
Any formula block specified in this macro supports these symbols.

# Example

    @roofline actual_flops=:autoflop target_ratio=0.05 begin
        mem = ((:iterator + 1) * :iterator)
        :autoflop / mem
    end

The code block defines operational intensity, whilst the other arguments define how to measure and compare the actual performance with the roofline performance. If the actual to projected performance ratio goes below the target, the test fails.

"""
macro roofline(opint_formula, cpu_peak=nothing, membw_peak=nothing)
    return :(
        begin end
    )
end

"""
  Defines a custom metric for informational purposes that will not be used for testing but will be printed as output.
"""
macro auxiliary_metric(formula, name, units)
    return :(
        begin end
    )
end
