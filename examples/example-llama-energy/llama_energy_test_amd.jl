# =============================================================================
#  PerfTest.jl case study: energy efficiency of LLM inference vs. quantization
#  (AMD GPU / ROCm variant)
# =============================================================================
#
#  PRELIMINARY DRAFT.
#
#  Story: for a single model, sweep the GGUF quantization level and measure the
#  GPU *energy per generated token* using PerfTest.jl's AMDGPU/rocm_smi energy
#  feature, alongside a quality proxy (perplexity). The headline result is the
#  Pareto tradeoff: how much energy quantization saves vs. how much quality it
#  costs.
#
#  Identical recipe to llama_energy_test.jl, just on the AMD/ROCm backend:
#  inference is driven IN-PROCESS via direct `ccall`s into a HIP-enabled
#  libllama (see LlamaFFI.jl — the FFI itself is backend-agnostic; only the
#  libllama.so it's pointed at differs). PerfTest.jl's AMDGPU extension
#  (../../ext/PerfTest_AMDGPUExt.jl) reads rocm_smi's per-device energy counter
#  around each measured target, exposed to formulas as `:amde`/`:amdp` (the
#  `:gpue`/`:gpup` analogues from the CUDA extension).
#
#  Perplexity (the quality axis) is obtained offline, "Level A" in README
#  "Quality axis": shelling out to the ROCm-built `llama-perplexity` tool
#  against a fixed corpus, once per quant. See llama_energy_test.jl / README
#  for why in-process ("Level B") perplexity was dropped.
#
#  Run with:
#     using PerfTest
#     runperftests("llama_energy_test_amd.jl")
#
#  Requirements (see README.md):
#    - An AMD GPU with rocm_smi energy-counter support, and ROCm/librocm_smi64
#      installed (see ../../ext/PerfTest_AMDGPUExt.jl).
#    - LLAMA_LIB pointing at a ROCm/HIP build of libllama (build_llama_rocm.sh).
#    - GGUF weights at several quant levels in $MODEL_DIR (get_models.sh).
#    - The `llama-perplexity` tool built alongside libllama, and a fixed text
#      corpus (see PPL_CORPUS below).
# =============================================================================

using Test
using PerfTest
using AMDGPU

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
[amdgpu]
enabled = true
"

# Directory holding the GGUF files, one per quantization level.
const MODEL_DIR = get(ENV, "MODEL_DIR", joinpath(@__DIR__, "models"))

# Base model name; the quant tag is appended to form the filename.
# e.g. "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
const MODEL_BASE = get(ENV, "MODEL_BASE", "Qwen2.5-7B-Instruct")

# Quantization levels to sweep (highest fidelity first). F16 is the quality
# baseline. Edit to match the GGUF files you actually downloaded/produced.
const QUANTS = ["f16", "Q8_0", "Q6_K", "Q5_K_M", "Q4_K_M", "Q3_K_M", "Q2_K"]

# Fixed workload. Deterministic (greedy) decoding, fixed token budget so that
# "energy per token" is comparable across quants.
const PROMPT = "Explain, in a single detailed paragraph, why energy efficiency " *
               "is becoming the dominant cost metric for large language model " *
               "inference in production data centers."
const N_GEN = 256   # generated tokens (decode phase)

quant_path(q) = joinpath(MODEL_DIR, "$(MODEL_BASE)-$(q).gguf")

# -----------------------------------------------------------------------------
# Quality axis: offline perplexity (README "Quality axis", Level A)
# -----------------------------------------------------------------------------

# `llama-perplexity` is built alongside `libllama` by build_llama_rocm.sh
# (same build dir's bin/); override if it lives elsewhere.
const LLAMA_PERPLEXITY_BIN = get(ENV, "LLAMA_PERPLEXITY_BIN",
    joinpath(dirname(get(ENV, "LLAMA_LIB", "")), "llama-perplexity"))

# Fixed evaluation corpus (plain text, e.g. a WikiText-2 slice). The same
# corpus is used for every quant so the perplexity numbers are comparable.
const PPL_CORPUS = joinpath(get(ENV, "MODEL_DIR", @__DIR__), "wikitext-2-raw", "wiki.test.raw")

