"""
    Builds the Julia expression that goes after the performance tests, it registers, prints and saves results given the measurements done above it.
"""
function perftestsuffix(context :: Context)
    return quote
        if main_rank($mode)

            #@info TS

            testresdict = Dict{String,Union{Dict,Test_Result}}()
            # A top level `@testset ... for` gives the testset of each iteration, each one is saved under its name and
            # iterator as a nested loop testset is (see extractTestResults), which the regression lookup keys follow
            if TS isa Vector
                benchmarks = PerfTest.newBenchmarkGroup()
                for ts in TS
                    testresdict[ts.description * "_" * string(ts.iterator)] = extractTestResults(ts)
                    benchmarks[ts.description * "_" *string(ts.iterator)] = ts.benchmarks
                end
                # Save new results
                newres = Suite_Execution_Result(
                    timestamp=datetime2unix(now()),
                    elapsed=time() - _t_begin,
                    benchmarks=benchmarks,
                    # Populate new with results of current execution
                    perftests = testresdict
            )
            else
                testresdict[TS.description] = extractTestResults(TS)
                # Save new results
                newres = Suite_Execution_Result(
                    timestamp=datetime2unix(now()),
                    elapsed=time() - _t_begin,
                    benchmarks=TS.benchmarks,
                    # Populate new with results of current execution
                    perftests = testresdict
                )
            end

            # Configuration.CONFIG is here the configuration the suite was generated with, as it stands at this point
            # of the recipe (see treeRun)
            if !PerfTest.testsSucceeded(TS)
                println("Some tests failed or errored.")
            # No fails no errors, regression enabled and different regression file path
            elseif Configuration.CONFIG["general"]["save_results"] && Configuration.CONFIG["regression"]["enabled"] && regression_path != _PRFT_GLOBALS.datafile_path
                println("All performance tests have passed. Values will be registered as reference for regression testing.")
                push!(regression_file.results, newres)
                # Deal with recorded results
                let
                    res_num = length(regression_file.results)
                    if (excess = $(Configuration.CONFIG["general"]["max_saved_results"]) - res_num) <= 0
                        PerfTest.p_yellow("[ℹ]")
                        println(" Regression: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
                        for i in 1:(-1*excess+1)
                            popfirst!(regression_file.results)
                        end
                    end
                end
                PerfTest.saveDataFile(regression_path, regression_file)
            end
            # Kept in memory even when it is not saved, e.g. for the Bencher export below
            push!(_PRFT_GLOBALS.datafile.results, newres)
            if Configuration.CONFIG["general"]["save_results"]
                # Deal with recorded results
                let
                    res_num = length(_PRFT_GLOBALS.datafile.results)

                    if (excess = $(Configuration.CONFIG["general"]["max_saved_results"]) - res_num) <= 0
                        PerfTest.p_yellow("[ℹ]")
                        println(" Results File: Exceeded maximum recorded results. The oldest $(-1*excess + 1) result/s will be removed.")
                        for i in 1:(-1*excess+1)
                            popfirst!(_PRFT_GLOBALS.datafile.results)
                        end
                    end
                end
                # Export as json
                #BencherInterface.exportToJSON(_PRFT_GLOBALS.datafile_path * ".json", newres)
                PerfTest.saveDataFile(_PRFT_GLOBALS.datafile_path, _PRFT_GLOBALS.datafile)
            else
                println("The results of this execution have not been saved (general.save_results is false).")
            end
            println("[✓] $path Performance tests have been finished (elapsed $(newres.elapsed) s)")

            # Bencher export using the REST API
            if Configuration.CONFIG["regression"]["use_bencher"]
                bencher_config = Configuration.CONFIG["bencher"]
                PerfTest.BencherREST.exportSuiteToBencher(_PRFT_GLOBALS.datafile, bencher_config)
            end
            
            PerfTest.clean($mode) 
        end
    end
end
