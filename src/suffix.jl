
### SUFFIX FILLER
function perftextsuffix(context :: Context)
    return quote
        suite = l

        # Deal with recorder results
        res_num = length(data.results)

        if (excess = $(max_saved_results) - res_num) <= 0
            PerfTest.p_yellow("[ℹ]")
            println(" Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
            for i in 1:(-1*excess+1)
                popfirst!(data.results)
            end
        end

        # CALCULATE REFERENCE BENCHMARKS IF NEEDED
        $(if effective_memory_throughput.enabled || roofline.enabled
              setupMemoryBandwidthBenchmark()
        end)
        $(if roofline.enabled
              setupCPUPeakFlopBenchmark()
          end)

        # TODO Inyect globally defined metrics

        # Trial Estimates
        median_suite = median(suite)
        min_suite = minimum(suite)

        # Methodology suffixes
        $(regressionSuffix(context))

        # Compose the serializable data structure for this execution
        current_result = PerfTest.Perftest_Result(timestamp=time(),
            benchmarks=l,
            perftests=Dict())

        push!(data.results, current_result)
        PerfTest.p_yellow("[ℹ]")
        println(" Regression: A perfomance reference has been registered.")
        # TODO
        failed = false
        # Test set hierarchy root
        depth = PerfTest.DepthRecord[]
        current_test_results = Dict{PerfTest.StrOrSym, Any}()
        tt = Dict()
        try
            # Test set hierarchy
            $(context.test_tree_expr_builder[1][1])
        catch e
            @warn "One or more performance tests have failed"
            failed = true
        end

        $(
            if save_test_results
                quote
                    push!(data.methodologies_history, current_test_results)
                end
            end
        )

        if !failed
            PerfTest.saveDataFile(path, data)
        end

        println("[✓] $($(ctx.original_file_path)) Performance tests have been finished")
    end
end
