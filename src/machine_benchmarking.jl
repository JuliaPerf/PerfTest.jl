

#using MPI
# Memory and CPU benchmarks used by different methodologies

function getMachineInfo()::Expr
    quote
        size = try
            CpuId.cachesize()
        catch
            # Default assumes 25MB (usually too much)
            [12 * 1024 * 1024]
        end
        @info "Measuring with buffer size: $(size .* 8 ./ 1024 ./ 1024) MB"
        global _PRFT_GLOBAL[:machine][:cache_sizes] = size
    end
end

function measureCPUPeakFlops!(::Type{<:NormalMode}, _PRFT_GLOBAL::Dict{Symbol,Any})
    LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
    # In Flop/s
    _PRFT_GLOBAL[:machine][:empirical][:peakflops] = LinearAlgebra.peakflops(; parallel=true)
end

function measureMemBandwidth!(::Type{<:NormalMode}, _PRFT_GLOBAL::Dict{Symbol,Any})
    bench_data = STREAMBenchmark.benchmark(N = div(_PRFT_GLOBAL[:machine][:cache_sizes][end], 2))
    # In B/s
    peakbandwidth = bench_data.multi.maximum * 1e6
    _PRFT_GLOBAL[:machine][:empirical][:peakmemBW] = peakbandwidth
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
