function parseSymbol(x, ctx::Context)
    if x in ctx._local.exported_vars
        return quote _PRFT_LOCAL[:additional][:exported][$(QuoteNode(x))] end
    elseif !(Configuration.CONFIG["general"]["safe_formulas"]) || x in names(Base)
        return x
    else
        throwParseError!("Variable \"$x\" not exported or undefined, use @export_vars to export", ctx)
        return empty_expr()
    end
end

# A unique wrapper type to mark "do not transform this QuoteNode"
# The thing is, transforming symbols can get quite messy cause some operators like a.b trigger it as well, so we need to mark them otherwise the fields will be treated as symbols.
struct DotFieldNode
    inner::QuoteNode
end

# Marks a fully-resolved symbol chain (e.g. :flop.double.vector_512).
# `main` is the head symbol, `rest` are the chained field symbols.
struct SymbolChainNode
    main::Symbol
    rest::Vector{Symbol}
end

# Helper: given a node, if it represents a symbol chain rooted at a QuoteNode,
# return (main_sym, rest_syms::Vector{Symbol}); otherwise return nothing.
#
# Cases handled:
#   QuoteNode(:s)                      -> (:s, Symbol[])
#   Expr(:., <base>, QuoteNode(:f))    -> resolve <base> recursively, push :f
#   Expr(:., <base>, SymbolChainNode)  -> (already-collected single-symbol base) chained further
function collectSymbolChain(node)
    if node isa QuoteNode && node.value isa Symbol
        return (node.value, Symbol[])
    elseif node isa SymbolChainNode
        return (node.main, copy(node.rest))
    elseif node isa Expr && node.head === :. && length(node.args) == 2 &&
           node.args[2] isa QuoteNode && node.args[2].value isa Symbol
        base = collectSymbolChain(node.args[1])
        base === nothing && return nothing
        main, rest = base
        push!(rest, node.args[2].value)
        return (main, rest)
    else
        return nothing
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
    # Resolved symbol chains: :main.a.b... -> SBMID(:main, [:a, :b, ...])
    validASTRule(
        checkType(SymbolChainNode),
        (x, ctx, info) -> isempty(x.rest) ?
            SBMID(x.main) :
            SBMID(x.main, x.rest)
    ),
    ASTRule(
        checkType(QuoteNode),
        (x, ctx) -> (x.value in union(ctx._global.valid_symbols)) ? true : (addLog("metrics", "[METRIC] $(x.value) has been parsed on a formula, its availability is not checked automatically");
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

function transformFormula(form_expr::ExtendedExpr, context::Context)::ExtendedExpr

    # prewalk: collapse dot-access chains rooted at a QuoteNode (symbol chains)
    # into a single SymbolChainNode sentinel, and protect plain a.b field names.
    protected = MacroTools.prewalk(form_expr) do node
        if node isa Expr && node.head === :. && length(node.args) == 2 &&
           node.args[2] isa QuoteNode
            chain = collectSymbolChain(node)
            if chain !== nothing
                # This is :sym, :sym.a, :sym.a.b, ... -> mark as a symbol chain
                main, rest = chain
                SymbolChainNode(main, rest)
            else
                # This is a.b where a is not (rooted at) a quoted symbol:
                # protect the field name QuoteNode so it is not treated as a metric.
                Expr(:., node.args[1], DotFieldNode(node.args[2]))
            end
        else
            node
        end
    end

    # Ordinary context independent transformations
    walked = MacroTools.postwalk(ruleSet(context, formula_rules), protected)

    # postwalk: unwrap field sentinels back to QuoteNodes
    result = MacroTools.postwalk(walked) do node
        if node isa Expr && node.head === :. && length(node.args) == 2 &&
           node.args[2] isa DotFieldNode
            Expr(:., node.args[1], node.args[2].inner)
        else
            node
        end
    end

    x = MacroTools.prettify(result)
    return x isa ExtendedExpr ? x : :(:($$x))
end