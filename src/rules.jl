using BenchmarkTools
using MacroTools
using Test
using BenchmarkTools: TrialJudgement

include("structs.jl")
include("prefix.jl")


# Builds a tree from the ground up
function updateTestTreeUpwards!(tree_builder :: AbstractArray, name :: Union{String, Expr})

    # Get depth level
    depth = length(tree_builder)

    # Concatenate expressions of the current level into a new node on the upper level
    concat = :(Nothing)

    for expr in tree_builder[depth]
        concat = :($concat; $expr)
    end

    if depth > 1
        push!(tree_builder[depth-1],
            quote
                @testset $name (showtiming = false) begin
                    push!(depth, PerfTests.DepthRecord($name))
                    $concat
                    pop!(depth)
                end
            end
        )

        # Delete last level
        pop!(tree_builder)
    else
        pop!(tree_builder)
        push!(tree_builder, Expr[
            quote
                tt[$name] = (@testset $name (showtiming = false) begin
                    push!(depth, PerfTests.DepthRecord($name))
                    $concat
                    pop!(depth)
                end)
            end
        ])
    end
end

function updateTestTreeDownwards!(tree_builder :: AbstractArray)
    # Add new level
    push!(tree_builder, Expr[])
end

function updateTestTreeSideways!(tree_builder::AbstractArray, name::String)

    # Get depth level
    depth = length(tree_builder)

    # Add the expression to de tree builder
    push!(tree_builder[depth],
          quote
            push!(depth, PerfTests.DepthRecord($name))
            @test PerfTests.inRange(tolerance, PerfTests.by_index(judgement, depth).ratio.time)

            if PerfTests.inRange(tolerance, PerfTests.by_index(judgement, depth).ratio.time)
                    else
                        PerfTests.printdepth!(depth)
                        PerfTests.printfail(PerfTests.by_index(judgement, depth), PerfTests.by_index(suite, depth), PerfTests.by_index(reference[1], depth), tolerance, length(depth))
                    end

            pop!(depth)
          end)

end

function testsetToBenchGroup!(input_expr :: Expr, context :: Context)
    # Get the elements of interest from the macrocall
    @capture(input_expr, @testset properties__ test_block_) ? Nothing : error("Incompatible testset syntax \n");

    # Get the name from the list of elements of the testset macrocall
    name = meta_get_string(properties);


    # Update context: add depth level
    push!(context.depth,
          ASTWalkDepthRecord(name));

    # Update context: add new level to the tree
    updateTestTreeDownwards!(context.test_tree_expr_builder)

    # Return the substitution
    return length(context.depth) > 1 ?
    :(
        l[$name] = BenchmarkGroup();
        let l = l[$name]
            $test_block
        end;

        :__BACK_CONTEXT__
    ) :
    :(
        :__PERFTEST_FW__;

        l = BenchmarkGroup();
        let l = l[$name]
            $test_block
        end;

        :__BACK_CONTEXT__
    )
end

function backTokenToContextUpdate!(input_expr ::QuoteNode, context::Context)
    # Update context: consolidate tree level
    updateTestTreeUpwards!(context.test_tree_expr_builder,
                           last(context.depth).depth_name)

    # Update context: delete depth level
    pop!(context.depth)

    return nothing;
end

function perftestToBenchmark!(input_expr::Expr, context::Context)
    # Get the elements of interest from the macrocall
    @capture(input_expr, @perftest prop__ expr_)

    num = (last(context.depth).depth_test_count += 1)
    name = "Test $num"

    # Update context: create expression on tree builder
    updateTestTreeSideways!(context.test_tree_expr_builder, name)

    # Return the substitution
    return :(
        l[$name] = @benchmark ($expr)
    )
end

## CONDITION RULES:
# TESTSET SUBSTITUTION

testset_macro_rule = ASTRule(
    x -> @capture(x, @testset __),
    (x, ctx) -> testsetToBenchGroup!(x, ctx)
)

# TESTS

test_macro_rule = ASTRule(
    x -> @capture(x, @test __),
    (x, ex_state) -> :(nothing)
)

test_throws_macro_rule = ASTRule(
    x -> @capture(x, @test_throws __),
    (x, ex_state) -> :(nothing)
)

test_logs_macro_rule = ASTRule(
    x -> @capture(x, @test_logs __),
    (x, ex_state) -> :(nothing)
)

inferred_macro_rule = ASTRule(
    x -> @capture(x, @inferred __),
    (x, ex_state) -> :(nothing)
)

test_deprecated_macro_rule = ASTRule(
    x -> @capture(x, @test_deprecated __),
    (x, ex_state) -> :(nothing)
)

test_warn_macro_rule = ASTRule(
    x -> @capture(x, @test_warn __),
    (x, ex_state) -> :(nothing)
)

test_nowarn_macro_rule = ASTRule(
    x -> @capture(x, @test_nowarn __),
    (x, ex_state) -> :(nothing)
)

test_broken_macro_rule = ASTRule(
    x -> @capture(x, @test_broken __),
    (x, ex_state) -> :(nothing)
)

test_skip_macro_rule = ASTRule(
    x -> @capture(x, @test_skip __),
    (x, ex_state) -> :(nothing)
)


# PERFTEST TARGET OBSERVERS

perftest_macro_rule = ASTRule(
    x -> @capture(x, @perftest __),
    (x, ctx) -> perftestToBenchmark!(x, ctx)
)

# TOKEN OBSERVERS

back_macro_rule_d = ASTRule(
    x -> x == :__BACK_CONTEXT__,
    (x, ctx) -> backTokenToContextUpdate!(x, ctx)
)

back_macro_rule = ASTRule(
    x -> (x == :(:__BACK_CONTEXT__)),
    (x, ctx) -> backTokenToContextUpdate!(x, ctx)
)

prefix_macro_rule = ASTRule(
    x -> (x == :(:__PERFTEST_FW__)),
    (x, ctx) -> perftestprefix(ctx)
)
