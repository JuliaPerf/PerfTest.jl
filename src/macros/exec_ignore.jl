
on_perftest_exec_validation = defineMacroParams([
    MacroParameter(
        Symbol(""),
        ExtendedExpr,
        true
    )
])
"""
The expression given to this macro will only be executed in the generated suite, and will be deleted if the source code is executed as is.
"""
macro on_perftest_exec(anything)
    return :(
        begin end
    )
end

on_perftest_ignore_validation = on_perftest_exec_validation
"""
The expression given to this macro will only be executed in the source code, and will be deleted in the generated performance test suite.
"""
macro on_perftest_ignore(anything)
    return esc(anything)
end
