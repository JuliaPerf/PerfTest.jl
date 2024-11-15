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
using Test
using BenchmarkTools
using STREAMBenchmark
using Suppressor
using PerfTest: DepthRecord, Metric_Reference, Metric_Test, Methodology_Result, StrOrSym, Metric_Result
_PRFT_GLOBAL = Dict{Symbol, Any}()
using CountFlops
path = "./.perftests/t3-roofline.jl_PERFORMANCE.JLD2"
nofile = true
if isfile(path)
    nofile = false
    _PRFT_GLOBAL[:datafile] = PerfTest.openDataFile(path)
else
    _PRFT_GLOBAL[:datafile] = PerfTest.Perftest_Datafile_Root(PerfTest.Perftest_Result[], PerfTest.Dict{PerfTest.StrOrSym, Any}[])
    PerfTest.p_yellow("[!]")
    println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
end
let
    _PRFT_GLOBAL[:machine] = Dict{Symbol, Any}()
    (_PRFT_GLOBAL[:machine])[:empirical] = Dict{Symbol, Any}()
    size = PerfTest.getAproxCacheSize()
    global (_PRFT_GLOBAL[:machine])[:approx_cache_size] = if size isa Int
                size
            else
                30000
            end
    using LinearAlgebra
    LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
    global ((_PRFT_GLOBAL[:machine])[:empirical])[:peakflops] = LinearAlgebra.peakflops(; parallel = true) / 1.0e9
    bench_data = STREAMBenchmark.benchmark(N = 4 * (_PRFT_GLOBAL[:machine])[:approx_cache_size])
    peakbandwidth = bench_data.multi.maximum / 1000.0
    global ((_PRFT_GLOBAL[:machine])[:empirical])[:peakmemBW] = peakbandwidth
end
_PRFT_LOCAL_SUITE = BenchmarkGroup()
_PRFT_LOCAL_ADDITIONAL = Dict()
_PRFT_LOCAL_SUITE["FIRST LEVEL"] = BenchmarkGroup()
_PRFT_LOCAL_ADDITIONAL["FIRST LEVEL"] = Dict()
let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE["FIRST LEVEL"], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL["FIRST LEVEL"]
    _PRFT_LOCAL_SUITE["SECOND LEVEL"] = BenchmarkGroup()
    _PRFT_LOCAL_ADDITIONAL["SECOND LEVEL"] = Dict()
    let _PRFT_LOCAL_SUITE = _PRFT_LOCAL_SUITE["SECOND LEVEL"], _PRFT_LOCAL_ADDITIONAL = _PRFT_LOCAL_ADDITIONAL["SECOND LEVEL"]
        PerfTest.MethodologyParameters[PerfTest.MethodologyParameters(:roofline, "Roofline Model", true, Dict{Symbol, Any}(Symbol("") => quote
    #= none:20 =#
    3 + 1
end, :target_ratio => 0.05, :test_flop => true, :actual_flops => 1000000, :test_opint => false))]
        x = begin
                _PRFT_LOCAL_ADDITIONAL["Test 1"] = Dict()
                (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:iterator] = nothing
                @suppress begin
                        _PRFT_LOCAL_SUITE["Test 1"] = @benchmark(testfun(10))
                        (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:autoflop] = CountFlops.flop(@count_ops(testfun(10)))
                    end
                (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:printed_output] = @capture_out((_PRFT_LOCAL_ADDITIONAL["Test 1"])[:ret_value] = testfun(10))
                @show (_PRFT_LOCAL_ADDITIONAL["Test 1"])[:autoflop]
            end
    end
    nothing
end
nothing
_PRFT_GLOBAL[:suite] = _PRFT_LOCAL_SUITE
_PRFT_GLOBAL[:additional] = _PRFT_LOCAL_ADDITIONAL
let
    res_num = length((_PRFT_GLOBAL[:datafile]).results)
    if (excess = 10 - res_num) <= 0
        PerfTest.p_yellow("[ℹ]")
        println(" Regression: Exceeded maximum recorded results. The oldest $(-1 * excess + 1) result/s will be removed.")
        for i = 1:-1 * excess + 1
            popfirst!((_PRFT_GLOBAL[:datafile]).results)
        end
    end
