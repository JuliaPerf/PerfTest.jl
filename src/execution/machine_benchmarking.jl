
# Memory and CPU benchmarks used by different methodologies

function getMachineInfo()::Expr
    if Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"] == 0
        return quote
            size = try
                CpuId.cachesize()
            catch
                addLog("machine", "[MACHINE] CpuId failed, using default cache size")
                [1024 * 1024 * 16]
            end
            global _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = size

            addLog("machine", "[MACHINE] Memory buffer size for benchmarking = $(size ./ 1024 ./ 1024) [MB]")
        end
    else
	return quote
            global _PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES] = [$(Configuration.CONFIG["machine_benchmarking"]["memory_bandwidth_test_buffer_size"])]

	    addLog("machine", "[MACHINE] Set by config, benchmark buffer size = $(_PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES][1] ./ 1024 ./ 1024) [MB]")
        end
    end
end

function measureCPUPeakFlops!(::Type{<:NormalMode}, _PRFT_GLOBALS::GlobalSuiteData)
    LinearAlgebra.BLAS.set_num_threads(Threads.nthreads())
    # In Flop/s
    _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK] = LinearAlgebra.peakflops(; parallel=true)
    addLog("machine", "[MACHINE] CPU max attainable flops = $(_PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]) [FLOP/S]")
end

using Base.Threads

copy_kernel(C,A;kwargs...) = STREAMBenchmark.copy_nthreads(C,A;kwargs...)
add_kernel(C,A,B;kwargs...) = STREAMBenchmark.add_nthreads(C,A,B;kwargs...)

# This function is heavily based on the respective from STREAMBenchmark
function _run_kernels(copy, add;
                      verbose = true,
                      N,
                      evals_per_sample = 10,
                      write_allocate = true,
                      nthreads = Threads.nthreads(),
                      init = :parallel)
    α = write_allocate ? 24 : 16
    β = write_allocate ? 32 : 24

    f = t -> N * α / t
    g = t -> N * β / t

    # N / nthreads if necessary
    thread_indices = STREAMBenchmark._threadidcs(N, nthreads)

    # initialize memory
    if init == :parallel
        A = Vector{Float64}(undef, N)
        B = Vector{Float64}(undef, N)
        C = Vector{Float64}(undef, N)
        s = rand()

        # fill in parallel (important for NUMA mapping / first-touch policy)
        @threads :static for tid in 1:nthreads
            @inbounds for i in thread_indices[tid]
                A[i] = 0.0
                B[i] = 0.0
                C[i] = 0.0
            end
        end
    else
        A = zeros(N)
        B = zeros(N)
        C = zeros(N)
        s = rand()
    end

    # COPY
    t_copy = @belapsed $copy($C, $A; nthreads = $nthreads, thread_indices = $thread_indices) samples=10 evals=evals_per_sample
    bw_copy = f(t_copy)

    # ADD
    t_add = @belapsed $add($C, $A, $B; nthreads = $nthreads,
        thread_indices=$thread_indices) samples = 10 evals = evals_per_sample
    bw_add = g(t_add)

    return (bw_copy,bw_add)
end


function measureMemBandwidth!(::Type{<:NormalMode}, _PRFT_GLOBALS::GlobalSuiteData)
    bench_data = _run_kernels(copy_kernel, add_kernel; N=div(_PRFT_GLOBALS.builtins[:MEM_CACHE_SIZES][end], 2))
    # in Bytes/sec
    peakbandwidth = bench_data
    _PRFT_GLOBALS.builtins[:MEM_STREAM] = peakbandwidth
    _PRFT_GLOBALS.builtins[:MEM_STREAM_COPY] = peakbandwidth[1]
    _PRFT_GLOBALS.builtins[:MEM_STREAM_ADD] = peakbandwidth[2]
    addLog("machine", "[MACHINE] CPU max attainable bandwidth = $(_PRFT_GLOBALS.builtins[:MEM_STREAM]) [Byte/s]")
end


function machineBenchmarks()::Expr
    quote
	      # Block to create a separated scope
        let
            $(getMachineInfo())
            measureCPUPeakFlops!($mode, _PRFT_GLOBALS)
            measureMemBandwidth!($mode, _PRFT_GLOBALS)
        end
    end
end
