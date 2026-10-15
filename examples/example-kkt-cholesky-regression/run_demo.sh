#!/usr/bin/env bash
# Runs the 4-step regression demo end to end:
#   1) baseline   2) confirm stable   3) regress   4) recover
# Requires: Linux + LIKWID set up (see README.md).
# Usage: ./run_demo.sh [kkt_perftest.jl|clarabel_perftest.jl]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

RECIPE="${1:-kkt_perftest.jl}"
TOGGLE_LINE='const USE_FAST_FACTORIZATION = '
THREADS="${SLURM_CPUS_PER_TASK:-${SLURM_JOB_CPUS_PER_NODE:-$(nproc)}}"

case "$(uname -m)" in
    x86_64|amd64)
        JULIA="$JX86"
        ;;
    arm64|aarch64)
        JULIA="$JARM"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

set_toggle() {
    sed -i.bak "s/^${TOGGLE_LINE}.*/${TOGGLE_LINE}${1}/" "$RECIPE"
    rm -f "${RECIPE}.bak"
}

run() {
    echo "=== $1 (USE_FAST_FACTORIZATION=$(grep -o 'true\|false' <(grep "$TOGGLE_LINE" "$RECIPE"))) ==="
    $JULIA --project=. --threads="$THREADS" -e 'using LIKWID, PerfTest; runperftests("'"$RECIPE"'")'
}

set_toggle true
run "Step 1/4: establish baseline"
run "Step 2/4: confirm stable"

set_toggle false
run "Step 3/4: introduce regression"

set_toggle true
run "Step 4/4: recover"
