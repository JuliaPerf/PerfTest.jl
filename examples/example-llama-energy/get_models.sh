#!/usr/bin/env bash
# =============================================================================
#  Fetch GGUF weights at several quantization levels for the energy study.
#
#  Two options:
#   (A) Download prebuilt GGUFs from Hugging Face (fast, less provenance).
#   (B) Produce all quants from a single F16 GGUF with llama-quantize so every
#       quant derives from an identical base (better provenance; recommended).
#
#  Also fetches the WikiText-2 corpus llama_energy_test.jl's quality axis
#  (Level A, run_llama_perplexity) evaluates against, at the same default
#  location it expects (PPL_CORPUS).
#
#  Set MODEL_DIR / LLAMA_MODEL_BASE to match llama_energy_test.jl.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_BASE="${LLAMA_MODEL_BASE:-Qwen2.5-7B-Instruct}"
mkdir -p "${MODEL_DIR}"

# ---- Option A: download prebuilt quants (edit URLs to your model) -----------
# Example uses the bartowski GGUF repos. Uncomment the quants you want.
download_prebuilt() {
    local repo="bartowski/Qwen2.5-7B-Instruct-GGUF"
    local base_url="https://huggingface.co/${repo}/resolve/main"
    for q in f16 Q8_0 Q6_K Q5_K_M Q4_K_M Q3_K_M Q2_K; do
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

# ---- Quality-axis corpus: WikiText-2 test split for llama-perplexity -------
# Same default location llama_energy_test.jl's PPL_CORPUS expects.
#
# The HF dataset repo dropped the old .raw/.zip files in favor of Parquet
# (https://huggingface.co/datasets/Salesforce/wikitext/tree/main/wikitext-2-raw-v1),
# so we download the test-split parquet and reassemble it into a plain-text
# file the same shape as the old wiki.test.raw (one physical line per row;
# blank rows are blank lines). Uses Julia (already a hard requirement for
# this whole example) with Parquet2.jl in a throwaway temp environment, so
# this doesn't touch Project.toml/Manifest.toml.
fetch_ppl_corpus() {
    if [[ -n "${PPL_CORPUS:-}" && -f "${PPL_CORPUS}" ]]; then
        echo "have ${PPL_CORPUS}"
        return
    fi
    local corpus_dir="${MODEL_DIR}/wikitext-2-raw"
    local corpus_file="${corpus_dir}/wiki.test.raw"
    [[ -f "${corpus_file}" ]] && { echo "have ${corpus_file}"; return; }
    echo "downloading wikitext-2-raw-v1 test split (parquet) ..."
    mkdir -p "${corpus_dir}"
    local parquet="${corpus_dir}/test-00000-of-00001.parquet"
    curl -L --fail -o "${parquet}" \
        "https://huggingface.co/datasets/Salesforce/wikitext/resolve/main/wikitext-2-raw-v1/test-00000-of-00001.parquet"
    echo "extracting text column -> ${corpus_file} ..."
    $JX86 --startup-file=no -e '
        import Pkg
        Pkg.activate(; temp=true)
        Pkg.add(["Parquet2", "Tables"])
        using Parquet2, Tables
        ds = Parquet2.Dataset(ARGS[1])
        open(ARGS[2], "w") do io
            for row in Tables.rows(ds)
                text = coalesce(row.text, "")
                print(io, text)
                endswith(text, "\n") || print(io, "\n")
            end
        end
    ' "${parquet}" "${corpus_file}"
    rm -f "${parquet}"
}

case "${1:-A}" in
    A) download_prebuilt ;;
    B) quantize_from_f16 ;;
    *) echo "usage: $0 [A|B]"; exit 1 ;;
esac

fetch_ppl_corpus

echo "Models in ${MODEL_DIR}:"
ls -lh "${MODEL_DIR}"
