

function transformTestset(input_expr::Expr, context::Context)
    # Get the elements of interest from the macrocall
    @capture(input_expr, @testset properties__ test_block_) || error("Incompatible testset syntax")

    # Get depth level
    depth = length(context.test_tree_expr_builder)

    # Concatenate expressions of the current level into a new node on the upper level
    concat = :(begin end)


    # for expr in context.test_tree_expr_builder[depth]
    #     concat = :($concat; $expr)
    # end

    # Get the name from the list of elements of the testset macrocall
    name = metaGetString(properties)

    # Check if there is a for loop over the testset
    has_for_loop = @capture(test_block, for a_ in b_
        inner_block_
    end)

    # TODO Transform the inner block
    #transformed_block = transformBlock(has_for_loop ? inner_block : test_block, context)

    # Update context tracking
    push!(context._local.depth_record, DepthEntry(name, has_for_loop ? Pair(a, b) : nothing, 0))
    push!(context._local.custom_metrics, CustomMetric[])
    push!(context._local.enabled_methodologies, MethodologyParameters[])

    # LOGINFO
    addLog("hierarchy", "[BNCH] New Group: $([i.set_name for i in context._local.depth_record])")

    # Launch regression methodology by default
    onRegressionDefinition(quote end, context, Dict())

    outerset = length(context._local.depth_record) <= 1

    if has_for_loop
        result = quote
            $(outerset ? :(:__PERFTEST_FW__) : begin end)

            TS = @perftestset PerfTestSet $name  for $a in $b
                local ts = Test.get_testset()
                ts.iterator = $a

                # The code inside the testset
                $inner_block
                :__BACK_CONTEXT__
            end
            $(outerset ? :(:__PERFTEST_AFTER__) : begin end)
        end
    else
        result = quote
            $(outerset ? :(:__PERFTEST_FW__) : begin end)
            TS = @perftestset PerfTestSet $name  begin
                local ts = Test.get_testset()

                # The code inside the testset
                $test_block
                :__BACK_CONTEXT__
            end
            $(outerset ? :(:__PERFTEST_AFTER__) : begin end)
        end
    end

    return result
end


function transformPerftest(input_expr::Expr, context::Context)
    # Get the elements of interest from the macrocall
    @capture(input_expr, @perftest prop__ expr_)

    # Parse the target expression, this spawns a specialized AST walker
    parsed_target = parseTarget(expr, context)

    # Create a unique name for this test
    num = (context._local.depth_record[end].test_count += 1)
    name = "Test $num"

    # LOGINFO
    addLog("hierarchy", "[BNCH] New Test: $name \"$expr\" @ $([i.set_name for i in context._local.depth_record])")
    # Return the transformed expression, in the following quote ts means the current testset
    return quote
        # Run the benchmark
        ts.benchmarks[$name] = @PRFTBenchmark($(prop...), ($parsed_target))

        # Create Test_Result struct to save test data
        test_res = Test_Result($name)
        ts.test_results[$name] = test_res

        # Store additional data
        test_res.primitives[:autoflop] = $(
            if Configuration.CONFIG["general"]["autoflops"]
                quote
                    PRFTflop(@PRFTCount_ops ($parsed_target))
                end
            else
                quote
                    0
                end
            end
        )

        # Capture output and return value
        test_res.primitives[:printed_output] =
            @PRFTCapture_out test_res.primitives[:ret_value] = $expr


        # Calculate metric snapshot
        buildPrimitiveMetrics!($mode, ts, test_res)
        $(buildCustomMetrics(context._local.custom_metrics))


        # Compute performance test based on enabled methodologies
        $(buildMemTRPTMethodology(context))
        $(buildRoofline(context))
        $(buildPerfcmp(context))
        $(buildRegression(context))

        PerfTest.printAuxiliaries(test_res.auxiliar, Test.get_testset_depth());

        nothing
    end
end
