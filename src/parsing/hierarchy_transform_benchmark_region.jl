function testsetToBenchGroup!(input_expr :: Expr, context :: Context)
    # Get the elements of interest from the macrocall
    @capture(input_expr, @testset properties__ test_block_) ? Nothing : error("Incompatible testset syntax \n");

    # Get the name from the list of elements of the testset macrocall
    name = metaGetString(properties);

    # Check if there is a for loop over the testset
    theres_for = @capture(test_block, for a_ in b_
        inner_block_
    end)

    # Update context: add depth level
    rec = DepthEntry(name, theres_for ? Pair(a,b) : nothing, 0)
    push!(context._local.depth_record, rec)
    push!(context._local.custom_metrics, CustomMetric[])
    push!(context._local.enabled_methodologies, MethodologyParameters[])

    # Update context: add new level to the tree
    updateTestTreeDownwards!(context.test_tree_expr_builder)

    if theres_for
        @capture(test_block, for a_ in b_
            inner_block_
        end)

        return length(context._local.depth_record) > 1 ?
            :(
            for $a in $b
                # For a s
                _PRFT_LOCAL_SUITE[$name * "_" * string($a)] = BenchmarkGroup();
                _PRFT_LOCAL_ADDITIONAL[$name * "_" * string($a)] = Dict();
                _PRFT_LOCAL_ADDITIONAL[$name * "_" * string($a)][:iterator] = $a;
                let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE[$name * "_" * string($a)], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL[$name * "_" * string($a)]
                    $inner_block
                end;
                :__BACK_CONTEXT__;
            end;
        ) :
            :(
            :__PERFTEST_FW__;
            for $a in $b
                _PRFT_LOCAL_SUITE[$name * "_" * string($a)] = BenchmarkGroup();
                _PRFT_LOCAL_ADDITIONAL[$name * "_" * string($a)] = Dict();
                let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE[$name * "_" * string($a)], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL[$name * "_" * string($a)]
                    $inner_block
                end;
                :__BACK_CONTEXT__;
            end;
        )
    else
        # Return the substitution
        return length(context._local.depth_record) > 1 ?
               :(
            _PRFT_LOCAL_SUITE[$name] = BenchmarkGroup();
            _PRFT_LOCAL_ADDITIONAL[$name] = Dict();
            let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE[$name], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL[$name]
                $test_block
            end;

            :__BACK_CONTEXT__
        ) :
               :(
            :__PERFTEST_FW__;

            _PRFT_LOCAL_SUITE[$name] = BenchmarkGroup();
            _PRFT_LOCAL_ADDITIONAL[$name] = Dict();
            let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE[$name], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL[$name]
                $test_block
            end;

            :__BACK_CONTEXT__
        )
    end
end

function backTokenToContextUpdate!(input_expr ::QuoteNode, context::Context)

    if CONFIG.recursive && context._global.in_recursion && length(context._local.depth_record) == 1
        return nothing;
    end

    # Check if inside a for loop
    if last(context._local.depth_record).for_loop !== nothing
        # Update context: consolidate tree level
        updateTestTreeUpwardsFor!(context.test_tree_expr_builder,
                           context._local.depth_record[end].set_name, context)
    else
        updateTestTreeUpwards!(context.test_tree_expr_builder,
                           context._local.depth_record[end].set_name)
    end
    # Update context: delete depth level
    pop!(context._local.depth_record)
    pop!(context._local.custom_metrics)
    pop!(context._local.enabled_methodologies)

    return nothing;
end

function perftestToBenchmark!(input_expr::Expr, context::Context)
    # Get the elements of interest from the macrocall
    @capture(input_expr, @perftest prop__ expr_)
    @show context._local.depth_record[end]
    num = (context._local.depth_record[end].test_count += 1)
    name = "Test $num"

    # Update context: create expression on tree builder
    updateTestTreeSideways!(context, name)

    parsed_target = parseTarget(expr, context)

    iterator = let loop = (context._local.depth_record[end]).for_loop
        loop isa Nothing ? nothing : loop.first
    end

    # Return the substitution and setup the in target flag deactivator
    return quote
        _PRFT_LOCAL_ADDITIONAL[$name] = Dict()
        _PRFT_LOCAL_ADDITIONAL[$name][:iterator] = $(iterator)
        $(if CONFIG.suppress_output
              quote
              @suppress begin
                  _PRFT_LOCAL_SUITE[$name] = @benchmark($(prop...), ($parsed_target));
                  _PRFT_LOCAL_ADDITIONAL[$name][:autoflop] = $(
                      if CONFIG.autoflops
                          quote CountFlops.flop(@count_ops ($parsed_target)) end
                      else
                          quote 0 end
                      end
                  )
              end
              end
          else
              quote
                  _PRFT_LOCAL_SUITE[$name] = @benchmark($(prop...), ($parsed_target));
                  _PRFT_LOCAL_ADDITIONAL[$name][:autoflop] = $(
                      if CONFIG.autoflops
                          quote CountFlops.flop(@count_ops ($parsed_target)) end
                      else
                          quote 0 end
                      end
                  )
              end
          end)

        _PRFT_LOCAL_ADDITIONAL[$name][:printed_output] =
            @capture_out _PRFT_LOCAL_ADDITIONAL[$name][:ret_value] = $expr;
        @show _PRFT_LOCAL_ADDITIONAL[$name][:autoflop]
    end
end

