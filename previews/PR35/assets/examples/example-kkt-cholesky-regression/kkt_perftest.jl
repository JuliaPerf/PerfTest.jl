using Test, LIKWID, PerfTest
using LinearAlgebra

include("KktCholesky.jl")
using .KktCholesky

# Single, obviously-editable toggle simulating "a regression was introduced".
# Demo walkthrough (see README.md):
#   1. run with USE_FAST_FACTORIZATION = true  -> records the baseline
#   2. run again unchanged                     -> confirms stability
#   3. flip to false, run again                -> regression caught
#   4. flip back to true, run again            -> recovery (vs. baseline from step 1)
const USE_FAST_FACTORIZATION = true

@perftest_config "
[general]
verbose = 3
[regression]
enabled = true
dedicated_reference_file = 'kkt_reference.JLD2'
"

@testset "KKT Cholesky solve" begin
    # n×n dense SPD system, large enough that L (n²·8 bytes ≈ 2MB) clears
    # typical L2 caches, so the loop-order regression shows up clearly in
    # LIKWID's cache-miss and bandwidth counters. Tune against the target
    # machine's actual cache sizes if the effect isn't visible.
    n, m = 512, 256
    K, b = build_kkt_system(n, m; seed=1)

    # LIKWID-backed custom metrics (see ext/PerfTest_LIKWIDExt.jl for the
    # full alias table).
    @define_metric name="l3_miss_ratio" units="ratio" begin
        :miss.l3
    end
    @define_metric name="mem_bandwidth" units="MB/s" begin
        :bw.mem.read_write
    end
    @define_metric name="attained_gflops" units="GFLOP/s" begin
        :flop / 1e9 / :median_time
    end

    # Regression tracked across wall time AND two LIKWID hardware-counter
    # metrics, so a failure explains *why* it got slower, not just *that* it
    # did.
    #@regression metrics=Symbol[:median_time, :l3_miss_ratio, :attained_gflops] threshold=Float64[1.15, 1.20, 0.85] low_is_bad=Bool[false, false, true]
    @regression metrics=median_time threshold=1.15 low_is_bad=false
    @regression metrics=l3_miss_ratio threshold=1.2 low_is_bad=false
    @regression metrics=attained_gflops threshold=0.85 low_is_bad=true

    x = @perftest samples=15 solve_kkt(K, b, USE_FAST_FACTORIZATION)

    # Always passes: fast and regressed factorizations are bit-for-bit
    # identical (see KktCholesky.jl), so only performance ever regresses.
    @test relative_residual(K, b, x) < 1e-8
end
