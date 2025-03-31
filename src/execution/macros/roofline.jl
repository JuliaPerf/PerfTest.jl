
roofline_validation = defineMacroParams([
    MacroParameter(
        :cpu_peak,
        Float64,
        greaterThan0,
    ),
    MacroParameter(
        :membw_peak,
        Float64,
        greaterThan0,
    ),
    MacroParameter(
        :target_opint,
        Float64,
        greaterThan0,
    ),
    MacroParameter(
        :actual_flops,
        Union{ExtendedExpr, Number}
    ),
    MacroParameter(
        :target_ratio,
        Float64,
        (x) -> 0. < x < 2.
    ),
    MacroParameter(
        :test_opint,
        Bool,
        always_true,
        false
    ),
    MacroParameter(
        :test_flop,
        Bool,
        always_true,
        true
    ), # TODO
    MacroParameter(
        :mem_benchmark,
        Symbol,
        (x) -> x in [:COPY,:ADD,:MAX,:MEAN],
        :COPY,
    ),
    MacroParameter(
        Symbol(""),
        Union{ExtendedExpr, Number}
    )
])
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
