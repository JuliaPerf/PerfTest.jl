"""
    LlamaFFI

Minimal, self-contained in-process `ccall` binding to a **CUDA-enabled** build of
`libllama` (llama.cpp). This is the layer that lets PerfTest.jl bracket real
`llama_decode` calls with NVML energy readings *in the same process as the tests*.

WHY A CUSTOM BUILD?
-------------------
The registered `llama_cpp_jll` artifact ships **CPU-only** binaries (no
`libggml_cuda`, no CUDA dependency). To measure GPU energy of llama.cpp inference
you MUST build llama.cpp yourself with `-DGGML_CUDA=ON` and point this module at
the resulting `libllama.so` via the `LLAMA_CPP_LIB` environment variable
(see `build_llama_cuda.sh`).

STATUS: PRELIMINARY DRAFT
-------------------------
This binding targets a recent llama.cpp C API (the `llama_model_load_from_file` /
`llama_init_from_model` generation, roughly late-2024/2025 API). The llama.cpp C
API and, especially, the *layout* of `llama_model_params` / `llama_context_params`
change across commits. The struct mirrors below MUST be verified against the exact
commit you build (`llama.h`). For a robust binding, regenerate with `Clang.jl`
against your pinned `llama.h`. The functions used here are intentionally a minimal
subset so that verification is quick.

Greedy (argmax) decoding is implemented directly in Julia over the returned logits
so we do not depend on the (frequently changing) sampler-chain API. Greedy keeps
generation deterministic, which is important for a controlled energy study.
"""
module LlamaFFI

using Libdl

# ---------------------------------------------------------------------------
# Library handle
# ---------------------------------------------------------------------------

const LIBLLAMA = Ref{String}("")
const LIBHANDLE = Ref{Ptr{Cvoid}}(C_NULL)

"""
    lib()

Path to the CUDA-enabled `libllama`. Resolved from the `LLAMA_CPP_LIB`
environment variable the first time it is needed. Also caches the dlopen handle
so we can probe for version-dependent symbols with [`sym`](@ref).
"""
function lib()
    if isempty(LIBLLAMA[])
        path = get(ENV, "LLAMA_CPP_LIB", "")
        isempty(path) && error(
            "Set LLAMA_CPP_LIB to your CUDA-enabled libllama (e.g. " *
            "/path/to/llama.cpp/build/bin/libllama.so). See build_llama_cuda.sh.")
        isfile(path) || error("LLAMA_CPP_LIB does not point to a file: $path")
        # Load with RTLD_GLOBAL so the ggml/ggml-cuda backends resolve.
        LIBHANDLE[] = Libdl.dlopen(path, Libdl.RTLD_LAZY | Libdl.RTLD_GLOBAL)
        LIBLLAMA[] = path
    end
    return LIBLLAMA[]
end

"Resolve a symbol pointer, or C_NULL if this llama.cpp build does not export it."
function sym(name::Symbol)
    lib()
    return Libdl.dlsym(LIBHANDLE[], name; throw_error = false)
end

# llama_token is int32
const LlamaToken = Int32
const LlamaPos   = Int32
const LlamaSeqId = Int32

# ---------------------------------------------------------------------------
# Parameter structs  (⚠ VERIFY LAYOUT AGAINST YOUR llama.h)
# ---------------------------------------------------------------------------
# These mirror the C structs so we can call the *_default_params() functions
# (which return by value) and then tweak individual fields. Field order and
# size must exactly match the header of the commit you build.

struct LlamaModelParams
    devices               :: Ptr{Cvoid}   # ggml_backend_dev_t *
    tensor_buft_overrides :: Ptr{Cvoid}   # const llama_model_tensor_buft_override *
    n_gpu_layers          :: Cint
    split_mode            :: Cint          # enum llama_split_mode
    main_gpu              :: Cint
    tensor_split          :: Ptr{Cfloat}
    progress_callback     :: Ptr{Cvoid}
    progress_callback_ud  :: Ptr{Cvoid}
    kv_overrides          :: Ptr{Cvoid}
    vocab_only            :: Bool
    use_mmap              :: Bool
    use_mlock             :: Bool
    check_tensors         :: Bool
