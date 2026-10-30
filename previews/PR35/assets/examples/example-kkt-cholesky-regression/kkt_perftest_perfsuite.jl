module __PERFTEST__
using Test, LIKWID, PerfTest
using LinearAlgebra
module KktCholesky
using LinearAlgebra
using Random
export build_kkt_system, cholesky_factor_fast!, cholesky_factor_regressed!, forward_substitution!, back_substitution!, solve_kkt, relative_residual
function build_kkt_system(n::Int, m::Int; seed::Int = 1, sigma::Float64 = 0.01)
    rng = MersenneTwister(seed)
    A = randn(rng, m, n)
    K = Matrix(Symmetric(A' * A))
    @inbounds for i = 1:n
            K[i, i] += sigma
        end
    b = randn(rng, n)
    return (K, b)
end
function cholesky_factor_fast!(L::Matrix{Float64}, K::Matrix{Float64})
    n = size(K, 1)
    copyto!(L, K)
    @inbounds for k = 1:n
            L[k, k] = sqrt(L[k, k])
            invLkk = 1.0 / L[k, k]
            for i = k + 1:n
                L[i, k] *= invLkk
            end
            for j = k + 1:n
                ljk = L[j, k]
                @simd for i = j:n
                        L[i, j] -= L[i, k] * ljk
                    end
            end
        end
    @inbounds for j = 1:n, i = 1:j - 1
            L[i, j] = 0.0
        end
    return L
end
function cholesky_factor_regressed!(L::Matrix{Float64}, K::Matrix{Float64})
    n = size(K, 1)
    copyto!(L, K)
    @inbounds for k = 1:n
            L[k, k] = sqrt(L[k, k])
            invLkk = 1.0 / L[k, k]
            for i = k + 1:n
                L[i, k] *= invLkk
            end
            for i = k + 1:n
                lik = L[i, k]
                @simd for j = k + 1:i
                        L[i, j] -= lik * L[j, k]
                    end
            end
        end
    @inbounds for j = 1:n, i = 1:j - 1
            L[i, j] = 0.0
        end
    return L
end
function forward_substitution!(z::Vector{Float64}, L::Matrix{Float64}, b::Vector{Float64})
    n = length(b)
    @inbounds for i = 1:n
            s = b[i]
            @simd for k = 1:i - 1
                    s -= L[i, k] * z[k]
                end
            z[i] = s / L[i, i]
        end
    return z
end
function back_substitution!(x::Vector{Float64}, L::Matrix{Float64}, z::Vector{Float64})
    n = length(z)
    @inbounds for i = n:-1:1
            s = z[i]
            @simd for k = i + 1:n
                    s -= L[k, i] * x[k]
                end
            x[i] = s / L[i, i]
        end
    return x
end
function solve_kkt(K::Matrix{Float64}, b::Vector{Float64}, fast::Bool = true)
    n = size(K, 1)
    L = Matrix{Float64}(undef, n, n)
    if fast
        cholesky_factor_fast!(L, K)
    else
        cholesky_factor_regressed!(L, K)
    end
    z = Vector{Float64}(undef, n)
    x = Vector{Float64}(undef, n)
    forward_substitution!(z, L, b)
    back_substitution!(x, L, z)
    return x
end
relative_residual(K, b, x) = norm(K * x - b) / norm(b)
end
using .KktCholesky
const USE_FAST_FACTORIZATION = true
PerfTest._perftest_config("[perfcompare]\nenabled = true\n\n[MPI]\nmode = \"reduce\"\nenabled = false\n\n[general]\nsave_results = true\nmax_saved_results = 20\nsuppress_output = true\nsave_folder = \".perftests\"\nthreads_per_numa = \"single\"\nrecursive = true\nverbose = 3\nautoflops = false\nplotting = true\nnumas = \"single\"\nlogs_enabled = true\nsafe_formulas = false\n\n[regression]\nenabled = true\ndedicated_reference_file = \"kkt_reference.JLD2\"\ndefault_threshold = 1.1\nuse_bencher = false\n\n[roofline]\nenabled = true\ndefault_threshold = 0.5\n\n[memory_bandwidth]\nenabled = true\ndefault_threshold = 0.5\n\n[machine_benchmarking]\nmemory_bandwidth_test_buffer_size = 0\n\n[bencher]\napi_key = \"\"\norganization = \"\"\napi_url = \"https://api.bencher.dev\"\nproject_name = \"\"\ncustom_testbed_name = \"\"\n")
using Test, Dates
nothing
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData, Configuration
_t_begin = time()
_GLOBAL_MODE = PerfTest.NormalMode
if main_rank(PerfTest.NormalMode)
    path = "./.perftests/kkt_perftest.jl_PERFORMANCE.JLD2"
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
    _PRFT_GLOBALS = GlobalSuiteData(datafile, path, "kkt_perftest.jl")
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
end
TS = @perftestset(PerfTestSet, "KKT Cholesky solve", begin
            local ts = Test.get_testset()
            ts.old_test_results = _PRFT_GLOBALS.old
            (n, m) = (512, 256)
            (K, b) = build_kkt_system(n, m; seed = 1)
            nothing
            nothing
            nothing
            nothing
            nothing
            nothing
            x = begin
                    ts.benchmarks["Test 1"] = @PRFTBenchmark(($solve_kkt)($K, $b, $USE_FAST_FACTORIZATION), samples = 15)
                    extensions = PerfTest.ExtensionData[]
                    (metrics, events) = PerfTest.perfmon((()->solve_kkt(K, b, USE_FAST_FACTORIZATION)), ["L3CACHE", "MEM", "FLOPS_DP"]; autopin = false, print = false)
                    push!(extensions, PerfTest.LIKWIDExtensionData(metrics, events))
                    push!(extensions, PerfTest.NoExtensionData())
                    push!(extensions, PerfTest.NoExtensionData())
                    test_res = Test_Result("Test 1", extensions)
                    ts.test_results["Test 1"] = test_res
                    keys = ["KKT Cholesky solve"]
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
                    test_res.primitives[:autoflop] = 0
                    test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = solve_kkt(K, b, USE_FAST_FACTORIZATION))
                    buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                    let m = newMetricResult(PerfTest.NormalMode, name = "l3_miss_ratio", units = "ratio", value = sum(PerfTest.likwidMetricsRetrieve(test_res, :L3CACHE, "L3 miss ratio")), auxiliary = false)
                        test_res.metrics[:l3_miss_ratio] = m
                    end
                    let m = newMetricResult(PerfTest.NormalMode, name = "mem_bandwidth", units = "MB/s", value = sum(PerfTest.likwidMetricsRetrieve(test_res, :MEM, "Memory bandwidth [MBytes/s]")), auxiliary = false)
                        test_res.metrics[:mem_bandwidth] = m
                    end
                    let m = newMetricResult(PerfTest.NormalMode, name = "attained_gflops", units = "GFLOP/s", value = (if haskey(_PRFT_GLOBALS.custom_benchmarks, :flop)
                                                (_PRFT_GLOBALS.custom_benchmarks[:flop]).value
                                            else
                                                if haskey(_PRFT_GLOBALS.builtins, :flop)
                                                    _PRFT_GLOBALS.builtins[:flop]
                                                else
                                                    if haskey(test_res.metrics, :flop)
                                                        (test_res.metrics[:flop]).value
                                                    else
                                                        if haskey(test_res.auxiliar, :flop)
                                                            (test_res.auxiliar[:flop]).value
                                                        else
                                                            sum(((PerfTest.likwidEventsRetrieve(test_res, :FLOPS_DP, :FP_ARITH_INST_RETIRED_SCALAR_DOUBLE; required = false) .* 1 .+ PerfTest.likwidEventsRetrieve(test_res, :FLOPS_DP, :FP_ARITH_INST_RETIRED_128B_PACKED_DOUBLE; required = false) .* 2) .+ PerfTest.likwidEventsRetrieve(test_res, :FLOPS_DP, :FP_ARITH_INST_RETIRED_256B_PACKED_DOUBLE; required = false) .* 4) .+ PerfTest.likwidEventsRetrieve(test_res, :FLOPS_DP, :FP_ARITH_INST_RETIRED_512B_PACKED_DOUBLE; required = false) .* 8)
                                                        end
                                                    end
                                                end
                                            end / 1.0e9) / test_res.primitives[:median_time], auxiliary = false)
                        test_res.metrics[:attained_gflops] = m
                    end
                    if main_rank(PerfTest.NormalMode)
                        let
                            methodology_res = Methodology_Result(name = "Performance Regression Testing")
                            all_succeeded = true
                            if haskey(test_res.metrics, :median_time) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :median_time))
                                ratio = (test_res.metrics[:median_time]).value / (old_test_res.metrics[:median_time]).value
                                success = ratio < 1.15
                                result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio * 100)
                                test = Metric_Test(reference = 100.0, threshold_min_percent = 1.15 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result => test)
                                methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:median_time]).name, units = (test_res.metrics[:median_time]).units, value = (test_res.metrics[:median_time]).value) => test
                                all_succeeded &= success
                            elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :median_time)) && (haskey(test_res.primitives, :median_time) && haskey(old_test_res.primitives, :median_time)))
                                ratio = test_res.primitives[:median_time] / old_test_res.primitives[:median_time]
                                success = ratio < 1.15
                                result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio * 100)
                                test = Metric_Test(reference = 100.0, threshold_min_percent = 1.15 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
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
                            if haskey(test_res.metrics, :l3_miss_ratio) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :l3_miss_ratio))
                                ratio = (test_res.metrics[:l3_miss_ratio]).value / (old_test_res.metrics[:l3_miss_ratio]).value
                                success = ratio < 1.2
                                result = newMetricResult(PerfTest.NormalMode, name = ":l3_miss_ratio Difference", units = "%", value = ratio * 100)
                                test = Metric_Test(reference = 100.0, threshold_min_percent = 1.2 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result => test)
                                methodology_res.custom_elements[:l3_miss_ratio] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:l3_miss_ratio]).name, units = (test_res.metrics[:l3_miss_ratio]).units, value = (test_res.metrics[:l3_miss_ratio]).value) => test
                                all_succeeded &= success
                            elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :l3_miss_ratio)) && (haskey(test_res.primitives, :l3_miss_ratio) && haskey(old_test_res.primitives, :l3_miss_ratio)))
                                ratio = test_res.primitives[:l3_miss_ratio] / old_test_res.primitives[:l3_miss_ratio]
                                success = ratio < 1.2
                                result = newMetricResult(PerfTest.NormalMode, name = ":l3_miss_ratio Difference", units = "%", value = ratio * 100)
                                test = Metric_Test(reference = 100.0, threshold_min_percent = 1.2 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result => test)
                                methodology_res.custom_elements[:l3_miss_ratio] = newMetricResult(PerfTest.NormalMode, name = ":l3_miss_ratio", units = "s", value = test_res.primitives[:l3_miss_ratio]) => test
                                all_succeeded &= success
                            end
                            if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":l3_miss_ratio Reference value", units = if haskey(old_test_res.metrics, :l3_miss_ratio)
                                                (old_test_res.metrics[:l3_miss_ratio]).units
                                            else
                                                "s"
                                            end, value = if haskey(old_test_res.metrics, :l3_miss_ratio)
                                                (old_test_res.metrics[:l3_miss_ratio]).value
                                            else
                                                if haskey(old_test_res.primitives, :l3_miss_ratio)
                                                    old_test_res.primitives[:l3_miss_ratio]
                                                else
                                                    NaN
                                                end
                                            end)
                            end
                            methodology_res.custom_elements[:l3_miss_ratio] = newMetricResult(PerfTest.NormalMode, name = ":l3_miss_ratio", units = if haskey(test_res.metrics, :l3_miss_ratio)
                                            (test_res.metrics[:l3_miss_ratio]).units
                                        else
                                            "s"
                                        end, value = if haskey(test_res.metrics, :l3_miss_ratio)
                                            (test_res.metrics[:l3_miss_ratio]).value
                                        else
                                            if haskey(test_res.primitives, :l3_miss_ratio)
                                                test_res.primitives[:l3_miss_ratio]
                                            else
                                                NaN
                                            end
                                        end)
                            if haskey(test_res.metrics, :attained_gflops) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :attained_gflops))
                                ratio = (test_res.metrics[:attained_gflops]).value / (old_test_res.metrics[:attained_gflops]).value
                                success = ratio > 0.85
                                result = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops Difference", units = "%", value = ratio * 100)
                                test = Metric_Test(reference = 100.0, threshold_min_percent = 0.85 * 100, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result => test)
                                methodology_res.custom_elements[:attained_gflops] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:attained_gflops]).name, units = (test_res.metrics[:attained_gflops]).units, value = (test_res.metrics[:attained_gflops]).value) => test
                                all_succeeded &= success
                            elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :attained_gflops)) && (haskey(test_res.primitives, :attained_gflops) && haskey(old_test_res.primitives, :attained_gflops)))
                                ratio = test_res.primitives[:attained_gflops] / old_test_res.primitives[:attained_gflops]
                                success = ratio > 0.85
                                result = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops Difference", units = "%", value = ratio * 100)
                                test = Metric_Test(reference = 100.0, threshold_min_percent = 0.85 * 100, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = true)
                                push!(methodology_res.metrics, result => test)
                                methodology_res.custom_elements[:attained_gflops] = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops", units = "s", value = test_res.primitives[:attained_gflops]) => test
                                all_succeeded &= success
                            end
                            if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops Reference value", units = if haskey(old_test_res.metrics, :attained_gflops)
                                                (old_test_res.metrics[:attained_gflops]).units
                                            else
                                                "s"
                                            end, value = if haskey(old_test_res.metrics, :attained_gflops)
                                                (old_test_res.metrics[:attained_gflops]).value
                                            else
                                                if haskey(old_test_res.primitives, :attained_gflops)
                                                    old_test_res.primitives[:attained_gflops]
                                                else
                                                    NaN
                                                end
                                            end)
                            end
                            methodology_res.custom_elements[:attained_gflops] = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops", units = if haskey(test_res.metrics, :attained_gflops)
                                            (test_res.metrics[:attained_gflops]).units
                                        else
                                            "s"
                                        end, value = if haskey(test_res.metrics, :attained_gflops)
                                            (test_res.metrics[:attained_gflops]).value
                                        else
                                            if haskey(test_res.primitives, :attained_gflops)
                                                test_res.primitives[:attained_gflops]
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
                end
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