#!/usr/bin/env bash
# =============================================================================
#  Build a CUDA-enabled llama.cpp so PerfTest.jl can measure GPU energy.
#
#  The registered llama_cpp_jll ships CPU-ONLY binaries (no libggml_cuda), so a
#  custom CUDA build is REQUIRED for this case study.
#
#  Usage:
#     ./build_llama_cuda.sh [LLAMA_COMMIT]
#
#  On success prints the LLAMA_CPP_LIB path to export before running the study.
# =============================================================================
set -euo pipefail

# Pin a commit for reproducibility. Record whatever you actually build in the
# README results table. Override by passing an argument.
LLAMA_COMMIT="${1:-master}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${HERE}/llama.cpp"
BUILD_DIR="${SRC_DIR}/build"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone https://github.com/ggml-org/llama.cpp.git "${SRC_DIR}"
fi

git -C "${SRC_DIR}" fetch --all --tags
git -C "${SRC_DIR}" checkout "${LLAMA_COMMIT}"
echo "Building llama.cpp @ $(git -C "${SRC_DIR}" rev-parse --short HEAD)"

# -DGGML_CUDA=ON is the crucial flag. Adjust CMAKE_CUDA_ARCHITECTURES to your
# datacenter GPU (70=V100, 80=A100, 90=H100).
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=OFF \
    -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH:-80}"

cmake --build "${BUILD_DIR}" --config Release -j"$(nproc)"

LIB="$(find "${BUILD_DIR}" -name 'libllama.so' -o -name 'libllama.dylib' | head -n1)"
echo ""
echo "=============================================================="
echo " Build complete. Export before running the study:"
echo ""
echo "   export LLAMA_CPP_LIB=${LIB}"
echo ""
echo " (also ensure libggml*.so are alongside it; they are in ${BUILD_DIR}/bin)"
echo "=============================================================="
