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
MODEL_BASE="${LLAMA_MODEL_BASE:-Qwen3.8-27B}"
# Repo derived from MODEL_BASE by default (bartowski's "<base>-GGUF" naming
# convention); override independently if the next model's repo doesn't follow
# that pattern, or belongs to a different quantizer, without editing this file.
MODEL_REPO="${LLAMA_MODEL_REPO:-unsloth/${MODEL_BASE}-GGUF}"
mkdir -p "${MODEL_DIR}"

# ---- Option A: download prebuilt quants (edit URLs to your model) -----------
# Example uses the bartowski GGUF repos. Uncomment the quants you want.
#
# Some quants of larger models (e.g. f16/Q8_0/Q6_K/Q5_K_M of a 70B model) are
# published as multiple split part files rather than one .gguf, since HF
# discourages single files much above ~50GB. fetch_quant tries the direct
# single-file download first, and falls back to discovering + downloading the
# split parts and merging them with llama-gguf-split.
GGUF_SPLIT_BIN="${GGUF_SPLIT_BIN:-${LLAMACPP_HOME}/bin/llama-gguf-split}"

fetch_quant() {
    local repo="$1" q="$2" out="$3"
    local base_url="https://huggingface.co/${repo}/resolve/main"
    echo "downloading ${q} : ${base_url}/${MODEL_BASE}-${q}.gguf ..."
    if curl -L --fail -o "${out}" "${base_url}/${MODEL_BASE}-${q}.gguf" 2>/dev/null; then
        return
    fi
    echo "  single-file download failed, checking for split parts ..."
    local listing rfilenames parts part local_parts=() local_name
    listing="$(curl -s "https://huggingface.co/api/models/${repo}")"
    # rfilename entries for split quants are nested under a quant-named
    # subdirectory (e.g. "Llama-3.3-70B-Instruct-Q8_0/Llama-3.3-70B-Instruct-
    # Q8_0-00001-of-00002.gguf"), so match the whole quoted path rather than
    # assuming the filename sits right after the opening quote.
    rfilenames="$(grep -o '"[^"]*\.gguf"' <<<"${listing}" | tr -d '"')"
    parts=($(grep -E "(^|/)${MODEL_BASE}-${q}-[0-9]{5}-of-[0-9]{5}\.gguf\$" <<<"${rfilenames}" | sort -u))
    if [[ ${#parts[@]} -eq 0 ]]; then
        echo "  no split parts found for ${q} either; giving up on this quant." >&2
        rm -f "${out}"
        return 1
    fi
    echo "  found ${#parts[@]} split part(s) for ${q}, downloading ..."
    for part in "${parts[@]}"; do
        # ${part} may include the subdirectory for the URL path, but is
        # stored flat locally (llama-gguf-split just needs the parts
        # together in one directory, named by their -NNNNN-of-NNNNN suffix).
        local_name="${MODEL_DIR}/$(basename "${part}")"
        curl -L --fail -o "${local_name}" "${base_url}/${part}"
        local_parts+=("${local_name}")
    done
    echo "  merging split parts -> ${out}"
    "${GGUF_SPLIT_BIN}" --merge "${local_parts[0]}" "${out}"
    rm -f "${local_parts[@]}"
}

download_prebuilt() {
    local repo="${MODEL_REPO}"
    for q in Q8_0 UD-Q6_K UD-Q5_K_M UD-Q4_K_M UD-Q3_K_XL UD-Q2_K_XL; do
        local out="${MODEL_DIR}/${MODEL_BASE}-${q}.gguf"
        [[ -f "${out}" ]] && { echo "have ${out}"; continue; }
        fetch_quant "${repo}" "${q}" "${out}"
    done
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
