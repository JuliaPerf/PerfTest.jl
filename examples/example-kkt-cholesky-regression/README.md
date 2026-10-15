# KKT Cholesky regression demo

This example shows PerfTest.jl's LIKWID-backed regression detection catching
a class of performance bug that no correctness test can ever see: a loop
reordered so it fights Julia's memory layout instead of working with it.

It comes in two parts, each demonstrating a different performance-bug class
that no correctness test can see:

- **Part 1** (`KktCholesky.jl` + `kkt_perftest.jl`): a small, self-contained,
  hand-rolled Cholesky kernel — no dependency beyond PerfTest/LIKWID. The
  regression is a transposed loop order (same algorithm, worse memory
  access pattern).
- **Part 2** (`clarabel_perftest.jl`): plugged directly into
  [Clarabel.jl](https://github.com/oxfordcontrol/Clarabel.jl) — a real
  interior-point QP/SOCP solver — by redefining one of its own internals at
  runtime. The regression is a disabled fill-reducing permutation (same
  Clarabel/QDLDL code end to end, worse elimination order).

## Background

Interior-point methods for convex optimization — Clarabel.jl, OSQP, ECOS,
and friends — spend nearly all of their time doing one thing over and over:
factorizing and solving a symmetric "KKT" (or condensed normal-equations)
linear system once per Newton iteration. Part 1 hand-rolls a kernel doing the
same kind of work — build a synthetic SPD system `K = AᵀA + σI`, factorize it
with Cholesky, solve by forward/back substitution — with no dependency on
any real solver, so we have full control over its implementation and can
inject a realistic regression into it. Part 2 takes that same idea — a
performance bug invisible to correctness tests — and drives it through
Clarabel.jl's actual factorization step instead of a synthetic stand-in,
via a different kind of bug: a disabled fill-reducing permutation, rather
than a transposed loop order.

## Part 1: the self-contained kernel

### The kernel, and the regression

Cholesky factorization has several textbook-equivalent loop orderings
(`kji`, `kij`, `jki`, ... — see Golub & Van Loan). They all do the exact same
arithmetic; they differ only in which array dimension the innermost loop
walks. Julia (like Fortran and MATLAB) stores matrices **column-major**, so
the innermost loop should walk down a column (stride 1) rather than across a
row (stride `n`).

`cholesky_factor_fast!` uses the `kji` order — column outer, row inner —
which is the right choice for Julia:

```julia
for j in (k+1):n
    ljk = L[j, k]
    @simd for i in j:n
        L[i, j] -= L[i, k] * ljk
    end
end
```

`cholesky_factor_regressed!` is the *same algorithm*, updating the exact
same set of matrix entries in the exact same order relative to the outer `k`
loop — just with the inner two loops transposed (`kij` order, row outer,
column inner):

```julia
for i in (k+1):n
    lik = L[i, k]
    @simd for j in (k+1):i
        L[i, j] -= lik * L[j, k]
    end
end
```

This is exactly the kind of one-line-diff bug that shows up when porting or
refactoring numerical code from a row-major reference implementation (C,
NumPy) without adjusting for Julia's layout. Because each matrix entry is
still updated by the same single subtraction in the same relative order,
**the two implementations produce bit-for-bit identical results** — every
`@test` you could write against the output will pass either way. Note also
that `@simd` is still sitting right there on the regressed loop: the
annotation alone doesn't fix a strided access pattern, which is exactly why
you need hardware counters, not source inspection, to catch this.

Measured locally (Apple M-series, n=512 dense system — absolute numbers will
differ on the real target machine, but the qualitative effect is a basic
cache/memory-hierarchy phenomenon that reproduces on any CPU):

| implementation | time (median of 5) |
|---|---|
| `cholesky_factor_fast!`      | ~6 ms   |
| `cholesky_factor_regressed!` | ~130 ms (≈20×) |

### The recipe (`kkt_perftest.jl`)

```julia
using Test, PerfTest, LIKWID
using LinearAlgebra

include("KktCholesky.jl")
using .KktCholesky

const USE_FAST_FACTORIZATION = true   # <- the toggle you flip to "introduce the regression"

@perftest_config "
[general]
verbose = 3
[regression]
enabled = true
dedicated_reference_file = 'kkt_reference.JLD2'
"

@testset "KKT Cholesky solve" begin
    n, m = 512, 256
    K, b = build_kkt_system(n, m; seed=1)

    @define_metric name="attained_gflops" units="GFLOP/s" begin
        :flops / 1e9
    end
    @define_metric name="l3_miss_ratio" units="ratio" begin
        :miss.l3
    end
    @define_metric name="mem_bandwidth" units="MB/s" begin
        :bw.mem.read_write
    end

    @regression metrics=[:median_time, :l3_miss_ratio, :attained_gflops] threshold=[1.15, 1.20, 0.85] low_is_bad=[false, false, true]

    x = @perftest samples=15 solve_kkt(K, b; fast=USE_FAST_FACTORIZATION)

    @test relative_residual(K, b, x) < 1e-8
end
```

`using LIKWID` activates PerfTest's `PerfTest_LIKWIDExt` extension. Any
`@perftest` target in a testset that references LIKWID-backed formula
symbols (`:flop`, `:flops`, `:bw`, `:miss`, `:energy`, `:power` — see
`ext/PerfTest_LIKWIDExt.jl` for the full alias table) is automatically
wrapped in `LIKWID.perfmon` with the right counter groups — there's no
manual group selection.

- `:flops` reads LIKWID's `FLOPS_DP` group's precomputed rate metric
  (reported internally in raw FLOP/s, hence `/ 1e9` for GFLOP/s).
- `:miss.l3` reads the `L3CACHE` group's "L3 miss ratio".
- `:bw.mem.read_write` reads the `MEM` group's "Memory bandwidth [MBytes/s]".

The `@regression` declaration tracks three metrics at once — wall time,
attained GFLOP/s, and L3 miss ratio — so a failing run doesn't just say "this
got slower", it tells you the mechanism: did the FLOP rate collapse, did the
cache miss ratio spike, or both?

### Running the Part 1 demo

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Then, from this directory:

1. With `USE_FAST_FACTORIZATION = true` (the shipped default), run:
   ```sh
   julia --project=. -e 'using PerfTest; runperftests("kkt_perftest.jl")'
   ```
   First run: no baseline exists yet, everything passes, the baseline is
   recorded to `kkt_reference.JLD2`.
2. Run the exact same command again — confirms stability (still compared
   against the run-1 baseline, still passes).
3. Edit `kkt_perftest.jl`, flip `USE_FAST_FACTORIZATION` to `false`, rerun.
   The `:median_time`, `l3_miss_ratio`, and `attained_gflops` regression
   checks fail; the correctness `@test` still passes. Because this run
   wasn't fully green, `kkt_reference.JLD2` is **not** updated — the
   original baseline persists.
4. Flip `USE_FAST_FACTORIZATION` back to `true` and rerun — recovers, passes
   again against the same original baseline from step 1.

Or run all four steps with `./run_demo.sh kkt_perftest.jl`.

*(TODO: paste real console output and measured metric values here after
running steps 1–4 on the target Linux/LIKWID machine.)*

Optionally, to see programmatically which metrics tripped a failing run
(mirrors `test/t5-regression.jl`'s style):

```julia
using PerfTest
PerfTest.retrievePerfTests("kkt_reference.JLD2"; get=:tests, where_pred=PerfTest.testFailed, pathonly=true)
```

## Part 2: plugging into Clarabel.jl directly

Part 1 proves the regression-detection idea works in isolation. Part 2
drives a *different* regression class through a real solver:
[Clarabel.jl](https://github.com/oxfordcontrol/Clarabel.jl), a pure-Julia
interior-point solver for QPs/SOCPs/SDPs, used here as a dependency rather
than reimplemented.

### The extension point, and the redefinition

Clarabel's default direct linear-solve backend, `QDLDLDirectLDLSolver`,
wraps [QDLDL.jl](https://github.com/osqp/QDLDL.jl), a sparse `K = L D Lᵀ`
factorization for symmetric quasi-definite matrices — the structural
property (positive-definite (1,1) block, negative-definite (2,2) block)
that Clarabel's KKT/Newton systems always have, which guarantees an `LDLᵀ`
factorization exists under *any* symmetric permutation, including the
identity, without pivoting.

QDLDL picks *which* permutation to use exactly once, at `Clarabel.Solver(...)`
construction time, via its own `qdldl(K; perm=..., ...)` constructor. The
default (`perm` left unspecified) computes a fill-reducing AMD ordering;
passing `perm=nothing` is QDLDL's own documented "factor without reordering"
mode — a first-class, publicly supported code path, not a hack. Every
`refactor!`/`solve!` call afterward — one pair per Newton iteration, plus
extra `solve!` calls for iterative refinement — is purely numeric and
reuses whatever permutation was chosen at construction; it never revisits
ordering.

This gives Part 2 a regression class that's arguably more representative
than a transposed loop order: **a disabled or broken fill-reducing
permutation**, a real, common sparse-solver performance bug. Crucially, it
can be injected without touching `refactor!`/`solve!` at all, and without
introducing any different algorithm — both `USE_FAST_FACTORIZATION = true`
and `false` run Clarabel's real, unmodified QDLDL numeric code end to end;
the only thing that differs is which permutation got baked in at
construction:

```julia
using QDLDL

function QDLDL._get_amd_ordering(A, amd_dense_scale)
    if USE_FAST_FACTORIZATION
        # Stock QDLDL behavior, verbatim.
        meta = QDLDL.AMD.Amd()
        meta.control[QDLDL.AMD.AMD_DENSE] *= Float64(amd_dense_scale)
        return QDLDL.AMD.amd(A, meta)
    else
        return nothing
    end
end
```

`_get_amd_ordering(A, amd_dense_scale)` is the private helper QDLDL uses to
compute `perm`'s default value. After `using QDLDL`, Julia lets this module
add or replace methods on any generic function for any type it doesn't
own — ordinary multiple dispatch, sometimes called "monkey-patching" (the
same mechanism Part 2 used to rely on for overriding `refactor!`/`solve!`
directly, before the regression moved to this construction-time hook). It's
private (underscore-prefixed), not public API — re-verify its name and
signature if the pinned QDLDL version (`Project.toml` pins `QDLDL = "0.4"`
alongside `Clarabel = "0.11"`) is ever bumped.

**Why `P` had to become genuinely sparse.** The naive version of this
regression — just flip AMD off on whatever QP happens to be at hand — turns
out to depend entirely on the problem: if the KKT matrix's dominant block is
already fully **dense**, no permutation can avoid roughly the same O(n³)
elimination cost either way, so disabling AMD barely registers. `build_qp`
therefore builds `P` as a genuinely sparse SPD matrix — a random sparse
graph (~6 edges/node) with diagonal dominance for guaranteed SPD-ness — and
then randomly shuffles its variable labeling. AMD's ordering is derived
purely from the sparsity graph, so it recovers a good elimination order
regardless of labeling; the *natural* (post-shuffle) order has no such
luck. That asymmetry — AMD is labeling-invariant, natural order isn't — is
exactly what makes "someone disabled AMD" a dramatic, realistic regression
on a sparse problem instead of a cosmetic one.

**Verified correctness**: both branches converge Clarabel to `SOLVED` on
the same QPs, to the same answer — they're the same algorithm and the same
code, just under two different permutations of the same quasi-definite
matrix, so (unlike Part 1's bit-for-bit identical loop-order variants) exact
floating-point agreement isn't guaranteed, but both should agree well
within Clarabel's own solver tolerance.

*(TODO: paste real fast-vs-regressed timing/GFLOP-s numbers here after
running on the target Linux/LIKWID machine.)*

### The recipe (`clarabel_perftest.jl`)

Same shape as Part 1 — inline `@perftest_config`, the same LIKWID-backed
metrics, the same multi-metric `@regression`, the same
`USE_FAST_FACTORIZATION` toggle — except the `@perftest` target constructs
and solves a real `Clarabel.Solver`, and it sweeps `n_vars` over
`[32, 64, 128, 256, 512, 1024, 2048]` instead of running a single fixed
size:

```julia
function solve_fresh_qp(P, q, A, b, cones, settings)
    solver = Clarabel.Solver(P, q, A, b, cones, settings)
    Clarabel.solve!(solver)
    return solver
end

solver = @perftest samples=5 evals=1 solve_fresh_qp(P, q, A, b, cones, settings)
@test solver.solution.status == Clarabel.SOLVED
```

Constructing a fresh solver inside the timed target (rather than via
`@perftest`'s `setup=`) keeps the target self-contained and measures "cost
of solving this QP", not just "cost of one factorization" — the regression
still shows up clearly since the bad permutation is paid for on every
Newton iteration inside the same call.

Note there's no intra-algorithm parallelism on either branch here — QDLDL
is single-threaded by design, regardless of AMD ordering. `@perftest_threads
:all` at the top of the file controls something different: how many Julia
threads the *perftest harness* itself may use across samples, not anything
inside Clarabel/QDLDL's own solve.

#### Why a ratio metric like `l3_miss_ratio` wouldn't be the right catch here either

`l3_miss_ratio` (`:miss.l3`) is a *rate* — L3 misses ÷ L3 references — not
a count. A disabled fill-reducing permutation genuinely increases both the
absolute amount of arithmetic (`:flop` — a worse elimination order creates
more fill-in in `L`, so QDLDL does more real work, not just the same work
laid out worse) and the memory traffic needed to do it, so a pure hit/miss
*ratio* can end up roughly flat even as both numerator and denominator grow
together — a ratio metric doesn't distinguish "twice the work, same
locality" from "the same work, half the locality."

`clarabel_perftest.jl` instead defines an operational-intensity metric that
normalizes L3 traffic by useful work directly:

```julia
@define_metric name="l3_operational_intensity" units="GFLOP/MB" begin
    (:flop / 1e9) / (:bw.l3.read_write * :median_time)
end
```

`:bw.l3.read_write` reads the `L3` group's "L3 bandwidth [MBytes/s]" — MB/s
of traffic at the L2/L3 boundary. Multiplying by `:median_time` turns that
rate into total MB moved for one call; dividing GFLOP of useful work
(`:flop / 1e9`) by that gives GFLOP done per MB of L3 traffic — the
roofline-style "operational intensity" (flop/byte, see
`example-paper-pardiso`), sourced from LIKWID counters instead of
solver-printed stats. `@regression` tracks it with `low_is_bad=false` (a
*decrease* is the failure signal): a disabled fill-reducing permutation
should make QDLDL do measurably more work per byte of L3 traffic it moves,
since the scattered fill-in it creates is exactly the kind of irregular,
low-reuse access pattern a good ordering exists to avoid.

### Running the Part 2 demo

Identical walkthrough to Part 1, just against the other recipe:

```sh
julia --project=. -e 'using PerfTest; runperftests("clarabel_perftest.jl")'
```

or `./run_demo.sh clarabel_perftest.jl` for all four steps at once.

*(TODO: paste real console output and measured metric values here after
running on the target Linux/LIKWID machine.)*

## Requirements

- **Linux only.** LIKWID reads hardware performance counters via the MSR
  interface or the `likwid-accessD` daemon; it does not run on macOS. Both
  kernels' correctness can be authored and sanity-checked anywhere Julia
  runs (see below), but run the actual `runperftests` demos on the target
  Linux machine.
- LIKWID needs counter access: either run as root, have the `msr` kernel
  module loaded with appropriate permissions, or have `likwid-accessD`
  installed and running. This is a LIKWID/OS-level concern — PerfTest.jl has
  no configuration for it.
- Part 1's `n = 512` dense system is sized to clear typical L2/L3 caches on
  the dev machine used above; if the regression doesn't show up clearly in
  `l3_miss_ratio`/`mem_bandwidth` on your target machine, scale up until the
  dense factor comfortably exceeds its L2/L3 size. Slowdown magnitude is
  also sensitive to whether the matrix dimension happens to alias badly
  against cache set size (e.g. powers of two are frequently pathological) —
  don't read too much into the exact multiplier, only into the fact that
  there reliably is one.
- Part 2's regression magnitude is driven by fill-in, not raw problem size:
  `build_qp`'s sparse, randomly-relabeled `P` (see above) needs the
  natural-order factorization to actually generate substantially more
  fill-in than AMD's — controlled by `avg_degree` (graph density) as much as
  by `n_vars`. If the regression doesn't show up clearly in
  `l3_operational_intensity`/`median_time` on your target machine, or if the
  natural-order branch blows up disproportionately at the largest `n_vars`
  in the sweep, tune `avg_degree` and/or trim the sweep rather than assuming
  the current values are universally correct — they haven't been tuned
  against a specific target machine yet.
- Part 2 pins `Clarabel = "0.11"` and `QDLDL = "0.4"` in `Project.toml`: it
  redefines QDLDL's private `_get_amd_ordering` helper, which is not public
  API and can change name or signature across QDLDL releases. If you bump
  either pin, re-verify the override still matches before trusting the
  patched results.

## Running these recipes via bare `include()`

Like `example-quickstart`'s `testfile.jl`, both recipes can also be run as
plain functional tests via `include("kkt_perftest.jl")` /
`include("clarabel_perftest.jl")`, bypassing `PerfTest.transform`/
`runperftests` entirely (all PerfTest macros are no-ops outside the
transform, so only the final `@test` actually runs, using whatever
`USE_FAST_FACTORIZATION` is currently set to). This requires `@perftest`'s
keyword arguments to always precede the target expression, which is the
last argument (`@perftest samples=15 solve_kkt(...)`, not
`@perftest solve_kkt(...) samples=15`) — this is also the order the real
transform pipeline expects. `KktCholesky.jl` has no such restriction either
way — it can be `include()`d and exercised directly for correctness checks
independent of PerfTest. (`KktLDLT.jl`, the hand-rolled dense `LDLᵀ` kernel
from an earlier version of Part 2's regression, is no longer used by
`clarabel_perftest.jl` — Part 2's regression now lives entirely inside
Clarabel/QDLDL's own code, see above — but the file is left in place
unreferenced rather than deleted.)
