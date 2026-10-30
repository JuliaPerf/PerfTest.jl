module __PERFTEST__
using Test
using PerfTest
using CUDA
Core.@doc "    LlamaFFI\n\nMinimal, self-contained in-process `ccall` binding to a **CUDA-enabled** build of\n`libllama` (llama.cpp). This is the layer that lets PerfTest.jl bracket real\n`llama_decode` calls with NVML energy readings *in the same process as the tests*.\n\nWHY A CUSTOM BUILD?\n-------------------\nThe registered `llama_cpp_jll` artifact ships **CPU-only** binaries (no\n`libggml_cuda`, no CUDA dependency). To measure GPU energy of llama.cpp inference\nyou MUST build llama.cpp yourself with `-DGGML_CUDA=ON` and point this module at\nthe resulting `libllama.so` via the `LLAMA_LIB` environment variable\n(see `build_llama_cuda.sh`).\n\nSTATUS: PRELIMINARY DRAFT\n-------------------------\nThis binding targets a recent llama.cpp C API (the `llama_model_load_from_file` /\n`llama_init_from_model` generation, roughly late-2024/2025 API). The llama.cpp C\nAPI and, especially, the *layout* of `llama_model_params` / `llama_context_params`\nchange across commits. The struct mirrors below MUST be verified against the exact\ncommit you build (`llama.h`). For a robust binding, regenerate with `Clang.jl`\nagainst your pinned `llama.h`. The functions used here are intentionally a minimal\nsubset so that verification is quick.\n\nGreedy (argmax) decoding is implemented directly in Julia over the returned logits\nso we do not depend on the (frequently changing) sampler-chain API. Greedy keeps\ngeneration deterministic, which is important for a controlled energy study.\n" module LlamaFFI
    using Libdl
    const LIBLLAMA = Ref{String}("")
    const LIBHANDLE = Ref{Ptr{Cvoid}}(C_NULL)
    Core.@doc "    lib()\n\nPath to the CUDA-enabled `libllama`. Resolved from the `LLAMA_CPP_LIB`\nenvironment variable the first time it is needed. Also caches the dlopen handle\nso we can probe for version-dependent symbols with [`sym`](@ref).\n" function lib()
            if isempty(LIBLLAMA[])
                path = get(ENV, "LLAMA_LIB", "")
                isempty(path) && error("Set LLAMA_LIB to your CUDA-enabled libllama (e.g. " * "/path/to/llama.cpp/build/bin/libllama.so). See build_llama_cuda.sh.")
                isfile(path) || error("LLAMA_LIB does not point to a file: $(path)")
                LIBHANDLE[] = Libdl.dlopen(path, Libdl.RTLD_LAZY | Libdl.RTLD_GLOBAL)
                LIBLLAMA[] = path
            end
            return LIBLLAMA[]
        end
    Core.@doc "Resolve a symbol pointer, or C_NULL if this llama.cpp build does not export it." function sym(name::Symbol)
            lib()
            return Libdl.dlsym(LIBHANDLE[], name; throw_error = false)
        end
    const LlamaToken = Int32
    const LlamaPos = Int32
    const LlamaSeqId = Int32
    struct LlamaModelParams
        devices::Ptr{Cvoid}
        tensor_buft_overrides::Ptr{Cvoid}
        n_gpu_layers::Cint
        split_mode::Cint
        load_mode::Cint
        main_gpu::Cint
        tensor_split::Ptr{Cfloat}
        progress_callback::Ptr{Cvoid}
        progress_callback_ud::Ptr{Cvoid}
        kv_overrides::Ptr{Cvoid}
        vocab_only::Bool
        check_tensors::Bool
        use_extra_bufts::Bool
        no_host::Bool
        no_alloc::Bool
        load_mtp::Bool
    end
    const LLAMA_FLASH_ATTN_TYPE_DISABLED = Cint(0)
    const LLAMA_FLASH_ATTN_TYPE_ENABLED = Cint(1)
    struct LlamaContextParams
        n_ctx::Cuint
        n_batch::Cuint
        n_ubatch::Cuint
        n_seq_max::Cuint
        n_rs_seq::Cuint
        n_outputs_max::Cuint
        n_threads::Cint
        n_threads_batch::Cint
        ctx_type::Cint
        rope_scaling_type::Cint
        pooling_type::Cint
        attention_type::Cint
        flash_attn_type::Cint
        rope_freq_base::Cfloat
        rope_freq_scale::Cfloat
        yarn_ext_factor::Cfloat
        yarn_attn_factor::Cfloat
        yarn_beta_fast::Cfloat
        yarn_beta_slow::Cfloat
        yarn_orig_ctx::Cuint
        defrag_thold::Cfloat
        cb_eval::Ptr{Cvoid}
        cb_eval_ud::Ptr{Cvoid}
        type_k::Cint
        type_v::Cint
        abort_callback::Ptr{Cvoid}
        abort_callback_data::Ptr{Cvoid}
        embeddings::Bool
        offload_kqv::Bool
        no_perf::Bool
        op_offload::Bool
        swa_full::Bool
        kv_unified::Bool
        samplers::Ptr{Cvoid}
        n_samplers::Csize_t
        ctx_other::Ptr{Cvoid}
    end
    struct LlamaBatch
        n_tokens::Cint
        token::Ptr{LlamaToken}
        embd::Ptr{Cfloat}
        pos::Ptr{LlamaPos}
        n_seq_id::Ptr{Cint}
        seq_id::Ptr{Ptr{LlamaSeqId}}
        logits::Ptr{Int8}
    end
    backend_init() = ccall((:llama_backend_init, lib()), Cvoid, ())
    backend_free() = ccall((:llama_backend_free, lib()), Cvoid, ())
    model_default_params() = ccall((:llama_model_default_params, lib()), LlamaModelParams, ())
    context_default_params() = ccall((:llama_context_default_params, lib()), LlamaContextParams, ())
    Core.@doc "    load_model(path; n_gpu_layers=999) -> Ptr\n\nLoad a GGUF model with the requested number of layers offloaded to the GPU.\n`n_gpu_layers=999` means \"offload everything\".\n" function load_model(path::AbstractString; n_gpu_layers::Integer = 999)
            p = model_default_params()
            p = LlamaModelParams(p.devices, p.tensor_buft_overrides, Cint(n_gpu_layers), Cint(0), p.load_mode, Cint(0), p.tensor_split, p.progress_callback, p.progress_callback_ud, p.kv_overrides, p.vocab_only, p.check_tensors, p.use_extra_bufts, p.no_host, p.no_alloc, p.load_mtp)
            m = ccall((:llama_model_load_from_file, lib()), Ptr{Cvoid}, (Cstring, LlamaModelParams), path, p)
            m == C_NULL && error("Failed to load model: $(path)")
            return m
        end
    function new_context(model::Ptr{Cvoid}; n_ctx::Integer = 4096, n_batch::Integer = 2048, flash_attn::Bool = true, n_threads::Integer = Sys.CPU_THREADS)
        p = context_default_params()
        p = LlamaContextParams(Cuint(n_ctx), Cuint(n_batch), p.n_ubatch, p.n_seq_max, p.n_rs_seq, p.n_outputs_max, Cint(n_threads), Cint(n_threads), p.ctx_type, p.rope_scaling_type, p.pooling_type, p.attention_type, if flash_attn
                    LLAMA_FLASH_ATTN_TYPE_ENABLED
                else
                    LLAMA_FLASH_ATTN_TYPE_DISABLED
                end, p.rope_freq_base, p.rope_freq_scale, p.yarn_ext_factor, p.yarn_attn_factor, p.yarn_beta_fast, p.yarn_beta_slow, p.yarn_orig_ctx, p.defrag_thold, p.cb_eval, p.cb_eval_ud, p.type_k, p.type_v, p.abort_callback, p.abort_callback_data, p.embeddings, p.offload_kqv, p.no_perf, p.op_offload, p.swa_full, p.kv_unified, p.samplers, p.n_samplers, p.ctx_other)
        ctx = ccall((:llama_init_from_model, lib()), Ptr{Cvoid}, (Ptr{Cvoid}, LlamaContextParams), model, p)
        ctx == C_NULL && error("Failed to create context")
        return ctx
    end
    free_model(model::Ptr{Cvoid}) = ccall((:llama_model_free, lib()), Cvoid, (Ptr{Cvoid},), model)
    free_context(ctx::Ptr{Cvoid}) = ccall((:llama_free, lib()), Cvoid, (Ptr{Cvoid},), ctx)
    get_vocab(model::Ptr{Cvoid}) = ccall((:llama_model_get_vocab, lib()), Ptr{Cvoid}, (Ptr{Cvoid},), model)
    n_vocab(vocab::Ptr{Cvoid}) = Int(ccall((:llama_vocab_n_tokens, lib()), Cint, (Ptr{Cvoid},), vocab))
    model_size_bytes(model::Ptr{Cvoid}) = Int(ccall((:llama_model_size, lib()), UInt64, (Ptr{Cvoid},), model))
    function tokenize(vocab::Ptr{Cvoid}, text::AbstractString; add_special::Bool = true, parse_special::Bool = true)
        cap = ncodeunits(text) + 16
        toks = Vector{LlamaToken}(undef, cap)
        n = ccall((:llama_tokenize, lib()), Cint, (Ptr{Cvoid}, Cstring, Cint, Ptr{LlamaToken}, Cint, Bool, Bool), vocab, text, ncodeunits(text), toks, cap, add_special, parse_special)
        n < 0 && error("tokenize: buffer too small (needed $(-n))")
        return toks[1:n]
    end
    is_eog(vocab::Ptr{Cvoid}, tok::LlamaToken) = ccall((:llama_vocab_is_eog, lib()), Bool, (Ptr{Cvoid}, LlamaToken), vocab, tok)
    batch_get_one(tokens::Vector{LlamaToken}) = ccall((:llama_batch_get_one, lib()), LlamaBatch, (Ptr{LlamaToken}, Cint), tokens, Cint(length(tokens)))
    function decode!(ctx::Ptr{Cvoid}, batch::LlamaBatch)
        rc = ccall((:llama_decode, lib()), Cint, (Ptr{Cvoid}, LlamaBatch), ctx, batch)
        rc != 0 && error("llama_decode failed: rc=$(rc)")
        return nothing
    end
    function logits_ith(ctx::Ptr{Cvoid}, i::Integer, nvoc::Integer)
        p = ccall((:llama_get_logits_ith, lib()), Ptr{Cfloat}, (Ptr{Cvoid}, Cint), ctx, Cint(i))
        p == C_NULL && error("llama_get_logits_ith returned NULL")
        return unsafe_wrap(Array, p, nvoc)
    end
    argmax_token(logits::AbstractVector{<:Real}) = LlamaToken(argmax(logits) - 1)
    Core.@doc "    Session\n\nHolds a loaded model + context and cached vocab size. Create once per\nquantization level, reuse for warmup + measurement runs.\n" mutable struct Session
            model::Ptr{Cvoid}
            ctx::Ptr{Cvoid}
            vocab::Ptr{Cvoid}
            nvoc::Int
        end
    binit = false
    function open_session(gguf_path::AbstractString; n_gpu_layers = 999, n_ctx = 4096, flash_attn = true)
        backend_init()
        model = load_model(gguf_path; n_gpu_layers = n_gpu_layers)
        ctx = new_context(model; n_ctx = n_ctx, flash_attn = flash_attn)
        vocab = get_vocab(model)
        return Session(model, ctx, vocab, n_vocab(vocab))
    end
    function close_session(s::Session)
        free_context(s.ctx)
        free_model(s.model)
        backend_free()
        return nothing
    end
    const _RESET_KIND = Ref{Symbol}(:unresolved)
    function _resolve_reset()
        if sym(:llama_get_memory) != C_NULL && sym(:llama_memory_clear) != C_NULL
            _RESET_KIND[] = :memory
        elseif sym(:llama_kv_self_clear) != C_NULL
            _RESET_KIND[] = :kv_self
        elseif sym(:llama_kv_cache_clear) != C_NULL
            _RESET_KIND[] = :kv_cache
        else
            error("No known KV-cache clear symbol found in libllama; check your version.")
        end
        return _RESET_KIND[]
    end
    Core.@doc "    reset!(s)\n\nClear the context KV cache so the next `prefill!`/`decode_n!` starts from a\nclean state. This is the key to idempotent, repeatable measurements.\n" function reset!(s::Session)
            _RESET_KIND[] == :unresolved && _resolve_reset()
            if _RESET_KIND[] == :memory
                mem = ccall((:llama_get_memory, lib()), Ptr{Cvoid}, (Ptr{Cvoid},), s.ctx)
                ccall((:llama_memory_clear, lib()), Cvoid, (Ptr{Cvoid}, Bool), mem, true)
            elseif _RESET_KIND[] == :kv_self
                ccall((:llama_kv_self_clear, lib()), Cvoid, (Ptr{Cvoid},), s.ctx)
            else
                ccall((:llama_kv_cache_clear, lib()), Cvoid, (Ptr{Cvoid},), s.ctx)
            end
            return nothing
        end
    const _MODEL_FREE_KIND = Ref{Symbol}(:unresolved)
    function _resolve_model_free()
        if sym(:llama_model_free) != C_NULL
            _MODEL_FREE_KIND[] = :new
        elseif sym(:llama_free_model) != C_NULL
            _MODEL_FREE_KIND[] = :old
        else
            error("No known model-free symbol found in libllama; check your version.")
        end
        return _MODEL_FREE_KIND[]
    end
    Core.@doc "    destroy!(s::Session)\n\nFree the context (KV cache + compute buffers) and the model (tensor weight\nbuffers) that were allocated on the GPU for this Session. `reset!` alone only\nclears KV-cache *contents*; it never releases the VRAM allocations, which is\nwhy memory climbs across models unless this is called too.\n\n`s.vocab` is *not* freed here — it's a pointer owned by the model\n(`llama_model_get_vocab`), not a separate allocation, and becomes invalid\nautomatically once `s.model` is freed.\n\nSafe to call multiple times; no-ops once fields are already null.\n" function destroy!(s::Session)
            if s.ctx != C_NULL
                ccall((:llama_free, lib()), Cvoid, (Ptr{Cvoid},), s.ctx)
                s.ctx = C_NULL
            end
            if s.model != C_NULL
                _MODEL_FREE_KIND[] == :unresolved && _resolve_model_free()
                if _MODEL_FREE_KIND[] == :new
                    ccall((:llama_model_free, lib()), Cvoid, (Ptr{Cvoid},), s.model)
                else
                    ccall((:llama_free_model, lib()), Cvoid, (Ptr{Cvoid},), s.model)
                end
                s.model = C_NULL
            end
            s.vocab = C_NULL
            s.nvoc = 0
            GC.gc()
            return nothing
        end
    Core.@doc "    prefill!(s, prompt) -> (last_token, n_prompt_tokens)\n\nRun the prompt through the model in a single batch (the \"prefill\" / prompt\nprocessing phase). Returns the greedily-selected first generated token and the\nnumber of prompt tokens.\n\nNOTE: this is a **stateful** primitive — it appends to the KV cache. Call\n[`reset!`](@ref) first if you need a clean state. For measurement targets use\nthe idempotent [`generate!`](@ref) / [`prefill_only!`](@ref) instead.\n" function prefill!(s::Session, prompt::AbstractString)
            toks = tokenize(s.vocab, prompt)
            decode!(s.ctx, batch_get_one(toks))
            next = argmax_token(logits_ith(s.ctx, -1, s.nvoc))
            return (next, length(toks))
        end
    Core.@doc "    decode_n!(s, first_token, n) -> n_generated\n\nAutoregressively generate up to `n` tokens starting from `first_token`\n(greedy), stopping early on EOG.\n\nNOTE: **stateful** — advances the KV cache. Not idempotent on its own; use it\nvia [`generate!`](@ref) for repeatable measurements.\n" function decode_n!(s::Session, first_token::LlamaToken, n::Integer)
            tok = first_token
            generated = 0
            scratch = LlamaToken[0]
            for _ = 1:n
                is_eog(s.vocab, tok) && break
                generated += 1
                scratch[1] = tok
                decode!(s.ctx, batch_get_one(scratch))
                tok = argmax_token(logits_ith(s.ctx, -1, s.nvoc))
            end
            return generated
        end
    Core.@doc "    generate!(s, prompt, n_gen) -> n_generated\n\nIdempotent full request: clear KV cache, prefill `prompt`, then greedily decode\nup to `n_gen` tokens. Safe to call repeatedly. This is the primary measured\ntarget; whole-request energy divided by `n_generated` gives Joules per token.\n" function generate!(s::Session, prompt::AbstractString, n_gen::Integer)
            reset!(s)
            (first_tok, _) = prefill!(s, prompt)
            return decode_n!(s, first_tok, n_gen)
        end
    Core.@doc "    prefill_only!(s, prompt) -> n_prompt_tokens\n\nIdempotent prefill: clear KV cache and process the prompt only. Measure this as\na second target to isolate prefill energy, so decode energy ≈ generate! energy −\nprefill_only! energy.\n" function prefill_only!(s::Session, prompt::AbstractString)
            reset!(s)
            (_, n_prompt) = prefill!(s, prompt)
            return n_prompt
        end
    end
