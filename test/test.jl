module __PERFTEST__
using Test
using PerfTest
function testfun(a::Int)
    c = 1
    for i = 1:a
        c = c + i ^ 2 / c
    end
    return c
end
using Test, Dates
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives
_PRFT_GLOBAL = Dict{Symbol, Any}()
_PRFT_GLOBAL[:is_main_rank] = true
_PRFT_GLOBAL[:comm_size] = 1
MPISetup(PerfTest.NormalMode, _PRFT_GLOBAL)
if _PRFT_GLOBAL[:is_main_rank]
    path = "./.perftests/t3-roofline.jl_PERFORMANCE.JLD2"
    nofile = true
    if isfile(path)
        nofile = false
        _PRFT_GLOBAL[:datafile] = PerfTest.openDataFile(path)
    else
        _PRFT_GLOBAL[:datafile] = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
        PerfTest.p_yellow("[!]")
        println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
    end
end
let
    _PRFT_GLOBAL[:machine] = Dict{Symbol, Any}()
    (_PRFT_GLOBAL[:machine])[:empirical] = Dict{Symbol, Any}()
    size = try
            CpuId.cachesize()
        catch
            addLog("machine", "[MACHINE] CpuId failed, using default cache size")
            [1024 * 1024 * 16]
        end
    global (_PRFT_GLOBAL[:machine])[:cache_sizes] = size
    addLog("machine", "[MACHINE] Memory buffer size for benchmarking = $((size ./ 1024) ./ 1024) [MB]")
    measureCPUPeakFlops!(PerfTest.NormalMode, _PRFT_GLOBAL)
    measureMemBandwidth!(PerfTest.NormalMode, _PRFT_GLOBAL)
end
_PRFT_LOCAL_SUITE = PRFTBenchmarkGroup()
_PRFT_LOCAL_ADDITIONAL = Dict()
_PRFT_LOCAL_SUITE["FIRST LEVEL"] = PRFTBenchmarkGroup()
_PRFT_LOCAL_ADDITIONAL["FIRST LEVEL"] = Dict()
(_PRFT_LOCAL_ADDITIONAL["FIRST LEVEL"])[:exported] = Dict{Symbol, Any}()
let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE["FIRST LEVEL"], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL["FIRST LEVEL"]
    _PRFT_LOCAL_SUITE["SECOND LEVEL"] = PRFTBenchmarkGroup()
    _PRFT_LOCAL_ADDITIONAL["SECOND LEVEL"] = Dict()
    (_PRFT_LOCAL_ADDITIONAL["SECOND LEVEL"])[:exported] = copy(_PRFT_LOCAL_ADDITIONAL[:exported])
    let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE["SECOND LEVEL"], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL["SECOND LEVEL"]
        nothing
        x = begin
                _PRFT_LOCAL_ADDITIONAL["Test 1"] = Dict()
                (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:exported] = _PRFT_LOCAL_ADDITIONAL[:exported]
                (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:iterator] = nothing
                @PRFTSuppress begin
                        _PRFT_LOCAL_SUITE["Test 1"] = @PRFTBenchmark(($testfun)(10))
                        (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:autoflop] = PRFTflop(@PRFTCount_ops(($testfun)(10)))
                    end
                (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:printed_output] = @PRFTCapture_out((_PRFT_LOCAL_ADDITIONAL["Test 1"])[:ret_value] = testfun(10))
            end
    end
    nothing
end
nothing
_PRFT_GLOBAL[:suite] = _PRFT_LOCAL_SUITE
_PRFT_GLOBAL[:additional] = _PRFT_LOCAL_ADDITIONAL
if _PRFT_GLOBAL[:is_main_rank]
    let
        res_num = length((_PRFT_GLOBAL[:datafile]).results)
        if (excess = 20 - res_num) <= 0
            PerfTest.p_yellow("[ℹ]")
            println(" Regression: Exceeded maximum recorded results. The oldest $(-1 * excess + 1) result/s will be removed.")
            for i = 1:-1 * excess + 1
                popfirst!((_PRFT_GLOBAL[:datafile]).results)
            end
        end
        if length((_PRFT_GLOBAL[:datafile]).results) > 0
            _PRFT_GLOBAL[:old] = ((_PRFT_GLOBAL[:datafile]).results[end]).perftests
        else
            _PRFT_GLOBAL[:old] = nothing
        end
        _PRFT_GLOBAL[:new] = Dict{String, Union{Dict, Test_Result}}()
    end
