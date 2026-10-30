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
#  Perplexity (the quality axis) is obtained offline, "Level A" in README
#  "Quality axis": shelling out to the CUDA-built `llama-perplexity` tool
#  against a fixed corpus, once per quant. An earlier in-process ("Level B")
#  attempt teacher-forced the ~30-token PROMPT through LlamaFFI directly, but
#  that sample is far too small for a stable estimate — per-token noise from
#  quantization swamped the real, monotonic quality trend. llama-perplexity's
#  sliding-window evaluation over a real corpus (thousands of tokens) is what
#  gives a trustworthy number.
#
#  Run with:
#     using PerfTest
#     runperftests("llama_energy_test.jl")
#
#  Requirements (see README.md):
#    - A datacenter-class NVIDIA GPU (NVML energy_consumption supported).
#    - LLAMA_CPP_LIB pointing at a CUDA build of libllama (build_llama_cuda.sh).
#    - GGUF weights at several quant levels in $LLAMA_MODEL_DIR (get_models.sh).
#    - The `llama-perplexity` tool built alongside libllama, and a fixed text
#      corpus (see PPL_CORPUS below).
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
# e.g. "Qwen3.8-27B-UD-Q4_K_M.gguf"
const MODEL_BASE = get(ENV, "MODEL_BASE", "Qwen3.8-27B")

# Quantization levels to sweep, smallest -> largest. F16 is the quality
# baseline. Edit to match the GGUF files you actually downloaded/produced.
#
# Smallest-first (rather than the more natural "quality baseline first")
# is deliberate: at this model's size, the largest quants (f16/Q8_0/UD-Q6_K) may
# not fit in a single GPU's VRAM and can OOM. Running them last means the
# smaller, likely-to-fit quants are at least *computed* earlier in the same
# process before that happens. This is only a partial mitigation, though —
# see README "Caveats: OOM behavior" — since results are still saved once,
# after the whole sweep finishes, so a hard crash on a later quant still
# loses everything computed in that run, regardless of this ordering.
const QUANTS = ["UD-Q2_K_XL", "UD-Q3_K_XL", "UD-Q4_K_M", "UD-Q5_K_M", "UD-Q6_K", "Q8_0", "f16"]

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

# `llama-perplexity` is built alongside `libllama` by build_llama_cuda.sh
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
@testset "Llama.cpp energy efficiency vs quantization" begin
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
            # session below, so the two CUDA contexts (llama-perplexity's
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
        @auxiliary_metric name="Energy" units="W" begin
            :gpue
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
