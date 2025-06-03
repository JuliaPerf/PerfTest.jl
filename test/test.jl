module __PERFTEST__
using Test
using PerfTest
using Test, Dates
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData
if main_rank()
    path = "./.perftests/ex5-recursive.jl_PERFORMANCE.JLD2"
    nofile = true
    if isfile(path)
        nofile = false
        datafile = PerfTest.openDataFile(path)
    else
        datafile = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
        PerfTest.p_yellow("[!]")
        println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
    end
    _PRFT_GLOBALS = GlobalSuiteData(datafile, path, "ex5-recursive.jl")
    MPISetup(PerfTest.NormalMode, _PRFT_GLOBALS)
end
let
    size = try
            CpuId.cachesize()
        catch
            addLog("machine", "[MACHINE] CpuId failed, using default cache size")
            [1024 * 1024 * 16]
        end
    global _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = size
    addLog("machine", "[MACHINE] Memory buffer size for benchmarking = $((size ./ 1024) ./ 1024) [MB]")
    measureCPUPeakFlops!(PerfTest.NormalMode, _PRFT_GLOBALS)
    measureMemBandwidth!(PerfTest.NormalMode, _PRFT_GLOBALS)
end
TS = @perftestset(PerfTestSet, "RECURSIVE", begin
            local ts = Test.get_testset()
            using Test
            using PerfTest
            function testfun(a::Int)
                sleep(1)
            end
            nothing
            TS = @perftestset(PerfTestSet, "FIRST LEVEL", begin
                        local ts = Test.get_testset()
                        nothing
                        TS = @perftestset(PerfTestSet, "SECOND LEVEL", begin
                                    local ts = Test.get_testset()
                                    PerfTest.MethodologyParameters[PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#225") => :(:median_time < 3))), PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#226") => :(:median_time < 5)))]
                                    PerfTest.MethodologyParameters[PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#225") => :(:median_time < 3))), PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#226") => :(:median_time < 5)))]
                                    x = begin
                                            ts.benchmarks["Test 1"] = @PRFTBenchmark(($testfun)(10))
                                            test_res = Test_Result("Test 1")
                                            ts.test_results["Test 1"] = test_res
                                            test_res.primitives[:autoflop] = PRFTflop(@PRFTCount_ops(($testfun)(10)))
                                            test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = testfun(10))
                                            buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                                            let
                                                methodology_res = Methodology_Result(name = "Performance Assertion")
                                                all_succeeded = true
                                                metric = newMetricResult(PerfTest.NormalMode, name = ":(:median_time < 5)", units = "bool", value = test_res.primitives[:median_time] < 5)
                                                success = metric.value
                                                test = Metric_Test(reference = 0, threshold_min_percent = 1.0, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = false)
                                                push!(methodology_res.metrics, metric => test)
                                                all_succeeded &= success
                                                metric = newMetricResult(PerfTest.NormalMode, name = ":(:median_time < 3)", units = "bool", value = test_res.primitives[:median_time] < 3)
                                                success = metric.value
                                                test = Metric_Test(reference = 0, threshold_min_percent = 1.0, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = false)
                                                push!(methodology_res.metrics, metric => test)
                                                all_succeeded &= success
                                                for (r, test) = methodology_res.metrics
                                                end
                                                saveMethodologyData(test_res.name, methodology_res)
                                            end
                                            PerfTest.printAuxiliaries(test_res.auxiliar, Test.get_testset_depth())
                                            nothing
                                        end
                                    nothing
                                end)
                        nothing
                        nothing
                    end)
            nothing
            nothing
            TS = @perftestset(PerfTestSet, "RECURSIVE 2", begin
                        local ts = Test.get_testset()
                        using Test
                        using PerfTest
                        function testfun(a::Int)
                            sleep(1)
                        end
                        nothing
                        TS = @perftestset(PerfTestSet, "FIRST LEVEL", begin
                                    local ts = Test.get_testset()
                                    nothing
                                    TS = @perftestset(PerfTestSet, "SECOND LEVEL", begin
                                                local ts = Test.get_testset()
                                                PerfTest.MethodologyParameters[PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#227") => :(:median_time < 3))), PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#228") => :(:median_time < 5)))]
                                                PerfTest.MethodologyParameters[PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#227") => :(:median_time < 3))), PerfTest.MethodologyParameters(:perfcmp, "@perfcompare Testing", false, Dict{Symbol, Any}(Symbol("##expr#228") => :(:median_time < 5)))]
                                                x = begin
                                                        ts.benchmarks["Test 1"] = @PRFTBenchmark(($testfun)(10))
                                                        test_res = Test_Result("Test 1")
                                                        ts.test_results["Test 1"] = test_res
                                                        test_res.primitives[:autoflop] = PRFTflop(@PRFTCount_ops(($testfun)(10)))
                                                        test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = testfun(10))
                                                        buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                                                        let
                                                            methodology_res = Methodology_Result(name = "Performance Assertion")
                                                            all_succeeded = true
                                                            metric = newMetricResult(PerfTest.NormalMode, name = ":(:median_time < 3)", units = "bool", value = test_res.primitives[:median_time] < 3)
                                                            success = metric.value
                                                            test = Metric_Test(reference = 0, threshold_min_percent = 1.0, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = false)
                                                            push!(methodology_res.metrics, metric => test)
                                                            all_succeeded &= success
                                                            metric = newMetricResult(PerfTest.NormalMode, name = ":(:median_time < 5)", units = "bool", value = test_res.primitives[:median_time] < 5)
                                                            success = metric.value
                                                            test = Metric_Test(reference = 0, threshold_min_percent = 1.0, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = false)
                                                            push!(methodology_res.metrics, metric => test)
                                                            all_succeeded &= success
                                                            for (r, test) = methodology_res.metrics
                                                            end
                                                            saveMethodologyData(test_res.name, methodology_res)
                                                        end
                                                        PerfTest.printAuxiliaries(test_res.auxiliar, Test.get_testset_depth())
                                                        nothing
                                                    end
                                                nothing
                                            end)
                                    nothing
                                    nothing
                                end)
                        nothing
                        nothing
                    end)
            nothing
            nothing
        end)
if main_rank()
    let
        res_num = length(_PRFT_GLOBALS.datafile.results)
        if (excess = 20 - res_num) <= 0
            PerfTest.p_yellow("[ℹ]")
            println(" Regression: Exceeded maximum recorded results. The oldest $(-1 * excess + 1) result/s will be removed.")
            for i = 1:-1 * excess + 1
                popfirst!(_PRFT_GLOBALS.datafile.results)
            end
        end
        if length(_PRFT_GLOBALS.datafile.results) > 0
            _PRFT_GLOBALS.old = (_PRFT_GLOBALS.datafile.results[end]).perftests
        else
            _PRFT_GLOBALS.old = nothing
        end
    end
    newres = Suite_Execution_Result(timestamp = datetime2unix(now()), benchmarks = TS.benchmarks, perftests = extractTestResults(TS))
    push!(_PRFT_GLOBALS.datafile.results, newres)
    if sum((Test.get_test_counts(TS))[2:3]) == 0
        PerfTest.saveDataFile(_PRFT_GLOBALS.datafile_path, _PRFT_GLOBALS.datafile)
    end
    println("[✓] $(path) Performance tests have been finished")
end
end