module __PERFTEST__
using Test
using PerfTest
using Pkg
using Pardiso
using Random
using SparseArrays
using LinearAlgebra
using MatrixMarket
ps = PardisoSolver()
set_msglvl!(ps, 1)
function build_sparse_matrix(nx, ny, nz, hx2, hy2, hz2)
    data = Float64[]
    row_indices = Int[]
    col_indices = Int[]
    for j = 0:ny - 1
        for i = 0:nx - 1
            for k = 0:nz - 1
                row = k * nx * ny + j * nx + i + 1
                if k > 0
                    col = (k - 1) * nx * ny + j * nx + i + 1
                    push!(data, -hz2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end
                if i > 0
                    col = k * nx * ny + j * nx + (i - 1) + 1
                    push!(data, -hx2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end
                if j > 0
                    col = k * nx * ny + (j - 1) * nx + i + 1
                    push!(data, -hy2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end
                push!(data, 2 * (hx2 + hy2 + hz2))
                push!(row_indices, row)
                push!(col_indices, row)
                if k < nz - 1
                    col = (k + 1) * nx * ny + j * nx + i + 1
                    push!(data, -hz2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end
                if i < nx - 1
                    col = k * nx * ny + j * nx + (i + 1) + 1
                    push!(data, -hx2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end
                if j < ny - 1
                    col = k * nx * ny + (j + 1) * nx + i + 1
                    push!(data, -hy2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end
            end
        end
    end
    sparse(row_indices, col_indices, data)
end
using Test, Dates
nothing
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData, Configuration
_t_begin = time()
if main_rank(PerfTest.NormalMode)
    path = "./.perftests/pardisotest.jl_PERFORMANCE.JLD2"
    nofile = true
    if isfile(path)
        nofile = false
        datafile = PerfTest.openDataFile(path)
    else
        datafile = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
    end
    regression_path = (Configuration.CONFIG["regression"])["dedicated_reference_file"]
    if regression_path != "" && isfile(regression_path)
        regression_file = PerfTest.openDataFile(regression_path)
    else
        if regression_path != ""
            regression_file = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
        else
            regression_file = datafile
            regression_path = path
        end
    end
    _PRFT_GLOBALS = GlobalSuiteData(datafile, path, "pardisotest.jl")
    if length(regression_file.results) > 0
        for i = length(regression_file.results):-1:1
            if length(retrievePerfTests(regression_path, get = :tests, where_pred = testFailed, execution = i)) == 0
                _PRFT_GLOBALS.old = (regression_file.results[i]).perftests
                println("Regression: Previous performance reference for this configuration has been found, regression tests could be performed. Regression is currenctly $(if true
    "enabled"
else
    "disabled"
end)).")
                break
            end
        end
    else
        _PRFT_GLOBALS.old = nothing
    end
else
    _PRFT_GLOBALS = GlobalSuiteData()
end
let
    PerfTest.Topology.getMachineTopology!()
    _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = PerfTest.Topology.getCacheSizes()
    measureCPUPeakFlops!(PerfTest.NormalMode, _PRFT_GLOBALS)
    measureMemBandwidth!(PerfTest.NormalMode, _PRFT_GLOBALS)
end
TS = @perftestset(PerfTestSet, "Pardiso GFLOP tests", begin
            local ts = Test.get_testset()
            ts.old_test_results = _PRFT_GLOBALS.old
            nothing
            TS = @perftestset(PerfTestSet, "Laplace for different N", for N = [i for i = [40, 42, 45, 47, 50, 52, 55, 57, 60]]
                        local ts = Test.get_testset()
                        ts.iterator = N
                        nothing
                        A = build_sparse_matrix(N, N, N, (N - 1) ^ 3, (N - 1) ^ 3, (N - 1) ^ 3)
                        x = zeros(Float64, N ^ 3)
                        b = zeros(Float64, N ^ 3)
                        nothing
                        set_phase!(ps, 11)
                        pardiso(ps, x, A, b)
                        set_phase!(ps, 22)
                        ts.benchmarks["Test 1"] = @PRFTBenchmark(($pardiso)($ps, $x, $A, $b), samples = 5)
                        test_res = Test_Result("Test 1")
                        ts.test_results["Test 1"] = test_res
                        keys = ["Pardiso GFLOP tests", "Laplace for different N"]
                        append!(keys, ["Test 1"])
                        old_test_res = _PRFT_GLOBALS.old
                        for key = keys
                            if !(old_test_res isa Nothing) && haskey(old_test_res, key)
                                old_test_res = old_test_res[key]
                            else
                                old_test_res = nothing
                                break
                            end
                        end
                        test_res.primitives[:autoflop] = PRFTflop(@PRFTCount_ops(($pardiso)($ps, $x, $A, $b)))
                        test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = pardiso(ps, x, A, b))
                        buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                        let m = newMetricResult(PerfTest.NormalMode, name = "Operational intensity", units = "Flop/Byte", value = begin
                                            flop = 1.0e9 * PerfTest.grepOutputXGetNumber(test_res.primitives[:printed_output], "Gflop   for the numerical factorization:")
                                            mem = sizeof(Float64) * PerfTest.grepOutputXGetNumber(test_res.primitives[:printed_output], "number of nonzeros in L")
                                            flop / mem
                                        end, auxiliary = false)
                            test_res.metrics[:opInt] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Attained Flops", units = "FLOP/s", value = (flop = 1.0e9 * PerfTest.grepOutputXGetNumber(test_res.primitives[:printed_output], "Gflop   for the numerical factorization:")) / test_res.primitives[:median_time], auxiliary = false)
                            test_res.metrics[:attainedFLOPS] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "OUT", units = "String", value = test_res.primitives[:printed_output], auxiliary = true)
                            test_res.auxiliar[:OUT] = m
                        end
                        if main_rank(PerfTest.NormalMode)
                            let
                                opint = (test_res.metrics[:opInt]).value
                                flop_s = (test_res.metrics[:attainedFLOPS]).value
                                flop_peak = _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]
                                mem_peak = _PRFT_GLOBALS.builtins[:MEM_BENCH_SDAXPY]
                                nothing
                                roof = PerfTest.rooflineCalc(flop_peak, mem_peak)
                                result_flop_ratio = newMetricResult(PerfTest.NormalMode, name = "Attained FLOP/S by expected FLOP/S", units = "%", value = (flop_s / roof(opint)) * 100)
                                methodology_res = Methodology_Result(name = "Roofline Model")
                                success_flop = result_flop_ratio.value >= 0.4 * 100
                                flop_test = Metric_Test(reference = 100, threshold_min_percent = 0.4 * 100, threshold_max_percent = nothing, low_is_bad = true, succeeded = success_flop, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result_flop_ratio => flop_test)
                                methodology_res.custom_elements[:realf] = magnitudeAdjust(test_res.metrics[:attainedFLOPS])
                                methodology_res.custom_elements[:opint] = test_res.metrics[:opInt]
                                aux_mem = newMetricResult(PerfTest.NormalMode, name = "Peak empirical bandwidth", units = "B/s", value = mem_peak)
                                aux_flops = newMetricResult(PerfTest.NormalMode, name = "Peak empirical flops", units = "FLOP/s", value = flop_peak)
                                aux_rcorner = newMetricResult(PerfTest.NormalMode, name = "Roofline Corner", units = "Flop/Byte", value = aux_flops.value / aux_mem.value)
                                methodology_res.custom_elements[:mem_peak] = magnitudeAdjust(aux_mem)
                                methodology_res.custom_elements[:cpu_peak] = magnitudeAdjust(aux_flops)
                                methodology_res.custom_elements[:roof_corner] = magnitudeAdjust(aux_rcorner)
                                methodology_res.custom_elements[:roof_corner_raw] = aux_rcorner
                                methodology_res.custom_elements[:factor] = 0.4
                                methodology_res.custom_elements[:plot] = PerfTest.printFullRoofline
                                try
                                    PerfTest.@_prftest flop_test.succeeded
                                    saveMethodologyData(test_res.name, methodology_res)
                                catch e
                                    @error "Roofline test failed with error: $(e)"
                                end
                            end
                            let
                                methodology_res = Methodology_Result(name = "Performance Regression Testing")
                                all_succeeded = true
                                if haskey(test_res.metrics, :median_time) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :median_time))
                                    ratio = (test_res.metrics[:median_time]).value / (old_test_res.metrics[:median_time]).value
                                    success = ratio < 1.1
                                    result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio * 100)
                                    test = Metric_Test(reference = 100.0, threshold_min_percent = 1.1 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                    push!(methodology_res.metrics, result => test)
                                    methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:median_time]).name, units = (test_res.metrics[:median_time]).units, value = (test_res.metrics[:median_time]).value) => test
                                    all_succeeded &= success
                                elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :median_time)) && (haskey(test_res.primitives, :median_time) && haskey(old_test_res.primitives, :median_time)))
                                    ratio = test_res.primitives[:median_time] / old_test_res.primitives[:median_time]
                                    success = ratio < 1.1
                                    result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio * 100)
                                    test = Metric_Test(reference = 100.0, threshold_min_percent = 1.1 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                    push!(methodology_res.metrics, result => test)
                                    methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = ":median_time", units = "s", value = test_res.primitives[:median_time]) => test
                                    all_succeeded &= success
                                end
                                if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                    methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":median_time Reference value", units = if haskey(old_test_res.metrics, :median_time)
                                                    (old_test_res.metrics[:median_time]).units
                                                else
                                                    "s"
                                                end, value = if haskey(old_test_res.metrics, :median_time)
                                                    (old_test_res.metrics[:median_time]).value
                                                else
                                                    if haskey(old_test_res.primitives, :median_time)
                                                        old_test_res.primitives[:median_time]
                                                    else
                                                        NaN
                                                    end
                                                end)
                                end
                                methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = ":median_time", units = if haskey(test_res.metrics, :median_time)
                                                (test_res.metrics[:median_time]).units
                                            else
                                                "s"
                                            end, value = if haskey(test_res.metrics, :median_time)
                                                (test_res.metrics[:median_time]).value
                                            else
                                                if haskey(test_res.primitives, :median_time)
                                                    test_res.primitives[:median_time]
                                                else
                                                    NaN
                                                end
                                            end)
                                for (r, test) = methodology_res.metrics
                                    PerfTest.@_prftest test.succeeded
                                end
                                saveMethodologyData(test_res.name, methodology_res)
                            end
                        end
                        nothing
                    end)
            nothing
            nothing
            TS = @perftestset(PerfTestSet, "Custom matrix", for mat = ["af_0_k101/af_0_k101.mtx", "af_shell3/af_shell3.mtx", "pkustk10/pkustk10.mtx", "pkustk11/pkustk11.mtx", "pkustk12/pkustk12.mtx", "pkustk13/pkustk13.mtx", "pkustk14/pkustk14.mtx"]
                        local ts = Test.get_testset()
                        ts.iterator = mat
                        nothing
                        A = SparseMatrixCSC{Float64}(mmread(mat))
                        x = zeros(Float64, size(A, 1))
                        b = zeros(Float64, size(A, 1))
                        nothing
                        set_phase!(ps, 11)
                        pardiso(ps, x, A, b)
                        set_phase!(ps, 22)
                        ts.benchmarks["Test 1"] = @PRFTBenchmark(($pardiso)($ps, $x, $A, $b), samples = 20)
                        test_res = Test_Result("Test 1")
                        ts.test_results["Test 1"] = test_res
                        keys = ["Pardiso GFLOP tests", "Custom matrix"]
                        append!(keys, ["Test 1"])
                        old_test_res = _PRFT_GLOBALS.old
                        for key = keys
                            if !(old_test_res isa Nothing) && haskey(old_test_res, key)
                                old_test_res = old_test_res[key]
                            else
                                old_test_res = nothing
                                break
                            end
                        end
                        test_res.primitives[:autoflop] = PRFTflop(@PRFTCount_ops(($pardiso)($ps, $x, $A, $b)))
                        test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = pardiso(ps, x, A, b))
                        buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                        let m = newMetricResult(PerfTest.NormalMode, name = "Operational intensity", units = "Flop/Byte", value = begin
                                            flop = 1.0e9 * PerfTest.grepOutputXGetNumber(test_res.primitives[:printed_output], "Gflop   for the numerical factorization:")
                                            mem = sizeof(Float64) * PerfTest.grepOutputXGetNumber(test_res.primitives[:printed_output], "number of nonzeros in L")
                                            flop / mem
                                        end, auxiliary = false)
                            test_res.metrics[:opInt] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Attained Flops", units = "FLOP/s", value = (flop = 1.0e9 * PerfTest.grepOutputXGetNumber(test_res.primitives[:printed_output], "Gflop   for the numerical factorization:")) / test_res.primitives[:median_time], auxiliary = false)
                            test_res.metrics[:attainedFLOPS] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "OUT", units = "String", value = test_res.primitives[:printed_output], auxiliary = true)
                            test_res.auxiliar[:OUT] = m
                        end
                        if main_rank(PerfTest.NormalMode)
                            let
                                opint = (test_res.metrics[:opInt]).value
                                flop_s = (test_res.metrics[:attainedFLOPS]).value
                                flop_peak = _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]
                                mem_peak = _PRFT_GLOBALS.builtins[:MEM_BENCH_SDAXPY]
                                nothing
                                roof = PerfTest.rooflineCalc(flop_peak, mem_peak)
                                result_flop_ratio = newMetricResult(PerfTest.NormalMode, name = "Attained FLOP/S by expected FLOP/S", units = "%", value = (flop_s / roof(opint)) * 100)
                                methodology_res = Methodology_Result(name = "Roofline Model")
                                success_flop = result_flop_ratio.value >= 0.4 * 100
                                flop_test = Metric_Test(reference = 100, threshold_min_percent = 0.4 * 100, threshold_max_percent = nothing, low_is_bad = true, succeeded = success_flop, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result_flop_ratio => flop_test)
                                methodology_res.custom_elements[:realf] = magnitudeAdjust(test_res.metrics[:attainedFLOPS])
                                methodology_res.custom_elements[:opint] = test_res.metrics[:opInt]
                                aux_mem = newMetricResult(PerfTest.NormalMode, name = "Peak empirical bandwidth", units = "B/s", value = mem_peak)
                                aux_flops = newMetricResult(PerfTest.NormalMode, name = "Peak empirical flops", units = "FLOP/s", value = flop_peak)
                                aux_rcorner = newMetricResult(PerfTest.NormalMode, name = "Roofline Corner", units = "Flop/Byte", value = aux_flops.value / aux_mem.value)
                                methodology_res.custom_elements[:mem_peak] = magnitudeAdjust(aux_mem)
                                methodology_res.custom_elements[:cpu_peak] = magnitudeAdjust(aux_flops)
                                methodology_res.custom_elements[:roof_corner] = magnitudeAdjust(aux_rcorner)
                                methodology_res.custom_elements[:roof_corner_raw] = aux_rcorner
                                methodology_res.custom_elements[:factor] = 0.4
                                methodology_res.custom_elements[:plot] = PerfTest.printFullRoofline
                                try
                                    PerfTest.@_prftest flop_test.succeeded
                                    saveMethodologyData(test_res.name, methodology_res)
                                catch e
                                    @error "Roofline test failed with error: $(e)"
                                end
                            end
                            let
                                methodology_res = Methodology_Result(name = "Performance Regression Testing")
                                all_succeeded = true
                                if haskey(test_res.metrics, :median_time) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :median_time))
                                    ratio = (test_res.metrics[:median_time]).value / (old_test_res.metrics[:median_time]).value
                                    success = ratio < 1.1
                                    result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio * 100)
                                    test = Metric_Test(reference = 100.0, threshold_min_percent = 1.1 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                    push!(methodology_res.metrics, result => test)
                                    methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:median_time]).name, units = (test_res.metrics[:median_time]).units, value = (test_res.metrics[:median_time]).value) => test
                                    all_succeeded &= success
                                elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :median_time)) && (haskey(test_res.primitives, :median_time) && haskey(old_test_res.primitives, :median_time)))
                                    ratio = test_res.primitives[:median_time] / old_test_res.primitives[:median_time]
                                    success = ratio < 1.1
                                    result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio * 100)
                                    test = Metric_Test(reference = 100.0, threshold_min_percent = 1.1 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                    push!(methodology_res.metrics, result => test)
                                    methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = ":median_time", units = "s", value = test_res.primitives[:median_time]) => test
                                    all_succeeded &= success
                                end
                                if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                    methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":median_time Reference value", units = if haskey(old_test_res.metrics, :median_time)
                                                    (old_test_res.metrics[:median_time]).units
                                                else
                                                    "s"
                                                end, value = if haskey(old_test_res.metrics, :median_time)
                                                    (old_test_res.metrics[:median_time]).value
                                                else
                                                    if haskey(old_test_res.primitives, :median_time)
                                                        old_test_res.primitives[:median_time]
                                                    else
                                                        NaN
                                                    end
                                                end)
                                end
                                methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = ":median_time", units = if haskey(test_res.metrics, :median_time)
                                                (test_res.metrics[:median_time]).units
                                            else
                                                "s"
                                            end, value = if haskey(test_res.metrics, :median_time)
                                                (test_res.metrics[:median_time]).value
                                            else
                                                if haskey(test_res.primitives, :median_time)
                                                    test_res.primitives[:median_time]
                                                else
                                                    NaN
                                                end
                                            end)
                                for (r, test) = methodology_res.metrics
                                    PerfTest.@_prftest test.succeeded
                                end
                                saveMethodologyData(test_res.name, methodology_res)
                            end
                        end
                        nothing
                    end)
            nothing
            nothing
        end)