PerfTest._perftest_config("[perfcompare]\nenabled = true\n\n[MPI]\nmode = \"reduce\"\nenabled = false\n\n[general]\nsave_results = true\nmax_saved_results = 20\nsuppress_output = true\nsave_folder = \".perftests\"\nthreads_per_numa = \"single\"\nrecursive = true\nverbose = 3\nautoflops = false\nplotting = true\nnumas = \"single\"\nlogs_enabled = true\nsafe_formulas = false\n\n[regression]\nenabled = false\ndedicated_reference_file = \"\"\ndefault_threshold = 1.1\nuse_bencher = false\n\n[roofline]\nenabled = true\ndefault_threshold = 0.5\n\n[memory_bandwidth]\nenabled = true\ndefault_threshold = 0.5\n\n[machine_benchmarking]\nmemory_bandwidth_test_buffer_size = 0\n\n[bencher]\napi_key = \"\"\norganization = \"\"\napi_url = \"https://api.bencher.dev\"\nproject_name = \"\"\ncustom_testbed_name = \"\"\n\n[cuda]\nenabled = true\n")
const MODEL_DIR = get(ENV, "MODEL_DIR", joinpath(@__DIR__(), "models"))
const MODEL_BASE = get(ENV, "MODEL_BASE", "Qwen3.8-27B")
const QUANTS = ["UD-Q2_K_XL", "UD-Q3_K_XL", "UD-Q4_K_M", "UD-Q5_K_M", "UD-Q6_K", "Q8_0", "f16"]
const PROMPT = "Explain, in a single detailed paragraph, why energy efficiency " * "is becoming the dominant cost metric for large language model " * "inference in production data centers."
const N_GEN = 256
quant_path(q) = joinpath(MODEL_DIR, "$(MODEL_BASE)-$(q).gguf")
const LLAMA_PERPLEXITY_BIN = get(ENV, "LLAMA_PERPLEXITY_BIN", joinpath(dirname(get(ENV, "LLAMA_LIB", "")), "llama-perplexity"))
const PPL_CORPUS = joinpath(get(ENV, "MODEL_DIR", @__DIR__()), "wikitext-2-raw", "wiki.test.raw")
const PPL_CTX = 512
Core.@doc "    run_llama_perplexity(model_path) -> Float64\n\nRun `llama-perplexity` on `PPL_CORPUS` against the GGUF at `model_path` and\nparse its \"Final estimate: PPL = ...\" line. Returns `NaN` (with a `@warn`) if\nthe binary or corpus is missing, so the sweep still runs without the quality\naxis.\n" function run_llama_perplexity(model_path::AbstractString)
        if !(isfile(LLAMA_PERPLEXITY_BIN))
            @warn "llama-perplexity binary not found, skipping perplexity" bin = LLAMA_PERPLEXITY_BIN
            return NaN
        end
        if !(isfile(PPL_CORPUS))
            @warn "Perplexity corpus not found, skipping perplexity" corpus = PPL_CORPUS
            return NaN
        end
        cmd = `$LLAMA_PERPLEXITY_BIN -m $model_path -f $PPL_CORPUS -c $PPL_CTX --n-gpu-layers 999`
        out = read(cmd, String)
        m = match(r"Final estimate: PPL = ([0-9.]+)", out)
        m === nothing && error("Could not parse PPL from llama-perplexity output:\n$(out)")
        return parse(Float64, m.captures[1])
    end
