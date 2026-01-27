

define_perfcmp_validation = defineMacroParams([
    MacroParameter(
        Symbol(""),
        Union{ExtendedExpr}
    )
])
"""
This macro is used to manually declare performance test conditions.

# Arguments
 - An expression that must result to a boolean when evaluated. Being true if the comparison leads to a succesful performance test. Special symbols can be used.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: will be substituted by the FLOP count the target.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.

# Example:

`
    @perfcompare :median_time < 0.05
`
"""
macro perfcompare(args...)
    return :(
        begin end
    )
end

"""
  Alias of @perfcompare
"""
macro perfcmp(args...)
    return :(
        begin end
    )
end