end
failed = false
_PRFT_LOCAL = Dict{StrOrSym, Any}()
_PRFT_LOCAL[:depth] = PerfTest.DepthRecord[]
_PRFT_LOCAL[:results] = Dict{PerfTest.StrOrSym, Any}()
_PRFT_LOCAL[:additional] = _PRFT_GLOBAL[:additional]
_PRFT_LOCAL[:suite] = _PRFT_GLOBAL[:suite]
tt = Dict()
try
    tt["FIRST LEVEL"] = @testset("FIRST LEVEL", showtiming = false, begin
                _PRFT_LOCAL["FIRST LEVEL"] = Dict{PerfTest.StrOrSym, Any}()
                (_PRFT_LOCAL["FIRST LEVEL"])[:additional] = (_PRFT_LOCAL[:additional])["FIRST LEVEL"]
                (_PRFT_LOCAL["FIRST LEVEL"])[:suite] = (_PRFT_LOCAL[:suite])["FIRST LEVEL"]
                (_PRFT_LOCAL["FIRST LEVEL"])[:depth] = _PRFT_LOCAL[:depth]
                (by_index(_PRFT_GLOBAL[:new], _PRFT_LOCAL[:depth]))["FIRST LEVEL"] = Dict{String, Union{Dict, Test_Result}}()
                let _PRFT_LOCAL = _PRFT_LOCAL["FIRST LEVEL"]
                    push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord("FIRST LEVEL"))
                    _PRFT_LOCAL[:primitives] = Dict{Symbol, Any}()
                    _PRFT_LOCAL[:metrics] = Dict{Symbol, Metric_Result}()
                    _PRFT_LOCAL[:auxiliar] = Dict{Symbol, Metric_Result}()
                    @testset "SECOND LEVEL" showtiming = false begin
                            _PRFT_LOCAL["SECOND LEVEL"] = Dict{PerfTest.StrOrSym, Any}()
                            (_PRFT_LOCAL["SECOND LEVEL"])[:additional] = (_PRFT_LOCAL[:additional])["SECOND LEVEL"]
                            (_PRFT_LOCAL["SECOND LEVEL"])[:suite] = (_PRFT_LOCAL[:suite])["SECOND LEVEL"]
                            (_PRFT_LOCAL["SECOND LEVEL"])[:depth] = _PRFT_LOCAL[:depth]
                            (by_index(_PRFT_GLOBAL[:new], _PRFT_LOCAL[:depth]))["SECOND LEVEL"] = Dict{String, Union{Dict, Test_Result}}()
                            let _PRFT_LOCAL = _PRFT_LOCAL["SECOND LEVEL"]
                                push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord("SECOND LEVEL"))
                                _PRFT_LOCAL[:primitives] = Dict{Symbol, Any}()
                                _PRFT_LOCAL[:metrics] = Dict{Symbol, Metric_Result}()
                                _PRFT_LOCAL[:auxiliar] = Dict{Symbol, Metric_Result}()
                                _PRFT_LOCAL["Test 1"] = Dict{PerfTest.StrOrSym, Any}()
                                (_PRFT_LOCAL["Test 1"])[:additional] = (_PRFT_LOCAL[:additional])["Test 1"]
                                (_PRFT_LOCAL["Test 1"])[:suite] = (_PRFT_LOCAL[:suite])["Test 1"]
                                (_PRFT_LOCAL["Test 1"])[:depth] = _PRFT_LOCAL[:depth]
                                (by_index(_PRFT_GLOBAL[:new], _PRFT_LOCAL[:depth]))["Test 1"] = Dict{String, Union{Dict, Test_Result}}()
                                let _PRFT_LOCAL = _PRFT_LOCAL["Test 1"]
                                    push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord("Test 1"))
                                    _PRFT_LOCAL[:primitives] = Dict{Symbol, Any}()
                                    _PRFT_LOCAL[:metrics] = Dict{Symbol, Metric_Result}()
                                    _PRFT_LOCAL[:auxiliar] = Dict{Symbol, Metric_Result}()
                                    PerfTest.printDepth!(_PRFT_LOCAL[:depth])
                                    buildPrimitiveMetrics!(PerfTest.NormalMode, _PRFT_LOCAL, _PRFT_GLOBAL)
                                    if _PRFT_GLOBAL[:is_main_rank]
                                        d = by_index(_PRFT_GLOBAL[:new], (_PRFT_LOCAL[:depth])[1:end - 1])
                                        d[((_PRFT_LOCAL[:depth])[end]).name] = Test_Result()
                                        savePrimitives(_PRFT_LOCAL, _PRFT_GLOBAL)
                                        (_PRFT_LOCAL[:metrics])[:opInt] = newMetricResult(PerfTest.NormalMode, name = "Operational intensity", units = "Flop/Byte", value = (_PRFT_LOCAL[:primitives])[:autoflop] / 4, auxiliary = false)
                                        (_PRFT_LOCAL[:metrics])[:attainedFLOPS] = newMetricResult(PerfTest.NormalMode, name = "Attained Flops", units = "FLOP/s", value = (_PRFT_LOCAL[:primitives])[:autoflop] / (_PRFT_LOCAL[:primitives])[:median_time], auxiliary = false)
                                        let
                                            opint = ((_PRFT_LOCAL[:metrics])[:opInt]).value
                                            flop_s = ((_PRFT_LOCAL[:metrics])[:attainedFLOPS]).value
                                            roof = PerfTest.rooflineCalc(((_PRFT_GLOBAL[:machine])[:empirical])[:peakflops], (((_PRFT_GLOBAL[:machine])[:empirical])[:peakmemBW])[:COPY])
                                            result_flop_ratio = newMetricResult(PerfTest.NormalMode, name = "Attained FLOP/S by expected FLOP/S", units = "%", value = (flop_s / roof(opint)) * 100)
                                            methodology_res = Methodology_Result(name = "Roofline Model")
                                            success_flop = result_flop_ratio.value >= 0.5
                                            flop_test = Metric_Test(reference = 100, threshold_min_percent = 0.5, threshold_max_percent = nothing, low_is_bad = true, succeeded = success_flop, custom_plotting = Symbol[], full_print = true)
                                            push!(methodology_res.metrics, result_flop_ratio => flop_test)
                                            methodology_res.custom_elements[:realf] = magnitudeAdjust((_PRFT_LOCAL[:metrics])[:attainedFLOPS])
                                            methodology_res.custom_elements[:opint] = (_PRFT_LOCAL[:metrics])[:opInt]
                                            aux_mem = newMetricResult(PerfTest.NormalMode, name = "Peak empirical bandwidth", units = "B/s", value = (((_PRFT_GLOBAL[:machine])[:empirical])[:peakmemBW])[:COPY])
                                            aux_flops = newMetricResult(PerfTest.NormalMode, name = "Peak empirical flops", units = "FLOP/s", value = ((_PRFT_GLOBAL[:machine])[:empirical])[:peakflops])
                                            aux_rcorner = newMetricResult(PerfTest.NormalMode, name = "Roofline Corner", units = "Flop/Byte", value = aux_flops.value / aux_mem.value)
                                            methodology_res.custom_elements[:mem_peak] = magnitudeAdjust(aux_mem)
                                            methodology_res.custom_elements[:cpu_peak] = magnitudeAdjust(aux_flops)
                                            methodology_res.custom_elements[:roof_corner] = magnitudeAdjust(aux_rcorner)
                                            methodology_res.custom_elements[:roof_corner_raw] = aux_rcorner
                                            methodology_res.custom_elements[:factor] = 0.5
                                            methodology_res.custom_elements[:plot] = PerfTest.printFullRoofline
                                            if true || !(flop_test.succeeded)
                                                PerfTest.printMethodology(methodology_res, 2, true)
                                            end
                                            push!((by_index(_PRFT_GLOBAL[:new], _PRFT_LOCAL[:depth])).methodology_results, methodology_res)
                                            try
                                                @test flop_test.succeeded
                                            catch
                                            end
                                        end
                                        PerfTest.printAuxiliaries(_PRFT_LOCAL[:metrics], length(_PRFT_LOCAL[:depth]))
                                    end
                                    pop!(_PRFT_LOCAL[:depth])
                                end
                                pop!(_PRFT_LOCAL[:depth])
                            end
                        end
                    pop!(_PRFT_LOCAL[:depth])
                end
            end)
catch e
    @warn "One or more performance tests have failed"
    failed = true
end
if _PRFT_GLOBAL[:is_main_rank]
    newres = Suite_Execution_Result(timestamp = datetime2unix(now()), benchmarks = _PRFT_GLOBAL[:suite], perftests = _PRFT_GLOBAL[:new])
    push!((_PRFT_GLOBAL[:datafile]).results, newres)
    if !failed
        PerfTest.saveDataFile(path, _PRFT_GLOBAL[:datafile])
    end
    println("[✓] $(path) Performance tests have been finished")
end
end