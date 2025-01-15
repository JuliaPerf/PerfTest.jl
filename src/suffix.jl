
### SUFFIX FILLER
function perftextsuffix2(context :: Context)
    return quote
        suite = _PRFT_LOCAL_SUITE

        # Deal with recorder results
        res_num = length(_PRFT_GLOBAL[:datafile].results)

        if (excess = $(CONFIG.max_saved_results) - res_num) <= 0
            PerfTest.p_yellow("[ℹ]")
            println(" Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
            for i in 1:(-1*excess+1)
                popfirst!(_PRFT_GLOBAL[:datafile].results)
            end
        end

        # CALCULATE REFERENCE BENCHMARKS IF NEEDED
        $(if true # effective_memory_throughput.enabled || roofline.enabled
              setupMemoryBandwidthBenchmark()
        end)
        $(if CONFIG.roofline.enabled
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

        push!(_PRFT_GLOBAL[:datafile].results, current_result)
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
            if CONFIG.save_test_results
                quote
                    push!(_PRFT_GLOBAL[:datafile].methodologies_history, current_test_results)
                end
            end
        )

        if !failed
            PerfTest.saveDataFile(path, data)
        end

        println("[✓] $path Performance tests have been finished")
    end
end


function perftestsuffix(context :: Context)
    @show "A"
    return quote
        # Local scope on the lowest level == Global scope
        _PRFT_GLOBAL[:suite] = _PRFT_LOCAL_SUITE
        _PRFT_GLOBAL[:additional] = _PRFT_LOCAL_ADDITIONAL

                # TODO Inyect globally defined metrics

        # Trial Estimates
        #median_suite = median(_PRFT_GLOBAL[:suite])
        #min_suite = minimum(_PRFT_GLOBAL[:suite])

        # Methodology suffixes
        #$(regressionSuffix(context))
        
        if _PRFT_GLOBAL[:is_main_rank]
            # Deal with recorder results
            let
                res_num = length(_PRFT_GLOBAL[:datafile].results)

                if (excess = $(CONFIG.max_saved_results) - res_num) <= 0
                    PerfTest.p_yellow("[ℹ]")
                    println(" Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
                    for i in 1:(-1*excess+1)
                        popfirst!(_PRFT_GLOBAL[:datafile].results)
                    end
                end
            end




            # Compose the serializable data structure for this execution
            let
                current_result = PerfTest.Perftest_Result(timestamp=time(),
                                                        benchmarks=_PRFT_GLOBAL[:suite],
                                                        perftests=Dict())

                push!(_PRFT_GLOBAL[:datafile].results, current_result)
                PerfTest.p_yellow("[ℹ]")
            end
        end
        
        #println(" Regression: A perfomance reference has been registered.")
        # TODO free vars
        failed = false
        # Test set hierarchy root
        _PRFT_LOCAL = Dict{StrOrSym,Any}()
        _PRFT_LOCAL[:depth] = PerfTest.DepthRecord[]
        _PRFT_LOCAL[:results] = Dict{PerfTest.StrOrSym,Any}()
        _PRFT_LOCAL[:additional] = _PRFT_GLOBAL[:additional]
        _PRFT_LOCAL[:suite] = _PRFT_GLOBAL[:suite]
        tt = Dict()
        try
            # HERE THE TESTSETS ARE PUT - Test set hierarchy
            $(context.test_tree_expr_builder[1][1])
        catch e
            @warn "One or more performance tests have failed"
            failed = true
        end

        if _PRFT_GLOBAL[:is_main_rank]
            $(
                if CONFIG.save_test_results
                    quote
                        push!(_PRFT_GLOBAL[:datafile].methodologies_history, current_test_results)
                    end
                end
            )

            if !failed
                PerfTest.saveDataFile(path, _PRFT_GLOBAL[:datafile])
            end
            println("[✓] $path Performance tests have been finished")
        end

    end
end
