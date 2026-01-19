
### SUFFIX FILLER
# function perftextsuffix2(context :: Context)
#     return quote
#         suite = _PRFT_LOCAL_SUITE

#         # Deal with recorder results
#         res_num = length(_PRFT_GLOBAL[:datafile].results)

#         if (excess = $(Configuration.CONFIG["max_saved_results"]) - res_num) <= 0
#             PerfTest.p_yellow("[ℹ]")
#             s = " Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed."
#             println(s)
#             addLog("general",s)
#             for i in 1:(-1*excess+1)
#                 popfirst!(_PRFT_GLOBAL[:datafile].results)
#             end
#         end

#         # CALCULATE REFERENCE BENCHMARKS IF NEEDED
#         $(if true # effective_memory_throughput.enabled || roofline.enabled
#               setupMemoryBandwidthBenchmark()
#         end)
#         $(if Configuration.CONFIG["roofline"]["enabled"]
#               setupCPUPeakFlopBenchmark()
#           end)

#         # Trial Estimates
#         median_suite = median(suite)
#         min_suite = minimum(suite)

#         # Methodology suffixes
#         $(regressionSuffix(context))

#         # Compose the serializable data structure for this execution
#         current_result = PerfTest.Perftest_Result(timestamp=time(),
#             benchmarks=l,
#             perftests=Dict())

#         push!(_PRFT_GLOBAL[:datafile].results, current_result)
#         PerfTest.p_yellow("[ℹ]")
#         println(" Regression: A perfomance reference has been registered.")
#         # TODO
#         failed = false
#         # Test set hierarchy root
#         depth = PerfTest.DepthRecord[]
#         current_test_results = Dict{PerfTest.StrOrSym, Any}()
#         tt = Dict()
#         try
#             # Test set hierarchy
#             $(context.test_tree_expr_builder[1][1])
#         catch e
#             @warn "One or more performance tests have failed"
#             failed = true
#         end

#         $(
#             if Configuration.CONFIG["save_results"]
#                 quote
#                     push!(_PRFT_GLOBAL[:datafile].methodologies_history, current_test_results)
#                 end
#             end
#         )

#         if !failed
#             PerfTest.saveDataFile(path, data)
#         end

#         println("[✓] $path Performance tests have been finished")
#     end
# end


function oldperftestsuffix(context :: Context)
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

                if (excess = $(Configuration.CONFIG["general"]["max_saved_results"]) - res_num) <= 0
                    PerfTest.p_yellow("[ℹ]")
                    println(" Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
                    for i in 1:(-1*excess+1)
                        popfirst!(_PRFT_GLOBAL[:datafile].results)
                    end
                end

                if length(_PRFT_GLOBAL[:datafile].results) > 0
                    _PRFT_GLOBAL[:old] = _PRFT_GLOBAL[:datafile].results[end].perftests
                else
                    _PRFT_GLOBAL[:old] = nothing
                end
                _PRFT_GLOBAL[:new] = Dict{String,Union{Dict, Test_Result}}()
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
            # Save new results
            newres = Suite_Execution_Result(
                timestamp= datetime2unix(now()),
                benchmarks = _PRFT_GLOBAL[:suite],
                perftests = _PRFT_GLOBAL[:new]
            )
            push!(_PRFT_GLOBAL[:datafile].results, newres)

            if !failed
                PerfTest.saveDataFile(path, _PRFT_GLOBAL[:datafile])
            end
            println("[✓] $path Performance tests have been finished")
        end

    end
end

function perftestsuffix(context :: Context)
    return quote
        if main_rank()
            # Deal with recorder results
            let
                res_num = length(_PRFT_GLOBALS.datafile.results)

                if (excess = $(Configuration.CONFIG["general"]["max_saved_results"]) - res_num) <= 0
                    PerfTest.p_yellow("[ℹ]")
                    println(" Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
                    for i in 1:(-1*excess+1)
                        popfirst!(_PRFT_GLOBALS.datafile.results)
                    end
                end

            end

            testresdict = Dict{String,Union{Dict,Test_Result}}()
            testresdict[TS.description] = extractTestResults(TS)
            # Save new results
            newres = Suite_Execution_Result(
                timestamp=datetime2unix(now()),
                benchmarks=TS.benchmarks,
                # Populate new with results of current execution
                perftests = testresdict
            )
            push!(_PRFT_GLOBALS.datafile.results, newres)

            # No fails no errors
            if sum(Test.get_test_counts(TS)[2:3]) == 0
                PerfTest.saveDataFile(_PRFT_GLOBALS.datafile_path, _PRFT_GLOBALS.datafile)
                # Export as json
                #BencherInterface.exportToJSON(_PRFT_GLOBALS.datafile_path * ".json", newres)
            end
            println("[✓] $path Performance tests have been finished")

            # Bencher export using the REST API
            if Configuration.CONFIG["regression"]["use_bencher"]
                bencher_config = Configuration.CONFIG["bencher"]
                PerfTest.BencherREST.exportSuiteToBencher(_PRFT_GLOBALS.datafile, bencher_config)
            end
        end
    end
end
