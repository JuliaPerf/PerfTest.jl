module __PERFTEST__
using Test, PerfTest, LIKWID
using Clarabel, QDLDL, LinearAlgebra, SparseArrays, Random
let
    specs = :all
    arrgmt_l = PerfTest.Topology.literallizeArrangement(:all)
    arrgmt_e = PerfTest.Topology.isExecutableArrangement(arrgmt_l)
    if arrgmt_e === nothing
        @warn "Ignoring pinning."
    else
        try
            PerfTest.Topology.enforceThreadArrangement(arrgmt_e)
        catch e
            if Sys.iswindows() || Sys.isapple()
                @warn "Thread pinning is not supported on this OS. Ignoring specified arrangement."
            else
                @warn "Failed to enforce thread pinning: $(e), ignoring specified arrangement."
            end
        end
    end
end
const USE_FAST_FACTORIZATION = true
const GRAPH_MODEL = :random
const GRAPH_CLUSTER_SIZE = 512
function QDLDL._get_amd_ordering(A, amd_dense_scale)
    if USE_FAST_FACTORIZATION
        meta = QDLDL.AMD.Amd()
        meta.control[QDLDL.AMD.AMD_DENSE] *= Float64(amd_dense_scale)
        return QDLDL.AMD.amd(A, meta)
    else
        return nothing
    end
end
function random_edges(rng::AbstractRNG, n_vars::Int, nedges::Int)
    Ii = rand(rng, 1:n_vars, nedges)
    Jj = rand(rng, 1:n_vars, nedges)
    return (Ii, Jj)
end
function geometric_edges(rng::AbstractRNG, n_vars::Int, nedges::Int; dim::Int = 2, avg_cluster_size::Union{Nothing, Real} = nothing)
    pts = if avg_cluster_size === nothing
            rand(rng, dim, n_vars)
        else
            nclusters = clamp(round(Int, n_vars / avg_cluster_size), 1, n_vars)
            centers = rand(rng, dim, nclusters)
            spread = 0.3 * nclusters ^ (-1.0 / dim)
            assign = rand(rng, 1:nclusters, n_vars)
            out = Matrix{Float64}(undef, dim, n_vars)
            @inbounds for v = 1:n_vars
                    @views out[:, v] .= clamp.(centers[:, assign[v]] .+ spread .* randn(rng, dim), 0.0, 1.0)
                end
            out
        end
    npairs = (n_vars * (n_vars - 1)) ÷ 2
    dists = Vector{Float64}(undef, npairs)
    Is = Vector{Int}(undef, npairs)
    Js = Vector{Int}(undef, npairs)
    k = 0
    @inbounds for i = 1:n_vars, j = i + 1:n_vars
            k += 1
            s = 0.0
            for d = 1:dim
                s += (pts[d, i] - pts[d, j]) ^ 2
            end
            dists[k] = sqrt(s)
            Is[k] = i
            Js[k] = j
        end
    order = partialsortperm(dists, 1:nedges)
    return (Is[order], Js[order])
end
function build_qp(n_vars::Int; seed::Int = 1, avg_degree::Int = 6, graph_model::Symbol = :random, avg_cluster_size::Union{Nothing, Real} = nothing)
    rng = MersenneTwister(seed)
    nedges = (n_vars * avg_degree) ÷ 2
    if graph_model === :random
        (Ii, Jj) = random_edges(rng, n_vars, nedges)
    elseif graph_model === :geometric
        (Ii, Jj) = geometric_edges(rng, n_vars, nedges; avg_cluster_size = avg_cluster_size)
    else
        error("build_qp: unknown graph_model = $(repr(graph_model)); expected :random or :geometric")
    end
    keep = Ii .!= Jj
    (Ii, Jj) = (Ii[keep], Jj[keep])
    vals = -((abs.(randn(rng, length(Ii))) .+ 0.1))
    P0 = sparse(Ii, Jj, vals, n_vars, n_vars)
    P0 = P0 + P0'
    d = vec(sum(abs, P0; dims = 2)) .+ 1.0
    P0 = (P0 - spdiagm(0 => diag(P0))) + spdiagm(0 => d)
    perm = randperm(rng, n_vars)
    P = P0[perm, perm]
    q = randn(rng, n_vars)
    A = sparse([-(I(n_vars)); I(n_vars)] .* 1.0)
    b = [zeros(n_vars); fill(5.0, n_vars)]
    cones = [Clarabel.NonnegativeConeT(n_vars), Clarabel.NonnegativeConeT(n_vars)]
    return (P, q, A, b, cones)
end
function solve_fresh_qp(P, q, A, b, cones, settings)
    solver = Clarabel.Solver(P, q, A, b, cones, settings)
    Clarabel.solve!(solver)
    return solver