end
let
    current_result = PerfTest.Perftest_Result(timestamp = time(), benchmarks = _PRFT_GLOBAL[:suite], perftests = Dict())
    push!((_PRFT_GLOBAL[:datafile]).results, current_result)
    PerfTest.p_yellow("[ℹ]")
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
                            let _PRFT_LOCAL = _PRFT_LOCAL["SECOND LEVEL"]
                                push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord("SECOND LEVEL"))
                                _PRFT_LOCAL[:primitives] = Dict{Symbol, Any}()
                                _PRFT_LOCAL[:metrics] = Dict{Symbol, Metric_Result}()
                                _PRFT_LOCAL[:auxiliar] = Dict{Symbol, Metric_Result}()
                                _PRFT_LOCAL["Test 1"] = Dict{PerfTest.StrOrSym, Any}()
                                (_PRFT_LOCAL["Test 1"])[:additional] = (_PRFT_LOCAL[:additional])["Test 1"]
                                (_PRFT_LOCAL["Test 1"])[:suite] = (_PRFT_LOCAL[:suite])["Test 1"]
                                (_PRFT_LOCAL["Test 1"])[:depth] = _PRFT_LOCAL[:depth]
                                let _PRFT_LOCAL = _PRFT_LOCAL["Test 1"]
                                    push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord("Test 1"))
                                    _PRFT_LOCAL[:primitives] = Dict{Symbol, Any}()
                                    _PRFT_LOCAL[:metrics] = Dict{Symbol, Metric_Result}()
                                    _PRFT_LOCAL[:auxiliar] = Dict{Symbol, Metric_Result}()
                                    PerfTest.printDepth!(_PRFT_LOCAL[:depth])
                                    (_PRFT_LOCAL[:primitives])[:median_time] = (median(_PRFT_LOCAL[:suite])).time
                                    (_PRFT_LOCAL[:primitives])[:min_time] = (minimum(_PRFT_LOCAL[:suite])).time
                                    (_PRFT_LOCAL[:primitives])[:autoflop] = (_PRFT_LOCAL[:additional])[:autoflop]
                                    (_PRFT_LOCAL[:primitives])[:ret_value] = (_PRFT_LOCAL[:additional])[:ret_value]
                                    (_PRFT_LOCAL[:primitives])[:printed_output] = (_PRFT_LOCAL[:additional])[:printed_output]
                                    (_PRFT_LOCAL[:primitives])[:iterator] = (_PRFT_LOCAL[:additional])[:iterator]
                                    (_PRFT_LOCAL[:metrics])[:opInt] = Metric_Result("Operational intensity", "Flop/Byte", 3 + 1)
                                    (_PRFT_LOCAL[:metrics])[:attainedFLOPS] = Metric_Result("Attained Flops", "FLOP/s", 1000000 / (_PRFT_LOCAL[:primitives])[:median_time])
                                    let
                                        opint = ((_PRFT_LOCAL[:metrics])[:opInt]).value
                                        flop_s = ((_PRFT_LOCAL[:metrics])[:attainedFLOPS]).value
                                        roof = PerfTest.rooflineCalc(((_PRFT_GLOBAL[:machine])[:empirical])[:peakflops], ((_PRFT_GLOBAL[:machine])[:empirical])[:peakmemBW])
                                        result_flop_ratio = Metric_Result(name = "Attained FLOP/S by expected FLOP/S", units = "%", value = flop_s / roof(opint))
                                        methodology_res = Methodology_Result(name = "Roofline Model")
                                        success_flop = result_flop_ratio.value >= 0.05
                                        flop_test = Metric_Test(reference = 100, threshold_min_percent = 0.05, threshold_max_percent = nothing, low_is_bad = true, succeeded = success_flop, custom_plotting = Symbol[], full_print = true)
                                        push!(methodology_res.metrics, result_flop_ratio => flop_test)
                                        methodology_res.custom_elements[:realf] = (_PRFT_LOCAL[:metrics])[:attainedFLOPS]
                                        methodology_res.custom_elements[:opint] = (_PRFT_LOCAL[:metrics])[:opInt]
                                        aux_mem = Metric_Result(name = "Peak empirical bandwidth", units = "GB/s", value = ((_PRFT_GLOBAL[:machine])[:empirical])[:peakmemBW])
                                        aux_flops = Metric_Result(name = "Peak empirical flops", units = "GFLOP/s", value = ((_PRFT_GLOBAL[:machine])[:empirical])[:peakflops])
                                        aux_rcorner = Metric_Result(name = "Roofline Corner", units = "Flop/Byte", value = aux_flops.value / aux_mem.value)
                                        methodology_res.custom_elements[:mem_peak] = aux_mem
                                        methodology_res.custom_elements[:cpu_peak] = aux_flops
                                        methodology_res.custom_elements[:roof_corner] = aux_rcorner
                                        methodology_res.custom_elements[:factor] = 0.05
                                        methodology_res.custom_elements[:plot] = PerfTest.printFullRoofline
                                        PerfTest.printMethodology(methodology_res, 2)
                                        @test flop_test.succeeded
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
nothing
if !failed
    PerfTest.saveDataFile(path, _PRFT_GLOBAL[:datafile])
end
println("[✓] $(path) Performance tests have been finished")
end