## CONDITION RULES:

# TESTSET SUBSTITUTION

testset_macro_rule = ASTRule(
    x -> @capture(x, @testset __),
    no_validation,
    (x, ctx, info) -> testsetToBenchGroup!(x, ctx)
)

# TESTS

test_macro_rule = ASTRule(
    x -> @capture(x, @test __),
    no_validation,
    empty_expr
)

test_throws_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

test_logs_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

inferred_macro_rule = ASTRule(
    x -> @capture(x, @inferred __),
    no_validation,
    empty_expr
)

test_deprecated_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

test_warn_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

test_nowarn_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

test_broken_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

test_skip_macro_rule = ASTRule(
    x -> escCapture(x, Symbol("@test_throws")),
    no_validation,
    empty_expr
)

# PERFTEST TARGET OBSERVERS

perftest_macro_rule = ASTRule(
    x -> @capture(x, @perftest __),
    perftest_validation,
    (x, ctx, info) -> perftestToBenchmark!(x, ctx)
)

perftest_begin_macro_rule = ASTRule(
    x -> @capture(x, @benchmark __) || (escCaptureGetblock(x, Symbol("@count_ops")) != nothing),
    no_validation,
    (x, ctx, info) -> (ctx.env_flags.inside_target = true; x)
)

perftest_scope_assignment_macro_rule = ASTRule(
    x -> @capture(x, _ = _),
    no_validation,
    (x, ctx, info) -> scopeAssignment(x, ctx)
)

perftest_scope_arg_macro_rule = ASTRule(
    x -> @capture(x, _(__)),
    no_validation,
    (x, ctx, info) -> (scopeArg(x, ctx))
)

perftest_scope_vecf_arg_macro_rule = ASTRule(
    x -> @capture(x, _.(__)),
    no_validation,
    (x, ctx, info) -> scopeVecFArg(x, ctx)
)

perftest_dot_interpolation_rule = ASTRule(
    x -> @capture(x, _._),
    no_validation,
    (x, ctx, info) -> scopeDotInterpolation(x, ctx)
)

perftest_end_macro_rule = ASTRule(
    x -> x == :(:__CONTEXT_TARGET_END__),
    no_validation,
    (x, ctx, info) -> (ctx.env_flags.inside_target = false; nothing)
)


# TOKEN OBSERVERS

back_macro_rule = ASTRule(
    x -> (x == :(:__BACK_CONTEXT__)),
    no_validation,
    (x, ctx, info) -> backTokenToContextUpdate!(x, ctx)
)

prefix_macro_rule = ASTRule(
    x -> (x == :(:__PERFTEST_FW__)),
    no_validation,
    (x, ctx, info) -> perftestprefix(ctx)
)

suffix_macro_rule = ASTRule(
    x -> (x == :(:__PERFTEST_AFTER__)),
    no_validation,
    (x, ctx, info) -> perftestsuffix(ctx)
)

# CONFIG

config_macro_rule = ASTRule(
    x -> (@capture(x, @m_ __); m == Symbol("@perftest_config")),
    config_validation,
    (x, ctx, info) -> (parseConfigurationMacro(x, ctx, info))
)


# CONDITIONAL EXECUTION

on_perftest_exec_rule = ASTRule(
    x -> escCaptureGetblock(x, Symbol("@on_perftest_exec")) !== nothing,
    on_perftest_exec_validation,
    (x, ctx, info) -> Expr(:block, x.args[2:end]...)
)

on_perftest_ignore_rule = ASTRule(
    x -> escCaptureGetblock(x, Symbol("@on_perftest_ignore")) !== nothing,
    on_perftest_ignore_validation,
    (x, ctx, info) -> :(begin end)
)

# CUSTOM METRICS
define_memory_throughput_rule = ASTRule(
    x -> escCaptureGetblock(x, Symbol("@define_eff_memory_throughput")) !== nothing,
    define_eff_memory_throughput_validation,
    # Defined on metrics.jl
    (x, ctx, info) -> onMemoryThroughputDefinition(transformFormula(info[Symbol("")], ctx), ctx, info)
)

define_metric_rule = ASTRule(
    x -> escCaptureGetblock(x, Symbol("@define_metric")) !== nothing,
    define_metric_validation,
    (x, ctx, info) -> defineCustomMetric(:custom, ctx, info)
)

auxiliary_metric_rule = ASTRule(
    x -> escCaptureGetblock(x, Symbol("@auxiliary_metric")) !== nothing,
    auxiliary_metric_validation,
    (x, ctx, info) -> defineCustomMetric(:aux, ctx, info)
)


export_vars_rule = ASTRule(
    x -> (@capture(x, @m_ __); m == Symbol("@export_vars")),
    export_vars_validation,
    (x, ctx, info) -> exportVars(info, ctx)
)

# ROOFLINE
roofline_macro_rule = ASTRule(
    x -> @capture(x, @roofline __),
    roofline_validation,
    # See roofline.jl at methodologies
    (x, ctx, info) -> onRooflineDefinition(info[Symbol("")], ctx, info)
)

# RAW
manual_macro_rule = ASTRule(
    x -> @capture(x, @perfcompare __),
    define_perfcmp_validation,
    (x, ctx, info) -> onPerfcmpDefinition(x, ctx, info)
)

function treeRunRecursive!(path::AbstractString, parent_context :: Context)::Pair{ExtendedExpr,ExtendedExpr}

    addLog("hierarchy", "[RECURSIVE] Recursivity is enabled, entering \"$path\"")
    # The transformation treats child files as if it were into the main one plugging their testsets into the global hierarchy

    input_expr = loadFileAsExpr(path)

    # A new context is made for the included file, the configuration is cloned so it can be altered by the included file without affecting the parent file
    push!(Configuration.PARENT_CONFIGS, deepcopy(Configuration.CONFIG))
    ctx = Context(GlobalContext(path, VecErrorCollection(), formula_symbols, :RECURSIVE))
    ctx._local = parent_context._local


    # Run through AST and build new expressions
    middle = _treeRun(input_expr, ctx)

    importErrors!(parent_context._global.errors, ctx._global.errors, path)


    Configuration.CONFIG = pop!(Configuration.PARENT_CONFIGS)
    addLog("hierarchy", "[RECURSIVE] \"$path\" has been processed, $(num_errors(ctx._global.errors)) errors found")

    return Pair(middle, ctx.test_tree_expr_builder[1][1])
end

# RECURSIVE
recursive_rule = ASTRule(
    x -> @capture(x, include(path_)),
    always_true,
    (x, ctx, info) -> (begin
        if Configuration.CONFIG["general"]["recursive"]
            @capture(x, include(path_))
            measure_expr, test_expr = treeRunRecursive!(joinpath(dirname(ctx._global.original_file_path), path), ctx)
            push!(ctx.test_tree_expr_builder[end], test_expr)
            measure_expr
        else
            quote end
        end
    end)
)
