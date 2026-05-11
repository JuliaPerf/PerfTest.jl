
# Memory and CPU benchmarks used by different methodologies
function measureCPUPeakFlops!(::Type{<:NormalMode}, _PRFT_GLOBALS::GlobalSuiteData)
    LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
    # In Flop/s
    _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK] = LinearAlgebra.peakflops(; parallel=true)
    addLog("machine", "[MACHINE] CPU max attainable flops = $(_PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]) [FLOP/S]")
end

using Base.Threads
using BandwidthBenchmark

function measureMemBandwidth!(::Type{<:NormalMode}, _PRFT_GLOBALS::GlobalSuiteData)
    def = Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"]
    if def == 0
        N = _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES][1] * 4 
    else
        N = Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"]
    end
    bench_data = BandwidthBenchmark.bwbench(N = N, verbose=false)
    peakbandwidth = bench_data[!,2] * 10^6  # Convert from MB/s to Byte/s
    # in Bytes/sec
    # "Init"
    # "Copy"
    # "Update"
    # "Triad"
    # "Daxpy"
    # "STriad"
    # "SDaxpy"
    _PRFT_GLOBALS.builtins[:MEM_BENCH] = peakbandwidth
    _PRFT_GLOBALS.builtins[:MEM_BENCH_INIT] = peakbandwidth[1]
    _PRFT_GLOBALS.builtins[:MEM_BENCH_COPY] = peakbandwidth[2]
    _PRFT_GLOBALS.builtins[:MEM_BENCH_UPDATE] = peakbandwidth[3]
    _PRFT_GLOBALS.builtins[:MEM_BENCH_TRIAD] = peakbandwidth[4]
    _PRFT_GLOBALS.builtins[:MEM_BENCH_DAXPY] = peakbandwidth[5]
    _PRFT_GLOBALS.builtins[:MEM_BENCH_STRIAD] = peakbandwidth[6]
    _PRFT_GLOBALS.builtins[:MEM_BENCH_SDAXPY] = peakbandwidth[7]

    # COMPAT symbols for benchmarks:
    _PRFT_GLOBALS.builtins[:MEM_STREAM_COPY] = peakbandwidth[2]
    _PRFT_GLOBALS.builtins[:MEM_STREAM_ADD] = peakbandwidth[4]
    _PRFT_GLOBALS.builtins[:MEM_STREAM_STRIAD] = peakbandwidth[6]

    addLog("machine", "[MACHINE] CPU max attainable bandwidth = $(_PRFT_GLOBALS.builtins[:MEM_BENCH]) [Byte/s]")
end


function machineBenchmarks(mode ::Type{<:NormalMode}, ctx :: Context)::Expr
    quote
	      # Block to create a separated scope
        let
            PerfTest.Topology.getMachineTopology!()
            # First element L3, second element L2, third element L1
            _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = PerfTest.Topology.getCacheSizes()
            $(ctx._global.uses_benchmarks == Set{Symbol}() ? quote 
            end : quote
                measureCPUPeakFlops!($mode, _PRFT_GLOBALS)
                measureMemBandwidth!($mode, _PRFT_GLOBALS) 
            end)
        end
    end
end
