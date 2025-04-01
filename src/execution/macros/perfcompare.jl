

define_perfcmp_validation = defineMacroParams([
    MacroParameter(
        Symbol(""),
        Union{ExtendedExpr}
    )
])
"""

"""
macro perfcompare(args...)
    return  :(
        begin end
    )
end

"""
  Same as perfcompare
"""
macro perfcmp(args...)
    return :(
        begin end
    )
end
