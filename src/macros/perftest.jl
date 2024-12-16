
perftest_validation = defineMacroParams([
    MacroParameter(:samples,
                   Int,
                   always_true,
                   10000),
    MacroParameter(Symbol(""),
                   ExtendedExpr,
                   true)
])
"""
This macro is used to signal that the wrapped expression is a performance test target, and therefore its performance will be sampled and then evaluated following the current suite configuration.

If the macro is evaluated it does not modify the target at all. The effects of the macro only show when the script is transformed into a performance testing suite.

This macro is sensitive to context since other adjacent macros can change how the target will be evaluated.

Use the parameter "samples" to specify the amount of samples (executions) to take.

# Arguments
 - The target expression
 - Number of samples (default: 10000)

# Example
    @perftest 2 + 3
    @perftest samples=100 2 + 3
"""
macro perftest(anything)
    return esc(anything)
end
