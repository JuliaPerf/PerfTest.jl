#!/usr/bin/env bash
#SBATCH --job-name=compilation     # Name of the job
#SBATCH --output=output_%j.log      # Standard output and error log
#SBATCH --error=error_%j.log        # Standard error log
#SBATCH --time=4:00:00              # Time limit hrs:min:sec
#SBATCH --nodes=1                   # Number of nodes
#SBATCH --ntasks=1                  # Total number of tasks
#SBATCH --nodelist=amdnode1             # Specify the node name (edit to your ROCm/AMD GPU node)
# =============================================================================
#  Build a ROCm/HIP-enabled llama.cpp so PerfTest.jl can measure GPU energy.
#
#  The registered llama_cpp_jll ships CPU-ONLY binaries (no libggml_hip), so a
#  custom ROCm build is REQUIRED for this case study.
#
#  Usage:
#     ./build_llama_rocm.sh [SRC_DIR] [LLAMA_COMMIT]
#
#  On success prints the LLAMA_CPP_LIB path to export before running the study.
# =============================================================================
set -euo pipefail

export TMPDIR=$WORK/hipcctmp
mkdir -p "$TMPDIR"

# Pin a commit/tag for reproducibility. Record whatever you actually build in
# the README results table. Override by passing an argument.
#
# OUTDATED: Defaults to the b6652 release rather than `master`: at time of writing,
# master has a real compiler-codegen bug building ggml-cuda/mmf.cu for gfx1100
# (RDNA3) — clang fails to legalize a GCN/CDNA-only DPP wavefront-shift
# instruction ("Invalid dpp_ctrl value: wavefront shifts are not supported on
# GFX10+"), see https://github.com/ggml-org/llama.cpp/issues/18396. b6652 is
# the release AMD's own ROCm docs build llama.cpp against
# (https://rocm.docs.amd.com/projects/llama-cpp/en/docs-26.02/install/llama-cpp-install.html)
# and is known to build cleanly for this AMDGPU_TARGETS list.
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

# -DGGML_HIP=ON is the crucial flag. Adjust AMDGPU_TARGETS to your GPU(s):
# gfx906=MI50, gfx908=MI100, gfx90a=MI210/MI250(X), gfx942=MI300A/X,
# gfx1030=RDNA2 (6800/6900 series), gfx1100=RDNA3 (7900 series).
# HIPCXX/HIP_PATH come from the ROCm install via `hipconfig` (must be on PATH).
HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
    -DGGML_HIP=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=OFF \
    -DAMDGPU_TARGETS="gfx908;gfx90a;gfx942"

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
