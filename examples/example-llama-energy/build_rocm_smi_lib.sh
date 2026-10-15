#!/usr/bin/env bash
#SBATCH --job-name=rocm_smi_build   # Name of the job
#SBATCH --output=output_%j.log      # Standard output and error log
#SBATCH --error=error_%j.log        # Standard error log
#SBATCH --time=0:30:00              # Time limit hrs:min:sec
#SBATCH --nodes=1                   # Number of nodes
#SBATCH --ntasks=1                  # Total number of tasks
#SBATCH --nodelist=amdnode1         # Specify the node name (edit to the GPU node you want to build/test against)
# =============================================================================
#  Build librocm_smi64 from source into a user-writable prefix, so PerfTest.jl's
#  AMDGPU extension can pick up a rocm_smi_lib version that correctly parses
#  this node's gpu_metrics format, instead of whatever is on the
#  environment-module ROCm path today.
#
#  Why ROCm/amdsmi and not ROCm/rocm_smi_lib: on the MI200A node, gpu_metrics
#  reports format_revision=1, content_revision=9 (confirmed via
#  `od -An -tu1 -N4 /sys/class/drm/card*/device/gpu_metrics`). content_revision
#  9 is a self-describing attribute-table format (struct gpu_metrics_v1_9 in
#  the amdgpu kernel headers - attr_count + {attr_encoding, attr_value} pairs),
#  not another fixed-offset struct. The standalone ROCm/rocm_smi_lib repo has
#  NO code to walk that format at all (its content-revision dispatch in
#  rsmi_dev_gpu_metrics_info_get only ever defines VER_1/2/3, and there is no
#  rocm_smi_dyn_gpu_metrics.cc anywhere in that repo's history) - confirmed by
#  building its current master and getting RSMI_STATUS_INVALID_ARGS from both
#  Julia and the rocm-smi CLI (GetGPUMetricsFormat1's fallback path leaves its
#  buffer pointer null for any content_revision it doesn't recognize, so
#  GetDevBinaryBlob correctly rejects the null buffer with INVALID_ARGS).
#
#  ROCm/amdsmi (the amd-smi CLI's repo) vendors its OWN copy of the same
#  rocm_smi/ source tree, with rocm_smi_dyn_gpu_metrics.cc added to walk
#  content_revision >= 9 tables (see translate_header_to_flag_version's
#  kGpuMetricDynV19Plus branch). It builds that tree into a target literally
#  named `rocm_smi64` (rocm_smi/CMakeLists.txt), i.e. the exact same
#  librocm_smi64.so our extension already Libdl.find_library's - same
#  rsmi_dev_energy_count_get C symbol, same signature. amdsmi_get_energy_count
#  in libamd_smi.so is confirmed to be nothing but a thin wrapper around that
#  same call. So this fixes MI200A with NO changes needed to
#  PerfTest_AMDGPUExt.jl - only which librocm_smi64.so gets loaded.
#
#  NOTE this does NOT fix the separate MI100 magnitude issue (energy readings
#  ~400,000x too small): kEnergyCounterResolution = 15.3 (uJ/tick) is still
#  hard-coded unconditionally for all ASICs in this same tree
#  (rocm_smi/src/rocm_smi.cc), so a content_revision the library already
#  understood (MI100's is <= 3) sees no behavior change either way. That is a
#  separate, still-open problem.
#
#  Unlike the standalone rocm_smi_lib repo (zero external deps), this
#  monorepo's top-level CMakeLists REQUIRES libdrm + libdrm_amdgpu via
#  pkg-config (`pkg_check_modules(... REQUIRED ...)`), even though the
#  rocm_smi64 target itself doesn't need much from them. This is almost
#  certainly already present (any node running the amdgpu kernel driver needs
#  libdrm), but if configure fails looking for libdrm.pc/libdrm_amdgpu.pc, try
#  `module load` whatever provides it, or point PKG_CONFIG_PATH at it.
#
#  Usage:
#     ./build_rocm_smi_lib.sh [AMDSMI_REF]
#
#  AMDSMI_REF defaults to `amd-mainline` (this repo's default branch).
#
#  On success prints the LD_LIBRARY_PATH to export before running PerfTest.jl.
#  IMPORTANT: it must be prepended (not appended) so Libdl.find_library finds
#  this build before the environment-module ROCm's librocm_smi64.
# =============================================================================
set -euo pipefail

AMDSMI_REF="${1:-amd-mainline}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$WORK/amdsmi"
BUILD_DIR="${SRC_DIR}/build/${HOSTNAME}"
INSTALL_DIR="${SRC_DIR}/install/${HOSTNAME}"

if [[ ! -d "${SRC_DIR}" ]]; then
    git clone https://github.com/ROCm/amdsmi.git "${SRC_DIR}"
fi

git -C "${SRC_DIR}" fetch --all --tags
git -C "${SRC_DIR}" checkout "${AMDSMI_REF}"
echo "Building amdsmi @ $(git -C "${SRC_DIR}" rev-parse --short HEAD) (ref: ${AMDSMI_REF})"

cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release

# Only build the rocm_smi64 target (the piece PerfTest.jl actually loads) -
# skip libamd_smi, amdsmi_cli, py-interface, rust-interface and their extra
# build time/deps entirely.
cmake --build "${BUILD_DIR}" --target rocm_smi64 -j"$(nproc)"

LIB_BUILD_DIR="$(dirname "$(find "${BUILD_DIR}" -name 'librocm_smi64.so' | head -n1)")"
mkdir -p "${INSTALL_DIR}/lib"
cp -a "${LIB_BUILD_DIR}"/librocm_smi64.so* "${INSTALL_DIR}/lib/"

LIB="$(find "${INSTALL_DIR}" -name 'librocm_smi64.so*' | head -n1)"
echo ""
echo "=============================================================="
echo " Build complete: ${LIB}"
echo ""
echo " Export before running PerfTest.jl (prepend, don't append, so this"
echo " build is found before the module-loaded ROCm's librocm_smi64):"
echo ""
echo "   export LD_LIBRARY_PATH=${INSTALL_DIR}/lib:\$LD_LIBRARY_PATH"
echo ""
echo " Sanity-check independent of Julia - the system rocm-smi CLI also"
echo " dlopens librocm_smi64, so the same export should make it (dis)agree:"
echo ""
echo "   rocm-smi --showenergycounter"
echo "=============================================================="