end
PerfTest._perftest_config("\n[general]\nverbose = 3\n[regression]\nenabled = true\ndedicated_reference_file = 'clarabel_reference_$(gethostname())_$(GRAPH_MODEL).JLD2'\n")
using Test, Dates
nothing
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData, Configuration, metricSampledValue, SampledValue
_t_begin = time()
_GLOBAL_MODE = PerfTest.NormalMode
if main_rank(PerfTest.NormalMode)
    path = "./.perftests/clarabel_perftest.jl_PERFORMANCE.JLD2"
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
    _PRFT_GLOBALS = GlobalSuiteData(datafile, path, "clarabel_perftest.jl")
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
TS = @perftestset(PerfTestSet, "Wrapper", begin
            local ts = Test.get_testset()
            ts.old_test_results = _PRFT_GLOBALS.old
            nothing
            TS = @perftestset(PerfTestSet, "Clarabel QP solve", for n_vars = [32, 64, 128, 256, 512, 1024, 2048, 2560]
                        local ts = Test.get_testset()
                        ts.iterator = n_vars
                        nothing
                        @info n_vars
                        (P, q, A, b, cones) = build_qp(n_vars; graph_model = GRAPH_MODEL, avg_cluster_size = GRAPH_CLUSTER_SIZE)
                        settings = Clarabel.Settings(verbose = false)
                        nothing
                        nothing
                        nothing
                        solver = begin
                                ts.benchmarks["Test 1"] = @PRFTBenchmark(($solve_fresh_qp)($P, $q, $A, $b, $cones, $settings), samples = 20, evals = 1)
                                extensions = PerfTest.ExtensionData[]
                                (metrics, events) = PerfTest.perfmon((()->solve_fresh_qp(P, q, A, b, cones, settings)), ["L3", "FLOPS_DP"]; autopin = false, print = false, nsamples = length(ts.benchmarks["Test 1"]))
                                push!(extensions, PerfTest.LIKWIDExtensionData(metrics, events))
                                push!(extensions, PerfTest.NoExtensionData())
                                push!(extensions, PerfTest.NoExtensionData())
                                test_res = Test_Result("Test 1", extensions)
                                ts.test_results["Test 1"] = test_res
                                keys = ["Wrapper", string("Clarabel QP solve", "_", n_vars)]
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
                                test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = solve_fresh_qp(P, q, A, b, cones, settings))
                                buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                                let m = newMetricResult(PerfTest.NormalMode, name = "attained_gflops", units = "GFLOP/s", value = (if haskey(_PRFT_GLOBALS.custom_benchmarks, :flop)
                                                            PerfTest.metricSampledValue(_PRFT_GLOBALS.custom_benchmarks[:flop])
                                                        else
                                                            if haskey(_PRFT_GLOBALS.builtins, :flop)
                                                                _PRFT_GLOBALS.builtins[:flop]
                                                            else
                                                                if haskey(test_res.metrics, :flop)
                                                                    PerfTest.metricSampledValue(test_res.metrics[:flop])
                                                                else
                                                                    if haskey(test_res.auxiliar, :flop)
                                                                        PerfTest.metricSampledValue(test_res.auxiliar[:flop])
                                                                    else
                                                                        sum(PerfTest.likwidMetricsRetrieve(test_res, :FLOPS_DP, "DP [MFLOP/s]")) * 1.0e6 * test_res.primitives[:median_time]
                                                                    end
                                                                end
                                                            end
                                                        end / 1.0e9) / test_res.primitives[:median_time], auxiliary = false, showvar = false)
                                    test_res.metrics[:attained_gflops] = m
                                end
                                let m = newMetricResult(PerfTest.NormalMode, name = "l3_bandwidth", units = "GBytes/s", value = sum(PerfTest.likwidMetricsRetrieve(test_res, :L3, "L3 data volume [GBytes]")), auxiliary = false, showvar = false)
                                    test_res.metrics[:l3_bandwidth] = m
                                end
                                if main_rank(PerfTest.NormalMode)
                                    let
                                        methodology_res = Methodology_Result(name = "Performance Regression Testing")
                                        all_succeeded = true
                                        if haskey(test_res.metrics, :median_time) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :median_time))
                                            ratio_sv = metricSampledValue(test_res.metrics[:median_time]) / metricSampledValue(old_test_res.metrics[:median_time])
                                            ratio = if ratio_sv isa SampledValue
                                                    ratio_sv.value
                                                else
                                                    ratio_sv
                                                end
                                            success = ratio < 1.15
                                            result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio_sv * 100, showvar = false)
                                            test = Metric_Test(reference = 100.0, threshold_min_percent = 1.15 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true, showvar = false)
                                            push!(methodology_res.metrics, result => test)
                                            methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:median_time]).name, units = (test_res.metrics[:median_time]).units, value = metricSampledValue(test_res.metrics[:median_time]), showvar = false) => test
                                            all_succeeded &= success
                                        elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :median_time)) && (haskey(test_res.primitives, :median_time) && haskey(old_test_res.primitives, :median_time)))
                                            ratio_sv = test_res.primitives[:median_time] / old_test_res.primitives[:median_time]
                                            ratio = if ratio_sv isa SampledValue
                                                    ratio_sv.value
                                                else
                                                    ratio_sv
                                                end
                                            success = ratio < 1.15
                                            result = newMetricResult(PerfTest.NormalMode, name = ":median_time Difference", units = "%", value = ratio_sv * 100, showvar = false)
                                            test = Metric_Test(reference = 100.0, threshold_min_percent = 1.15 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true, showvar = false)
                                            push!(methodology_res.metrics, result => test)
                                            methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = ":median_time", units = "s", value = test_res.primitives[:median_time], showvar = false) => test
                                            all_succeeded &= success
                                        end
                                        if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                            methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":median_time Reference value", units = if haskey(old_test_res.metrics, :median_time)
                                                            (old_test_res.metrics[:median_time]).units
                                                        else
                                                            "s"
                                                        end, value = if haskey(old_test_res.metrics, :median_time)
                                                            metricSampledValue(old_test_res.metrics[:median_time])
                                                        else
                                                            if haskey(old_test_res.primitives, :median_time)
                                                                old_test_res.primitives[:median_time]
                                                            else
                                                                NaN
                                                            end
                                                        end, showvar = false)
                                        end
                                        methodology_res.custom_elements[:median_time] = newMetricResult(PerfTest.NormalMode, name = ":median_time", units = if haskey(test_res.metrics, :median_time)
                                                        (test_res.metrics[:median_time]).units
                                                    else
                                                        "s"
                                                    end, value = if haskey(test_res.metrics, :median_time)
                                                        metricSampledValue(test_res.metrics[:median_time])
                                                    else
                                                        if haskey(test_res.primitives, :median_time)
                                                            test_res.primitives[:median_time]
                                                        else
                                                            NaN
                                                        end
                                                    end, showvar = false)
                                        if haskey(test_res.metrics, :attained_gflops) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :attained_gflops))
                                            ratio_sv = metricSampledValue(test_res.metrics[:attained_gflops]) / metricSampledValue(old_test_res.metrics[:attained_gflops])
                                            ratio = if ratio_sv isa SampledValue
                                                    ratio_sv.value
                                                else
                                                    ratio_sv
                                                end
                                            success = ratio > 0.85
                                            result = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops Difference", units = "%", value = ratio_sv * 100, showvar = false)
                                            test = Metric_Test(reference = 100.0, threshold_min_percent = 0.85 * 100, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = true, showvar = false)
                                            push!(methodology_res.metrics, result => test)
                                            methodology_res.custom_elements[:attained_gflops] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:attained_gflops]).name, units = (test_res.metrics[:attained_gflops]).units, value = metricSampledValue(test_res.metrics[:attained_gflops]), showvar = false) => test
                                            all_succeeded &= success
                                        elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :attained_gflops)) && (haskey(test_res.primitives, :attained_gflops) && haskey(old_test_res.primitives, :attained_gflops)))
                                            ratio_sv = test_res.primitives[:attained_gflops] / old_test_res.primitives[:attained_gflops]
                                            ratio = if ratio_sv isa SampledValue
                                                    ratio_sv.value
                                                else
                                                    ratio_sv
                                                end
                                            success = ratio > 0.85
                                            result = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops Difference", units = "%", value = ratio_sv * 100, showvar = false)
                                            test = Metric_Test(reference = 100.0, threshold_min_percent = 0.85 * 100, threshold_max_percent = nothing, low_is_bad = true, succeeded = success, custom_plotting = Symbol[], full_print = true, showvar = false)
                                            push!(methodology_res.metrics, result => test)
                                            methodology_res.custom_elements[:attained_gflops] = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops", units = "s", value = test_res.primitives[:attained_gflops], showvar = false) => test
                                            all_succeeded &= success
                                        end
                                        if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                            methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops Reference value", units = if haskey(old_test_res.metrics, :attained_gflops)
                                                            (old_test_res.metrics[:attained_gflops]).units
                                                        else
                                                            "s"
                                                        end, value = if haskey(old_test_res.metrics, :attained_gflops)
                                                            metricSampledValue(old_test_res.metrics[:attained_gflops])
                                                        else
                                                            if haskey(old_test_res.primitives, :attained_gflops)
                                                                old_test_res.primitives[:attained_gflops]
                                                            else
                                                                NaN
                                                            end
                                                        end, showvar = false)
                                        end
                                        methodology_res.custom_elements[:attained_gflops] = newMetricResult(PerfTest.NormalMode, name = ":attained_gflops", units = if haskey(test_res.metrics, :attained_gflops)
                                                        (test_res.metrics[:attained_gflops]).units
                                                    else
                                                        "s"
                                                    end, value = if haskey(test_res.metrics, :attained_gflops)
                                                        metricSampledValue(test_res.metrics[:attained_gflops])
                                                    else
                                                        if haskey(test_res.primitives, :attained_gflops)
                                                            test_res.primitives[:attained_gflops]
                                                        else
                                                            NaN
                                                        end
                                                    end, showvar = false)
                                        if haskey(test_res.metrics, :l3_bandwidth) && (!(old_test_res isa Nothing) && haskey(old_test_res.metrics, :l3_bandwidth))
                                            ratio_sv = metricSampledValue(test_res.metrics[:l3_bandwidth]) / metricSampledValue(old_test_res.metrics[:l3_bandwidth])
                                            ratio = if ratio_sv isa SampledValue
                                                    ratio_sv.value
                                                else
                                                    ratio_sv
                                                end
                                            success = ratio < 1.15
                                            result = newMetricResult(PerfTest.NormalMode, name = ":l3_bandwidth Difference", units = "%", value = ratio_sv * 100, showvar = false)
                                            test = Metric_Test(reference = 100.0, threshold_min_percent = 1.15 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true, showvar = false)
                                            push!(methodology_res.metrics, result => test)
                                            methodology_res.custom_elements[:l3_bandwidth] = newMetricResult(PerfTest.NormalMode, name = (test_res.metrics[:l3_bandwidth]).name, units = (test_res.metrics[:l3_bandwidth]).units, value = metricSampledValue(test_res.metrics[:l3_bandwidth]), showvar = false) => test
                                            all_succeeded &= success
                                        elseif !(old_test_res isa Nothing) && (!(haskey(test_res.metrics, :l3_bandwidth)) && (haskey(test_res.primitives, :l3_bandwidth) && haskey(old_test_res.primitives, :l3_bandwidth)))
                                            ratio_sv = test_res.primitives[:l3_bandwidth] / old_test_res.primitives[:l3_bandwidth]
                                            ratio = if ratio_sv isa SampledValue
                                                    ratio_sv.value
                                                else
                                                    ratio_sv
                                                end
                                            success = ratio < 1.15
                                            result = newMetricResult(PerfTest.NormalMode, name = ":l3_bandwidth Difference", units = "%", value = ratio_sv * 100, showvar = false)
                                            test = Metric_Test(reference = 100.0, threshold_min_percent = 1.15 * 100, threshold_max_percent = nothing, low_is_bad = false, succeeded = success, custom_plotting = Symbol[], full_print = true, showvar = false)
                                            push!(methodology_res.metrics, result => test)
                                            methodology_res.custom_elements[:l3_bandwidth] = newMetricResult(PerfTest.NormalMode, name = ":l3_bandwidth", units = "s", value = test_res.primitives[:l3_bandwidth], showvar = false) => test
                                            all_succeeded &= success
                                        end
                                        if (Configuration.CONFIG["general"])["verbose"] >= 2 && !(old_test_res isa Nothing)
                                            methodology_res.custom_elements[:reference] = newMetricResult(PerfTest.NormalMode, name = ":l3_bandwidth Reference value", units = if haskey(old_test_res.metrics, :l3_bandwidth)
                                                            (old_test_res.metrics[:l3_bandwidth]).units
                                                        else
                                                            "s"
                                                        end, value = if haskey(old_test_res.metrics, :l3_bandwidth)
                                                            metricSampledValue(old_test_res.metrics[:l3_bandwidth])
                                                        else
                                                            if haskey(old_test_res.primitives, :l3_bandwidth)
                                                                old_test_res.primitives[:l3_bandwidth]
                                                            else
                                                                NaN
                                                            end
                                                        end, showvar = false)
                                        end
                                        methodology_res.custom_elements[:l3_bandwidth] = newMetricResult(PerfTest.NormalMode, name = ":l3_bandwidth", units = if haskey(test_res.metrics, :l3_bandwidth)
                                                        (test_res.metrics[:l3_bandwidth]).units
                                                    else
                                                        "s"
                                                    end, value = if haskey(test_res.metrics, :l3_bandwidth)
                                                        metricSampledValue(test_res.metrics[:l3_bandwidth])
                                                    else
                                                        if haskey(test_res.primitives, :l3_bandwidth)
                                                            test_res.primitives[:l3_bandwidth]
                                                        else
                                                            NaN
                                                        end
                                                    end, showvar = false)
                                        for (r, test) = methodology_res.metrics
                                            PerfTest.@_prftest test.succeeded
                                        end
                                        saveMethodologyData(test_res.name, methodology_res)
                                    end
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
            testresdict[ts.description * "_" * string(ts.iterator)] = extractTestResults(ts)
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