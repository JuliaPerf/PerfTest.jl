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
# e.g. "Qwen3.8-27B-UD-Q4_K_M.gguf"
const MODEL_BASE = get(ENV, "MODEL_BASE", "Qwen3.8-27B")

# Quantization levels to sweep (highest fidelity first). F16 is the quality
# baseline. Edit to match the GGUF files you actually downloaded/produced.
const QUANTS = ["f16", "Q8_0", "UD-Q6_K", "UD-Q5_K_M", "UD-Q4_K_M", "UD-Q3_K_XL", "UD-Q2_K_XL"]

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
@testset "(AMD TEST)" begin

    # Average GPU power during decode.
    @auxiliary_metric name="Energy" units="W" begin
        :gpue
    end

    @auxiliary_metric name="Time" units="s" begin
        :median_time
    end

    @perftest samples=1 evals=1 seconds=120 sleep(5)
end
