module __PERFTEST__
using Test
using PerfTest
PerfTest._perftest_config("[perfcompare]\nenabled = true\n\n[MPI]\nmode = \"reduce\"\nenabled = false\n\n[general]\nrecursive = true\nsave_results = true\nautoflops = true\nsuppress_output = true\nplotting = true\nsave_folder = \".perftests\"\nmax_saved_results = 20\nverbose = true\nlogs_enabled = true\nsafe_formulas = false\n\n[regression]\nenabled = false\ndefault_threshold = 0.05\n\n[roofline]\nenabled = true\ndefault_threshold = 0.5\n\n[memory_bandwidth]\nenabled = true\ndefault_threshold = 0.5\n\n[machine_benchmarking]\nmemory_bandwidth_test_buffer_size = false\n")
function testfun(a::Int)
    c = 1
    for i = 1:a
        c = c + i ^ 2 / c
    end
    return c
end
using Test, Dates
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData
if main_rank()
    path = "./.perftests/ex2-effmemtp.jl_PERFORMANCE.JLD2"
    nofile = true
    if isfile(path)
        nofile = false
        datafile = PerfTest.openDataFile(path)
    else
        datafile = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
        PerfTest.p_yellow("[!]")
        println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
    end
    _PRFT_GLOBALS = GlobalSuiteData(datafile, path, "ex2-effmemtp.jl")
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
TS = @perftestset(PerfTestSet, "FIRST LEVEL", begin
            local ts = Test.get_testset()
            nothing
            TS = @perftestset(PerfTestSet, "SECOND LEVEL", begin

                        local ts = Test.get_testset()
                                  # BENCH
                                 ts.benchmarks["Test 1"] = @PRFTBenchmark(($testfun)(10))
                        test_res = Test_Result("Test 1")
                        ts.test_results["Test 1"] = test_res
                        test_res.primitives[:autoflop] = PRFTflop(@PRFTCount_ops(($testfun)(10)))
                        test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = (x = testfun(10)))
                                  # METRICS
                                  buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                        test_res.metrics[:effMemTP] = newMetricResult(PerfTest.NormalMode, name = "Effective memory throughput", units = "GB/s", value = 2.0 + 5.0, auxiliary = false)
                                  # METHIDOLOGY
                        let
                            reference_benchmark = _PRFT_GLOBALS.builtins[:MEM_STREAM_COPY]
                            value = (test_res.metrics[:effMemTP]).value / reference_benchmark
                            success = value >= 0.01
                            result = newMetricResult(PerfTest.NormalMode, name = "Effective Throughput Ratio", units = "%", value = value * 100)
                            test = Metric_Test(reference = 100, threshold_min_percent = 0.01, threshold_max_percent = 1.0, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = true)
                            aux_abs_value = newMetricResult(PerfTest.NormalMode, name = "Attained Bandwidth", units = "B/s", value = value)
                            aux_ref_value = newMetricResult(PerfTest.NormalMode, name = "Peak empirical bandwidth", units = "B/s", value = reference_benchmark)
                            methodology_res = Methodology_Result(name = "Effective Memory Throughput")
                            push!(methodology_res.metrics, result => test)
                            methodology_res.custom_elements[:abs] = magnitudeAdjust(aux_abs_value)
                            methodology_res.custom_elements[:abs_ref] = magnitudeAdjust(aux_ref_value)
                            if true || !(test.succeeded)
                                PerfTest.printMethodology(methodology_res, 2, true)
                            end
                            saveMethodologyData(test_res.name, methodology_res)
                        end
                                  # PRINT
                        PerfTest.printAuxiliaries(test_res.auxiliar, Test.get_testset_depth())
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