using Test, Dates
nothing
using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTCount_ops, PRFTflop, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData, Configuration, metricSampledValue, SampledValue
_t_begin = time()
_GLOBAL_MODE = PerfTest.NormalMode
if main_rank(PerfTest.NormalMode)
    path = "./.perftests/llama_energy_test.jl_PERFORMANCE.JLD2"
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
    _PRFT_GLOBALS = GlobalSuiteData(datafile, path, "llama_energy_test.jl")
    if length(regression_file.results) > 0
        for i = length(regression_file.results):-1:1
            if length(retrievePerfTests(regression_path, get = :tests, where_pred = testFailed, execution = i)) == 0
                _PRFT_GLOBALS.old = (regression_file.results[i]).perftests
                println("Regression: Previous performance reference for this configuration has been found, regression tests could be performed. Regression is currenctly $(if false
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
TS = @perftestset(PerfTestSet, "Llama.cpp energy efficiency vs quantization", begin
            local ts = Test.get_testset()
            ts.old_test_results = _PRFT_GLOBALS.old
            nothing
            TS = @perftestset(PerfTestSet, "quant = ", for q = QUANTS
                        local ts = Test.get_testset()
                        ts.iterator = q
                        nothing
                        global s = nothing
                        n_prompt = 0
                        ppl = NaN
                        path = quant_path(q)
                        if !(isfile(path))
                            @warn "Missing GGUF, skipping" quant = q path = path
                            continue
                        end
                        s = LlamaFFI.open_session(path; n_gpu_layers = 999, n_ctx = 4096)
                        LlamaFFI.generate!(s, PROMPT, 8)
                        n_prompt = LlamaFFI.prefill_only!(s, PROMPT)
                        @info (N_GEN, n_prompt, q)
                        nothing
                        nothing
                        nothing
                        nothing
                        nothing
                        nothing
                        @define_test_metric name = "Energy budget" units = "J/token" reference = 0.5 low_is_bad = false :gpue / N_GEN
                        ts.benchmarks["Test 1"] = @PRFTBenchmark(($LlamaFFI).generate!($s, $PROMPT, $N_GEN), samples = 1, evals = 1, seconds = 120)
                        extensions = PerfTest.ExtensionData[]
                        push!(extensions, PerfTest.NoExtensionData())
                        @info PerfTest.cuda_devices()
                        (energy, power) = begin
                                devs = PerfTest.cuda_devices()
                                nsamples = max(1, length(ts.benchmarks["Test 1"]))
                                energy_samples = Vector{Vector{Float64}}()
                                for _s = 1:nsamples
                                    CUDA.synchronize()
                                    pre = []
                                    for d = devs
                                        push!(pre, PerfTest.read_joule(d))
                                    end
                                    LlamaFFI.generate!(s, PROMPT, N_GEN)
                                    CUDA.synchronize()
                                    post = []
                                    for d = devs
                                        push!(post, PerfTest.read_joule(d))
                                    end
                                    push!(energy_samples, Float64.(post .- pre))
                                end
                                energy = [let dev_samples = Float64[(energy_samples[s])[d] for s = 1:nsamples]
                                        if nsamples >= PerfTest.MIN_VARIANCE_SAMPLES
                                            PerfTest.SampledValue(dev_samples, PerfTest._sample_median(dev_samples))
                                        else
                                            PerfTest._sample_median(dev_samples)
                                        end
                                    end for d = eachindex(devs)]
                                power = energy
                                @info (energy, power)
                                (energy, power)
                            end
                        push!(extensions, PerfTest.CUDAExtensionData(energy, power))
                        push!(extensions, PerfTest.NoExtensionData())
                        test_res = Test_Result("Test 1", extensions)
                        ts.test_results["Test 1"] = test_res
                        keys = ["Llama.cpp energy efficiency vs quantization", string("quant = ", "_", q)]
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
                        test_res.primitives[:printed_output] = @PRFTCapture_out(test_res.primitives[:ret_value] = LlamaFFI.generate!(s, PROMPT, N_GEN))
                        buildPrimitiveMetrics!(PerfTest.NormalMode, ts, test_res)
                        let m = newMetricResult(PerfTest.NormalMode, name = "Energy/token", units = "J/token", value = if haskey(_PRFT_GLOBALS.custom_benchmarks, :gpue)
                                                PerfTest.metricSampledValue(_PRFT_GLOBALS.custom_benchmarks[:gpue])
                                            else
                                                if haskey(_PRFT_GLOBALS.builtins, :gpue)
                                                    _PRFT_GLOBALS.builtins[:gpue]
                                                else
                                                    if haskey(test_res.metrics, :gpue)
                                                        PerfTest.metricSampledValue(test_res.metrics[:gpue])
                                                    else
                                                        if haskey(test_res.auxiliar, :gpue)
                                                            PerfTest.metricSampledValue(test_res.auxiliar[:gpue])
                                                        else
                                                            sum((test_res.extensions[2]).energy)
                                                        end
                                                    end
                                                end
                                            end / N_GEN, auxiliary = true, showvar = false)
                            test_res.auxiliar[Symbol("Energy/token")] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Efficiency", units = "token/J", value = N_GEN / if haskey(_PRFT_GLOBALS.custom_benchmarks, :gpue)
                                                PerfTest.metricSampledValue(_PRFT_GLOBALS.custom_benchmarks[:gpue])
                                            else
                                                if haskey(_PRFT_GLOBALS.builtins, :gpue)
                                                    _PRFT_GLOBALS.builtins[:gpue]
                                                else
                                                    if haskey(test_res.metrics, :gpue)
                                                        PerfTest.metricSampledValue(test_res.metrics[:gpue])
                                                    else
                                                        if haskey(test_res.auxiliar, :gpue)
                                                            PerfTest.metricSampledValue(test_res.auxiliar[:gpue])
                                                        else
                                                            sum((test_res.extensions[2]).energy)
                                                        end
                                                    end
                                                end
                                            end, auxiliary = true, showvar = false)
                            test_res.auxiliar[:Efficiency] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Energy", units = "W", value = if haskey(_PRFT_GLOBALS.custom_benchmarks, :gpue)
                                            PerfTest.metricSampledValue(_PRFT_GLOBALS.custom_benchmarks[:gpue])
                                        else
                                            if haskey(_PRFT_GLOBALS.builtins, :gpue)
                                                _PRFT_GLOBALS.builtins[:gpue]
                                            else
                                                if haskey(test_res.metrics, :gpue)
                                                    PerfTest.metricSampledValue(test_res.metrics[:gpue])
                                                else
                                                    if haskey(test_res.auxiliar, :gpue)
                                                        PerfTest.metricSampledValue(test_res.auxiliar[:gpue])
                                                    else
                                                        sum((test_res.extensions[2]).energy)
                                                    end
                                                end
                                            end
                                        end, auxiliary = true, showvar = false)
                            test_res.auxiliar[:Energy] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Time", units = "s", value = test_res.primitives[:median_time], auxiliary = true, showvar = false)
                            test_res.auxiliar[:Time] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Throughput", units = "token/s", value = N_GEN / test_res.primitives[:median_time], auxiliary = true, showvar = false)
                            test_res.auxiliar[:Throughput] = m
                        end
                        let m = newMetricResult(PerfTest.NormalMode, name = "Perplexity", units = "ppl", value = ppl, auxiliary = true, showvar = false)
                            test_res.auxiliar[:Perplexity] = m
                        end
                        if main_rank(PerfTest.NormalMode)
                        end
                        s === nothing || LlamaFFI.destroy!(s)
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