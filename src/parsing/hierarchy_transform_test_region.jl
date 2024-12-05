
# The tree builder is a stack used to construct the test region
# 3 DIRECTIONS
# DOWNWARDS : a new testset level is parsed -> a new test level is created (new top of stack)
# SIDEWAY : a test is parsed -> test is added to the level (top of stack)
# UPWARDS : the level has been fully parsed -> the test level is pushed into the previous level (top of stack merged with previous and then top is popped)
# When all levels have been pushed, just one element will be left in the tree builder, the final test region

# Builds a tree from the ground up
function updateTestTreeUpwards!(tree_builder :: AbstractArray, name :: Union{String, Expr})

    # Get depth level
    depth = length(tree_builder)

    # Concatenate expressions of the current level into a new node on the upper level
    concat = :(begin end)

    for expr in tree_builder[depth]
        concat = :($concat; $expr)
    end

    if depth > 1
        push!(tree_builder[depth-1],
            quote
                @testset $name (showtiming = false) begin
                    $(newLocalScope(name, concat))
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
                             $(newLocalScope(name, concat))
                         end)
            end
        ])
    end
end


function updateTestTreeUpwardsFor!(tree_builder::AbstractArray, name::Union{String,Expr}, context :: Context)

    # Get depth level
    depth = length(tree_builder)

    # Concatenate expressions of the current level into a new node on the upper level
    concat = :(begin end)

    for expr in tree_builder[depth]
        concat = :($concat; $expr)
    end

    i,n = last(context._local.depth_record).for_loop

    if depth > 1
        push!(tree_builder[depth-1],
              quote
                @testset $name (showtiming = false) for $i in $n
                    $(newLocalScopeFor(name, i, concat))
                end
              end
              )
        # Delete last level
        pop!(tree_builder)
    else
        pop!(tree_builder)
        push!(tree_builder, Expr[
            quote
                tt[$name] = (@testset $name (showtiming = false) for $i in $n
                    $(newLocalScopeFor(name, i, concat))
                end)
            end
        ])
    end
end

function updateTestTreeDownwards!(tree_builder :: AbstractArray)
    # Add new level
    push!(tree_builder, Expr[])
end

function updateTestTreeSideways!(context::Context, name::String)

    # Get depth level
    depth = length(context.test_tree_expr_builder)
    @show context._local
    # Add the expression to de tree builder
    push!(context.test_tree_expr_builder[depth],
          newLocalScope(name,
                        quote
                            #TODO?
                            PerfTest.printDepth!(_PRFT_LOCAL[:depth])
                            # Metric calc
                            $(buildPrimitiveMetrics()) # See metrics.jl
                            # Custom metric calc TODO Regulating
                            $(buildCustomMetrics(context._local.custom_metrics))
                            # Methodology evaluation
                            $(buildMemTRPTMethodology(context))
                            $(buildRoofline(context))
                            $(buildRaw(context))

                            PerfTest.printAuxiliaries(_PRFT_LOCAL[:metrics], length(_PRFT_LOCAL[:depth]))
                        end))
end