end

struct LlamaContextParams
    n_ctx               :: Cuint
    n_batch             :: Cuint
    n_ubatch            :: Cuint
    n_seq_max           :: Cuint
    n_threads           :: Cint
    n_threads_batch     :: Cint
    rope_scaling_type   :: Cint
    pooling_type        :: Cint
    attention_type      :: Cint
    rope_freq_base      :: Cfloat
    rope_freq_scale     :: Cfloat
    yarn_ext_factor     :: Cfloat
    yarn_attn_factor    :: Cfloat
    yarn_beta_fast      :: Cfloat
    yarn_beta_slow      :: Cfloat
    yarn_orig_ctx       :: Cuint
    defrag_thold        :: Cfloat
    cb_eval             :: Ptr{Cvoid}
    cb_eval_ud          :: Ptr{Cvoid}
    type_k              :: Cint
    type_v              :: Cint
    logits_all          :: Bool
    embeddings          :: Bool
    offload_kqv         :: Bool
    flash_attn          :: Bool
    no_perf             :: Bool
    abort_callback      :: Ptr{Cvoid}
    abort_callback_data :: Ptr{Cvoid}
end

# llama_batch is isbits (all pointers), so it can be returned/passed by value.
struct LlamaBatch
    n_tokens :: Cint
    token    :: Ptr{LlamaToken}
    embd     :: Ptr{Cfloat}
    pos      :: Ptr{LlamaPos}
    n_seq_id :: Ptr{Cint}
    seq_id   :: Ptr{Ptr{LlamaSeqId}}
    logits   :: Ptr{Int8}
end

# ---------------------------------------------------------------------------
# Backend lifecycle
# ---------------------------------------------------------------------------

backend_init() = ccall((:llama_backend_init, lib()), Cvoid, ())
backend_free() = ccall((:llama_backend_free, lib()), Cvoid, ())

# ---------------------------------------------------------------------------
# Model / context
# ---------------------------------------------------------------------------

model_default_params() = ccall((:llama_model_default_params, lib()), LlamaModelParams, ())
context_default_params() = ccall((:llama_context_default_params, lib()), LlamaContextParams, ())

"""
    load_model(path; n_gpu_layers=999) -> Ptr

Load a GGUF model with the requested number of layers offloaded to the GPU.
`n_gpu_layers=999` means "offload everything".
"""
function load_model(path::AbstractString; n_gpu_layers::Integer = 999)
    p = model_default_params()
    p = LlamaModelParams(
        p.devices, p.tensor_buft_overrides, Cint(n_gpu_layers), p.split_mode,
        p.main_gpu, p.tensor_split, p.progress_callback, p.progress_callback_ud,
        p.kv_overrides, p.vocab_only, p.use_mmap, p.use_mlock, p.check_tensors)
    m = ccall((:llama_model_load_from_file, lib()), Ptr{Cvoid}, (Cstring, LlamaModelParams), path, p)
    m == C_NULL && error("Failed to load model: $path")
    return m
end

function new_context(model::Ptr{Cvoid}; n_ctx::Integer = 4096, n_batch::Integer = 2048,
                     flash_attn::Bool = true, n_threads::Integer = Sys.CPU_THREADS)
    p = context_default_params()
    p = LlamaContextParams(
        Cuint(n_ctx), Cuint(n_batch), p.n_ubatch, p.n_seq_max, Cint(n_threads),
        Cint(n_threads), p.rope_scaling_type, p.pooling_type, p.attention_type,
        p.rope_freq_base, p.rope_freq_scale, p.yarn_ext_factor, p.yarn_attn_factor,
        p.yarn_beta_fast, p.yarn_beta_slow, p.yarn_orig_ctx, p.defrag_thold,
        p.cb_eval, p.cb_eval_ud, p.type_k, p.type_v, p.logits_all, p.embeddings,
        p.offload_kqv, flash_attn, p.no_perf, p.abort_callback, p.abort_callback_data)
    ctx = ccall((:llama_init_from_model, lib()), Ptr{Cvoid}, (Ptr{Cvoid}, LlamaContextParams), model, p)
    ctx == C_NULL && error("Failed to create context")
    return ctx
