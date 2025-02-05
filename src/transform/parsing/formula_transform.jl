
function parseSymbol(x, ctx :: Context)
    if x in ctx._local.exported_vars
        return quote _PRFT_LOCAL[:additional][:exported][$(QuoteNode(x))] end
    elseif !(ctx._global.configuration["general"]["safe_formulas"]) || x in names(Base)
        return x
    else
        throwParseError!("Variable \"$x\" not exported or undefined, use @export_vars to export", ctx)
        return empty_expr()
    end
end


formula_rules = ASTRule[
    validASTRule(
        checkType(Symbol),
        (x, ctx, info) -> parseSymbol(x, ctx)
    ),
    validASTRule(
        checkType(LineNumberNode),
        empty_expr,
    ),
    ASTRule(
        checkType(QuoteNode),
        (x, ctx) -> (x.value in ctx._global.valid_symbols) ? true :  (@info "$(x.value) has been parsed on a formula, its availability is not checked automatically"),
        (x, ctx, info) -> info == true ? (quote _PRFT_LOCAL[:primitives][$x] end) : x),
]


function transformFormula(form_expr :: ExtendedExpr, context :: Context) :: ExtendedExpr
    x = MacroTools.prettify(MacroTools.postwalk(ruleSet(context, formula_rules), form_expr))
    # There is the edge case of having just a basic type, this condition deals with it
    if x isa ExtendedExpr
        return x
    else
        return :(:($$x))
    end
end
