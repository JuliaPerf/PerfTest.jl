
function parseSymbol(x, ctx :: Context)
    if x in ctx._local.exported_vars
        return quote _PRFT_LOCAL[:additional][:exported][$(QuoteNode(x))] end
    elseif !(Configuration.CONFIG["general"]["safe_formulas"]) || x in names(Base)
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
        (x, ctx) -> (x.value in ctx._global.valid_symbols) ? true : (addLog("metrics", "[METRIC] $(x.value) has been parsed on a formula, its availability is not checked automatically");
                                                                     #throwParseError!("Variable \"$x\" not exported or undefined, use @export_vars to export", ctx)
                                                                     ),
        (x, ctx, info) -> info == true ? (
            quote
                test_res.primitives[$x]
            end
        ) : SBMID(x.value)),
]


function exportVars(symbols::Set{Symbol}, context::Context)::Expr

    export_one(sym) = quote
	      _PRFT_LOCAL_ADDITIONAL[:exported][$(QuoteNode(sym))] = $sym
    end

    expr = quote end
    for symbol in symbols
        expr = :($expr; $(export_one(symbol)))
        push!(context._local.exported_vars, symbol)
    end

    return expr
end

# A unique wrapper type to mark "do not transform this QuoteNode"
# The thing is, transforming symbols can get quite messy cause some operators like a.b trigger it as well, so we need to mark them otherwise the fields will be treated as symbols.
struct DotFieldNode
    inner::QuoteNode
end

function transformFormula(form_expr::ExtendedExpr, context::Context)::ExtendedExpr

    # prewalk: wrap QuoteNodes that are dot-access field names
    protected = MacroTools.prewalk(form_expr) do node
        if node isa Expr && node.head === :. &&
           length(node.args) == 2 && node.args[2] isa QuoteNode
            # Replace the QuoteNode child with our sentinel
            Expr(:., node.args[1], DotFieldNode(node.args[2]))
        else
            node
        end
    end

    # Ordinary context independent transformations
    walked = MacroTools.postwalk(ruleSet(context, formula_rules), protected)

    # postwalk: unwrap sentinels back to QuoteNodes
    result = MacroTools.postwalk(walked) do node
        if node isa Expr && node.head === :. &&
           length(node.args) == 2 && node.args[2] isa DotFieldNode
            Expr(:., node.args[1], node.args[2].inner)
        else
            node
        end
    end

    x = MacroTools.prettify(result)
    return x isa ExtendedExpr ? x : :(:($$x))
end