end

free_model(model::Ptr{Cvoid}) = ccall((:llama_model_free, lib()), Cvoid, (Ptr{Cvoid},), model)
free_context(ctx::Ptr{Cvoid}) = ccall((:llama_free, lib()), Cvoid, (Ptr{Cvoid},), ctx)

get_vocab(model::Ptr{Cvoid}) = ccall((:llama_model_get_vocab, lib()), Ptr{Cvoid}, (Ptr{Cvoid},), model)
n_vocab(vocab::Ptr{Cvoid}) = Int(ccall((:llama_vocab_n_tokens, lib()), Cint, (Ptr{Cvoid},), vocab))
model_size_bytes(model::Ptr{Cvoid}) = Int(ccall((:llama_model_size, lib()), UInt64, (Ptr{Cvoid},), model))

# ---------------------------------------------------------------------------
# Tokenization
# ---------------------------------------------------------------------------

function tokenize(vocab::Ptr{Cvoid}, text::AbstractString; add_special::Bool = true,
                  parse_special::Bool = true)
    cap = ncodeunits(text) + 16
    toks = Vector{LlamaToken}(undef, cap)
    n = ccall((:llama_tokenize, lib()), Cint,
              (Ptr{Cvoid}, Cstring, Cint, Ptr{LlamaToken}, Cint, Bool, Bool),
              vocab, text, ncodeunits(text), toks, cap, add_special, parse_special)
    n < 0 && error("tokenize: buffer too small (needed $(-n))")
    return toks[1:n]
end

is_eog(vocab::Ptr{Cvoid}, tok::LlamaToken) =
    ccall((:llama_vocab_is_eog, lib()), Bool, (Ptr{Cvoid}, LlamaToken), vocab, tok)

# ---------------------------------------------------------------------------
# Decode helpers
# ---------------------------------------------------------------------------

# batch containing a contiguous run of tokens for a single sequence, starting at
# position `pos0`, only the last token's logits requested if `logits_last`.
batch_get_one(tokens::Vector{LlamaToken}) =
    ccall((:llama_batch_get_one, lib()), LlamaBatch, (Ptr{LlamaToken}, Cint),
          tokens, Cint(length(tokens)))

function decode!(ctx::Ptr{Cvoid}, batch::LlamaBatch)
    rc = ccall((:llama_decode, lib()), Cint, (Ptr{Cvoid}, LlamaBatch), ctx, batch)
    rc != 0 && error("llama_decode failed: rc=$rc")
    return nothing
end

# logits for the i-th token of the last batch (-1 == last token)
function logits_ith(ctx::Ptr{Cvoid}, i::Integer, nvoc::Integer)
    p = ccall((:llama_get_logits_ith, lib()), Ptr{Cfloat}, (Ptr{Cvoid}, Cint), ctx, Cint(i))
    p == C_NULL && error("llama_get_logits_ith returned NULL")
    return unsafe_wrap(Array, p, nvoc)
end

argmax_token(logits::AbstractVector{<:Real}) = LlamaToken(argmax(logits) - 1)

# ---------------------------------------------------------------------------
# High-level: a controlled prefill + decode split
# ---------------------------------------------------------------------------

"""
    Session

Holds a loaded model + context and cached vocab size. Create once per
quantization level, reuse for warmup + measurement runs.
"""
mutable struct Session
    model :: Ptr{Cvoid}
    ctx   :: Ptr{Cvoid}
    vocab :: Ptr{Cvoid}
    nvoc  :: Int
end

function open_session(gguf_path::AbstractString; n_gpu_layers = 999, n_ctx = 4096,
                      flash_attn = true)
    backend_init()
    model = load_model(gguf_path; n_gpu_layers = n_gpu_layers)
    ctx   = new_context(model; n_ctx = n_ctx, flash_attn = flash_attn)
    vocab = get_vocab(model)
    return Session(model, ctx, vocab, n_vocab(vocab))