if main_rank(PerfTest.NormalMode)
    testresdict = Dict{String, Union{Dict, Test_Result}}()
    if TS isa Vector
        benchmarks = PerfTest.newBenchmarkGroup()
        for ts = TS
            testresdict[ts.description * "_" * string(ts.iterator)] = extractTestResults(TS)
            benchmarks[ts.description * "_" * string(ts.iterator)] = ts.benchmarks
        end
        newres = Suite_Execution_Result(timestamp = datetime2unix(now()), elapsed = time() - _t_begin, benchmarks = benchmarks, perftests = testresdict)
    else
        testresdict[TS.description] = extractTestResults(TS)
        newres = Suite_Execution_Result(timestamp = datetime2unix(now()), elapsed = time() - _t_begin, benchmarks = TS.benchmarks, perftests = testresdict)
    end
    if PerfTest.testsSucceeded(TS) && ((Configuration.CONFIG["regression"])["enabled"] && regression_path != _PRFT_GLOBALS.datafile_path)
        println("All performance tests have passed. Values will be registered as reference for regression testing.")
        push!(regression_file.results, newres)
        let
            res_num = length(regression_file.results)
            if (excess = 20 - res_num) <= 0
                PerfTest.p_yellow("[ℹ]")
                println(" Regression: Exceeded maximum recorded results. The oldest $(-1 * excess + 1) result/s will be removed.")
                for i = 1:-1 * excess + 1
                    popfirst!(regression_file.results)
                end
            end
        end
        PerfTest.saveDataFile(regression_path, regression_file)
    else
        println("Some tests failed or errored.")
    end
    let
        push!(_PRFT_GLOBALS.datafile.results, newres)
        res_num = length(_PRFT_GLOBALS.datafile.results)
        if (excess = 20 - res_num) <= 0
            PerfTest.p_yellow("[ℹ]")
            println(" Results File: Exceeded maximum recorded results. The oldest $(-1 * excess + 1) result/s will be removed.")
            for i = 1:-1 * excess + 1
                popfirst!(_PRFT_GLOBALS.datafile.results)
            end
        end
    end
    PerfTest.saveDataFile(_PRFT_GLOBALS.datafile_path, _PRFT_GLOBALS.datafile)
    println("[✓] $(path) Performance tests have been finished (elapsed $(newres.elapsed) s)")
    if (Configuration.CONFIG["regression"])["use_bencher"]
        bencher_config = Configuration.CONFIG["bencher"]
        PerfTest.BencherREST.exportSuiteToBencher(_PRFT_GLOBALS.datafile, bencher_config)
    end
    PerfTest.clean(PerfTest.NormalMode)
end
end