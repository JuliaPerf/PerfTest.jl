

# Memory and CPU benchmarks used by different methodologies

function getMachineInfo()::Expr
    quote
        size = try
            CpuId.cachesize()
        catch
            addLog("machine", "[MACHINE] CpuId failed, using default cache size")
            # Default assumes 25MB (usually too much)
            [12 * 1024 * 1024]
        end
        global _PRFT_GLOBAL[:machine][:cache_sizes] = size

        addLog("machine", "[MACHINE] Assumed CPU cache size = $(size ./ 1024 ./ 1024) [MB]")
    end
end

function measureCPUPeakFlops!(::Type{<:NormalMode}, _PRFT_GLOBAL::Dict{Symbol,Any})
    LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
    # In Flop/s
    _PRFT_GLOBAL[:machine][:empirical][:peakflops] = LinearAlgebra.peakflops(; parallel=true)
    addLog("machine", "[MACHINE] CPU max attainable flops = $(_PRFT_GLOBAL[:machine][:empirical][:peakflops]) [FLOP]")
end

function measureMemBandwidth!(::Type{<:NormalMode}, _PRFT_GLOBAL::Dict{Symbol,Any})
    bench_data = STREAMBenchmark.memory_bandwidth(N=div(_PRFT_GLOBAL[:machine][:cache_sizes][end], 2))
    # In B/s
    peakbandwidth = bench_data.maximum * 1e6
    _PRFT_GLOBAL[:machine][:empirical][:peakmemBW] = peakbandwidth
    addLog("machine", "[MACHINE] CPU max attainable bandwidth = $(_PRFT_GLOBAL[:machine][:empirical][:peakmemBW]) [Byte/s]")
end


function machineBenchmarks()::Expr
    quote
	      # Block to create a separated scope
        let
            _PRFT_GLOBAL[:machine] = Dict{Symbol,Any}()
            _PRFT_GLOBAL[:machine][:empirical] = Dict{Symbol,Any}()
            $(getMachineInfo())
            measureCPUPeakFlops!($mode, _PRFT_GLOBAL)
            measureMemBandwidth!($mode, _PRFT_GLOBAL)
        end
    end
end
