#!/usr/bin/env bash
#SBATCH --job-name=compilation     # Name of the job
#SBATCH --output=output_%j.log      # Standard output and error log
#SBATCH --error=error_%j.log        # Standard error log
#SBATCH --time=4:00:00              # Time limit hrs:min:sec
#SBATCH --nodes=1                   # Number of nodes
#SBATCH --ntasks=1                  # Total number of tasks
#SBATCH --nodelist=medusa               # Specify the node name
# =============================================================================
#  Build a CUDA-enabled llama.cpp so PerfTest.jl can measure GPU energy.
#
#  The registered llama_cpp_jll ships CPU-ONLY binaries (no libggml_cuda), so a
#  custom CUDA build is REQUIRED for this case study.
#
#  Usage:
#     ./build_llama_cuda.sh [SRC_DIR] [LLAMA_COMMIT]
#
#  On success prints the LLAMA_CPP_LIB path to export before running the study.
# =============================================================================
set -euo pipefail

export TMPDIR=$WORK/nvcctmp

# Pin a commit for reproducibility. Record whatever you actually build in the
# README results table. Override by passing an argument.
LLAMA_COMMIT="${2:-master}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$WORK/llama.cpp"
BUILD_DIR="${SRC_DIR}/build/${HOSTNAME}"

echo $BUILD_DIR

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
    -DCMAKE_CUDA_ARCHITECTURES="75;80;86;89;90"

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
