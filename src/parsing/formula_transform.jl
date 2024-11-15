

formula_rules = ASTRule[
    validASTRule(
        checkType(Symbol),
        no_transform,
    ),
    validASTRule(
        checkType(LineNumberNode),
        empty_expr,
    ),
    ASTRule(
        checkType(QuoteNode),
        (x, ctx) -> x.value in ctx._global.valid_symbols ? true : (throwParseError!("Invalid symbol $(x.value) in formula", ctx); false),
        abort_if_invalid((x, ctx, info) -> quote _PRFT_LOCAL[:primitives][$x] end)
    ),
]


function transformFormula(form_expr :: ExtendedExpr, context :: Context) :: ExtendedExpr
    return MacroTools.prettify(MacroTools.postwalk(ruleSet(context, formula_rules), form_expr))
end