end

function close_session(s::Session)
    free_context(s.ctx)
    free_model(s.model)
    return nothing
end

# ---------------------------------------------------------------------------
# State reset  (⚠ API name varies across llama.cpp versions)
# ---------------------------------------------------------------------------
# Clearing the KV cache is what makes generation idempotent: without it, each
# decode run continues from the previous run's state and eventually overflows
# n_ctx. The clearing entry point has been renamed several times:
#   newest : llama_get_memory(ctx) + llama_memory_clear(mem, data)
#   older  : llama_kv_self_clear(ctx)
#   oldest : llama_kv_cache_clear(ctx)
# We resolve whichever the built library exports.
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

"""
    reset!(s)

Clear the context KV cache so the next `prefill!`/`decode_n!` starts from a
clean state. This is the key to idempotent, repeatable measurements.
"""
function reset!(s::Session)
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

"""
    prefill!(s, prompt) -> (last_token, n_prompt_tokens)

Run the prompt through the model in a single batch (the "prefill" / prompt
processing phase). Returns the greedily-selected first generated token and the
number of prompt tokens.

NOTE: this is a **stateful** primitive — it appends to the KV cache. Call
[`reset!`](@ref) first if you need a clean state. For measurement targets use
the idempotent [`generate!`](@ref) / [`prefill_only!`](@ref) instead.
"""
function prefill!(s::Session, prompt::AbstractString)
    toks = tokenize(s.vocab, prompt)
    decode!(s.ctx, batch_get_one(toks))
    next = argmax_token(logits_ith(s.ctx, -1, s.nvoc))
    return next, length(toks)
end

"""
    decode_n!(s, first_token, n) -> n_generated

Autoregressively generate up to `n` tokens starting from `first_token`
(greedy), stopping early on EOG.

NOTE: **stateful** — advances the KV cache. Not idempotent on its own; use it
via [`generate!`](@ref) for repeatable measurements.
"""
function decode_n!(s::Session, first_token::LlamaToken, n::Integer)
    tok = first_token
    generated = 0
    scratch = LlamaToken[0]
    for _ in 1:n
        is_eog(s.vocab, tok) && break
        generated += 1
        scratch[1] = tok
        decode!(s.ctx, batch_get_one(scratch))
        tok = argmax_token(logits_ith(s.ctx, -1, s.nvoc))
    end
    return generated
end

# ---------------------------------------------------------------------------
# Idempotent measurement targets
# ---------------------------------------------------------------------------
# These reset the KV cache at the start of every call, so they can be safely
# invoked many times (BenchmarkTools samples/evals) AND once more by the energy
# probe, each starting from an identical state. This is why the recipe needs no
# @perftest setup/teardown: idempotency is built into the target.
#
# IMPORTANT: the current PerfTest CUDA energy path measures the target ONCE,
# with no setup/teardown, and AFTER the timing loop. A `@perftest setup=...`
# would therefore NOT reset state for the energy measurement. Making the target
# self-resetting is the robust way to keep both the timing and energy runs
# consistent until the extension gains setup/teardown support around the probe.

"""
    generate!(s, prompt, n_gen) -> n_generated

Idempotent full request: clear KV cache, prefill `prompt`, then greedily decode
up to `n_gen` tokens. Safe to call repeatedly. This is the primary measured
target; whole-request energy divided by `n_generated` gives Joules per token.
"""
function generate!(s::Session, prompt::AbstractString, n_gen::Integer)
    reset!(s)
    first_tok, _ = prefill!(s, prompt)
    return decode_n!(s, first_tok, n_gen)
end

"""
    prefill_only!(s, prompt) -> n_prompt_tokens

Idempotent prefill: clear KV cache and process the prompt only. Measure this as
a second target to isolate prefill energy, so decode energy ≈ generate! energy −
prefill_only! energy.
"""
function prefill_only!(s::Session, prompt::AbstractString)
    reset!(s)
    _, n_prompt = prefill!(s, prompt)
    return n_prompt
end

end # module
