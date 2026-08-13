# =============================================================================
#  PerfTest.jl case study: energy efficiency of LLM inference vs. quantization
# =============================================================================
#
#  PRELIMINARY DRAFT.
#
#  Story: for a single model, sweep the GGUF quantization level and measure the
#  GPU *energy per generated token* using PerfTest.jl's CUDA/NVML energy feature,
#  alongside a quality proxy (perplexity). The headline result is the Pareto
#  tradeoff: how much energy quantization saves vs. how much quality it costs.
#
#  Inference is driven IN-PROCESS via direct `ccall`s into a CUDA-enabled
#  libllama (see LlamaFFI.jl). Because NVML's energy counter is device-global,
#  PerfTest.jl (running on CUDA.jl) transparently captures the energy consumed by
#  llama.cpp's own CUDA context around each measured target.
#
#  Run with:
#     using PerfTest
#     runperftests("llama_energy_test.jl")
#
#  Requirements (see README.md):
#    - A datacenter-class NVIDIA GPU (NVML energy_consumption supported).
#    - LLAMA_CPP_LIB pointing at a CUDA build of libllama (build_llama_cuda.sh).
#    - GGUF weights at several quant levels in $LLAMA_MODEL_DIR (get_models.sh).
# =============================================================================

using Test
using PerfTest
using CUDA

include("LlamaFFI.jl")

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
@perftest_config "
[general]
verbose = 3
plotting = true
[regression]
enabled = false
[cuda]
enabled = true
"

# Directory holding the GGUF files, one per quantization level.
const MODEL_DIR = get(ENV, "MODEL_DIR", joinpath(@__DIR__, "models"))

# Base model name; the quant tag is appended to form the filename.
# e.g. "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
const MODEL_BASE = get(ENV, "MODEL_BASE", "Qwen2.5-7B-Instruct")

# Quantization levels to sweep (highest fidelity first). F16 is the quality
# baseline. Edit to match the GGUF files you actually downloaded/produced.
const QUANTS = ["Q8_K_M", "Q6_K", "Q5_K_M", "Q4_K_M", "Q3_K_M", "Q2_K"]

# Fixed workload. Deterministic (greedy) decoding, fixed token budget so that
# "energy per token" is comparable across quants.
const PROMPT = "Explain, in a single detailed paragraph, why energy efficiency " *
               "is becoming the dominant cost metric for large language model " *
               "inference in production data centers."
const N_GEN = 256   # generated tokens (decode phase)

quant_path(q) = joinpath(MODEL_DIR, "$(MODEL_BASE)-$(q).gguf")

# Offline perplexity per quant (quality axis). See README "Quality axis":
# populate this from `llama-perplexity` runs, or leave empty to skip the quality
# metric. Keyed by quant tag.
const PERPLEXITY = Dict{String,Float64}(
    # "f16"    => 0.0,
    # "Q4_K_M" => 0.0,
)

# -----------------------------------------------------------------------------
# Sweep
# -----------------------------------------------------------------------------
@testset "Llama.cpp energy efficiency vs quantization" begin
    @testset "quant = " for q in QUANTS

        # Skip quants whose GGUF is not present, so the suite still runs on a
        # partial model set.
        @on_perftest_ignore begin
            # (plain source run: nothing to do)
        end

        global s = nothing
        n_prompt = 0
        # Heavy setup only happens in the generated perf suite.
        @on_perftest_exec begin
            path = quant_path(q)
            if !isfile(path)
                @warn "Missing GGUF, skipping" quant=q path=path
                continue
            end
            s = LlamaFFI.open_session(path; n_gpu_layers = 999, n_ctx = 4096)
            # Warmup (compile kernels, populate caches) — excluded from the
            # measured targets below. generate! resets state each call, so this
            # leaves the session in a clean, reproducible state.
            LlamaFFI.generate!(s, PROMPT, 8)
            n_prompt = LlamaFFI.prefill_only!(s, PROMPT)
        end

        # Export locals so the metric formulas below can reference them.
        @info N_GEN,n_prompt,q

        # ---- Custom metrics -------------------------------------------------
        # Headline: Joules per generated token (whole-request energy / tokens).
        # :gpue.dev0 -> per-device GPU energy (Joules) measured around the target.
        # For a short prompt and N_GEN >> prompt this ≈ decode J/token; measure
        # prefill_only! separately to attribute the split exactly.
        @auxiliary_metric name="Energy/token" units="J/token" begin
            :gpue / N_GEN
        end

        # Energy efficiency: generated tokens per Joule.
        @auxiliary_metric name="Efficiency" units="token/J" begin
            N_GEN / :gpue
        end

        # Average GPU power during decode.
        @auxiliary_metric name="Avg power" units="W" begin
            :gpup
        end

        # Decode throughput for context.
        @auxiliary_metric name="Throughput" units="token/s" begin
            N_GEN / :median_time
        end

        # Optional quality axis: perplexity for this quant (if provided).
        @auxiliary_metric name="Perplexity" units="ppl" begin
            get(PERPLEXITY, q, NaN)
        end

        # ---- Pass/fail budget ----------------------------------------------
        # Demonstrates a testable energy target: fail if decode costs more than
        # the budget of Joules per generated token. Tune to your GPU/model.
        # low_is_bad=false => bigger is worse (energy).
        @define_test_metric name="Energy budget" units="J/token" reference=0.5 low_is_bad=false begin
            :gpue / N_GEN
        end

        # ---- The measured target -------------------------------------------
        # Full request (prefill + decode), IDEMPOTENT: generate! clears the KV
        # cache and re-prefills on every call, so all BenchmarkTools samples and
        # the separate energy probe start from an identical state. No setup/
        # teardown is needed (and would not help the energy probe anyway — see
        # LlamaFFI.jl). Energy is auto-measured by the CUDA extension around this
        # call; :gpue.dev0 / N_GEN is the headline Joules-per-token.
        @perftest samples=1 evals=1 seconds=120 LlamaFFI.generate!(s, PROMPT, N_GEN)

        # To isolate decode from prefill energy, also measure prefill_only! as a
        # second target and subtract; both are idempotent:
        #   @perftest samples=3 LlamaFFI.prefill_only!(s, PROMPT)

        # Teardown
        @on_perftest_exec begin
            s === nothing || LlamaFFI.destroy!(s)
        end
    end
end