const PPL_CTX = 512   # llama-perplexity's context/chunk size (its -c flag)

"""
    run_llama_perplexity(model_path) -> Float64

Run `llama-perplexity` on `PPL_CORPUS` against the GGUF at `model_path` and
parse its "Final estimate: PPL = ..." line. Returns `NaN` (with a `@warn`) if
the binary or corpus is missing, so the sweep still runs without the quality
axis.
"""
function run_llama_perplexity(model_path::AbstractString)
    if !isfile(LLAMA_PERPLEXITY_BIN)
        @warn "llama-perplexity binary not found, skipping perplexity" bin=LLAMA_PERPLEXITY_BIN
        return NaN
    end
    if !isfile(PPL_CORPUS)
        @warn "Perplexity corpus not found, skipping perplexity" corpus=PPL_CORPUS
        return NaN
    end
    cmd = `$LLAMA_PERPLEXITY_BIN -m $model_path -f $PPL_CORPUS -c $PPL_CTX --n-gpu-layers 999`
    out = read(cmd, String)
    m = match(r"Final estimate: PPL = ([0-9.]+)", out)
    m === nothing && error("Could not parse PPL from llama-perplexity output:\n$out")
    return parse(Float64, m.captures[1])
end

# -----------------------------------------------------------------------------
# Sweep
# -----------------------------------------------------------------------------
@testset "Llama.cpp energy efficiency vs quantization (AMD)" begin
    @testset "quant = " for q in QUANTS

        # Skip quants whose GGUF is not present, so the suite still runs on a
        # partial model set.
        @on_perftest_ignore begin
            # (plain source run: nothing to do)
        end

        global s = nothing
        n_prompt = 0
        ppl = NaN
        # Heavy setup only happens in the generated perf suite.
        @on_perftest_exec begin
            path = quant_path(q)
            if !isfile(path)
                @warn "Missing GGUF, skipping" quant=q path=path
                continue
            end
            # Quality axis (Level A): run before opening the in-process FFI
            # session below, so the two GPU contexts (llama-perplexity's
            # subprocess and our own) never occupy the GPU at the same time.
            #ppl = run_llama_perplexity(path)

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
        # :amde.dev0 -> per-device GPU energy (Joules) measured around the target.
        # For a short prompt and N_GEN >> prompt this ≈ decode J/token; measure
        # prefill_only! separately to attribute the split exactly.
        @auxiliary_metric name="Energy/token" units="J/token" begin
            :amde / N_GEN
        end

        # Energy efficiency: generated tokens per Joule.
        @auxiliary_metric name="Efficiency" units="token/J" begin
            N_GEN / :amde
        end

        # Average GPU power during decode.
        @auxiliary_metric name="Energy" units="W" begin
            :amde
        end

	    @auxiliary_metric name="Time" units="s" begin :median_time  end

        # Decode throughput for context.
        @auxiliary_metric name="Throughput" units="token/s" begin
            N_GEN / :median_time
        end

        # Quality axis: offline llama-perplexity estimate for this quant on
        # PPL_CORPUS (run_llama_perplexity, computed once in setup above).
        @auxiliary_metric name="Perplexity" units="ppl" begin
            ppl
        end

        # ---- Pass/fail budget ----------------------------------------------
        # Demonstrates a testable energy target: fail if decode costs more than
        # the budget of Joules per generated token. Tune to your GPU/model.
        # low_is_bad=false => bigger is worse (energy).
        @define_test_metric name="Energy budget" units="J/token" reference=0.5 low_is_bad=false begin
            :amde / N_GEN
        end

        # ---- The measured target -------------------------------------------
        # Full request (prefill + decode), IDEMPOTENT: generate! clears the KV
        # cache and re-prefills on every call, so all BenchmarkTools samples and
        # the separate energy probe start from an identical state. No setup/
        # teardown is needed (and would not help the energy probe anyway — see
        # LlamaFFI.jl). Energy is auto-measured by the AMDGPU extension around
        # this call; :amde.dev0 / N_GEN is the headline Joules-per-token.
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
