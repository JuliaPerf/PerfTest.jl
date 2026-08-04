#!/usr/bin/env bash
# =============================================================================
#  Fetch GGUF weights at several quantization levels for the energy study.
#
#  Two options:
#   (A) Download prebuilt GGUFs from Hugging Face (fast, less provenance).
#   (B) Produce all quants from a single F16 GGUF with llama-quantize so every
#       quant derives from an identical base (better provenance; recommended).
#
#  Set LLAMA_MODEL_DIR / LLAMA_MODEL_BASE to match llama_energy_test.jl.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${LLAMA_MODEL_DIR:-${HERE}/models}"
MODEL_BASE="${LLAMA_MODEL_BASE:-Qwen2.5-7B-Instruct}"
mkdir -p "${MODEL_DIR}"

# ---- Option A: download prebuilt quants (edit URLs to your model) -----------
# Example uses the bartowski GGUF repos. Uncomment the quants you want.
download_prebuilt() {
    local repo="bartowski/Qwen2.5-7B-Instruct-GGUF"
    local base_url="https://huggingface.co/${repo}/resolve/main"
    for q in Q8_0 Q6_K Q5_K_M Q4_K_M Q3_K_M Q2_K; do
        local out="${MODEL_DIR}/${MODEL_BASE}-${q}.gguf"
        [[ -f "${out}" ]] && { echo "have ${out}"; continue; }
        echo "downloading ${q} ..."
        curl -L --fail -o "${out}" "${base_url}/${MODEL_BASE}-${q}.gguf"
    done
    echo "NOTE: obtain the F16 baseline separately (often split or not published)."
}

# ---- Option B: quantize from a single F16 base (recommended) ----------------
# Requires the CUDA (or CPU) llama-quantize built by build_llama_cuda.sh.
quantize_from_f16() {
    local f16="${MODEL_DIR}/${MODEL_BASE}-f16.gguf"
    local quantize_bin="${QUANTIZE_BIN:-${HERE}/llama.cpp/build/bin/llama-quantize}"
    [[ -f "${f16}" ]] || { echo "Provide the F16 base at ${f16} first."; exit 1; }
    for q in Q8_0 Q6_K Q5_K_M Q4_K_M Q3_K_M Q2_K; do
        local out="${MODEL_DIR}/${MODEL_BASE}-${q}.gguf"
        [[ -f "${out}" ]] && { echo "have ${out}"; continue; }
        echo "quantizing -> ${q}"
        "${quantize_bin}" "${f16}" "${out}" "${q}"
    done
}

case "${1:-A}" in
    A) download_prebuilt ;;
    B) quantize_from_f16 ;;
    *) echo "usage: $0 [A|B]"; exit 1 ;;
esac

echo "Models in ${MODEL_DIR}:"
ls -lh "${MODEL_DIR}"
