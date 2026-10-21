# AGENT.md — PerfTest.jl developer guide

Orientation for AI agents doing package-wide work on **PerfTest.jl**, a Julia package
(`JuliaPerf/PerfTest.jl`, module `PerfTest`, currently v0.2.1) that compiles ordinary
`Test.jl`-style recipe scripts into performance-regression test suites. Originated as a
Master's thesis at USI, supervised with CSCS. Read this before touching `src/`.

## Mental model: two phases

1. **Transform (parse) time** — `PerfTest.transform` (alias of `treeRun`) reads a *recipe*
   script (plain Julia using `@testset`/`@test` plus PerfTest macros like `@perftest`,
   `@regression`, `@roofline`), walks its AST twice with `MacroTools.prewalk`, and emits a
   new Julia `Expr` for a self-contained test-suite module (`__PERFTEST__`). No benchmarking
   happens in this phase — it is pure macro expansion via a custom rule engine (PerfTest does
   **not** use real Julia macros for `@perftest` etc.; they are ordinary macrocalls matched
   and rewritten by pattern, then the not-yet-`@`-expanded generated code is written to disk).
2. **Execution (run) time** — the generated suite (saved as `<recipe>_perfsuite.jl`) is
   `include`d/launched as its own process. It runs real `BenchmarkTools.@benchmark`s, computes
   metrics/methodology results (`Test_Result`, `Methodology_Result`, ...), persists them via
   JLD2, and optionally uploads to bencher.dev.

`runperftests(file)` is the public one-call entry point: transform → save → execute.
`PerfTest.retrievePerfTests(datafile; ...)` is the public post-hoc query API over saved results.

## Directory map (`src/`)

```
src/PerfTest.jl            module root: exports, include order, rule-engine driver, treeRun/runperftests
src/extension_stubs.jl     forward-declares functions implemented in ext/*, is_loaded(), Mode types
src/logs.jl                Logger + per-channel log buffers, log folder save
src/printing.jl            colored console print helpers

src/transform/             ── PARSE TIME ──
  datastruct.jl              ASTRule, MacroParameter, Context/LocalContext/GlobalContext, generic combinators
  configuration.jl           `Configuration` submodule: CONFIG_SHAPE schema, load/save/merge TOML config
  prefix.jl / suffix.jl      boilerplate injected at top/bottom of the generated suite module
  auxiliar.jl                AST utility grab-bag (see below) — included LAST, used throughout
  dummy.jl                   trivial fixture recipe, used only by @compile_workload
  metrics/{primitives,custom}.jl        built-in metrics (median_time, autoflop, ...) + @define_metric machinery
  methodologies/{common,manual,regression,roofline,mem_bandwidth}.jl
                              one file per assertion "methodology" (@perfcompare/@regression/@roofline/@def_eff_mem)
  validation/{errors,formula,macro,export_vars}.jl
                              generic macro-arg validator, error collection, formula symbol table
  parsing/{rules,hierarchy_transform,target_transform,formula_transform}.jl
                              the actual ASTRule instances + testset/target/formula AST rewriters

src/execution/             ── RUN TIME ──
  structs.jl                 Metric_Result, Test_Result, Suite_Execution_Result, Perftest_Datafile_Root, ...
  testset.jl                 PerfTestSet <: AbstractTestSet — custom Test.jl testset that records results
  machine_topology.jl        `Topology` submodule: NUMA/thread pinning (hwloc/ThreadPinningCore)
  machine_benchmarking.jl    measures machine peak FLOPs / memory bandwidth (used by @roofline)
  retrieve.jl                public query API: retrievePerfTests, inTestSet, hasMetric, testPassed/testFailed
  data_handling.jl           JLD2 save/load of Perftest_Datafile_Root
  units.jl                   magnitudeAdjust — magnitude-prefix normalization for display
  printing.jl                runtime output (roofline UnicodePlots, hierarchical test-name printing)
  launch_suite.jl            `Launch` submodule: runs the generated `_perfsuite.jl` as a subprocess
  macros/                    one file per user-facing macro: perftest, perfcompare, roofline, regression,
                              exec_ignore (@on_perftest_exec/_ignore), customs (@define_metric &c.),
                              configuration (@perftest_config), topology (@perftest_threads, WIP)

src/bencher/                bencher.dev integration: REST client, JSON report export, submitReport

ext/                        package extensions (Julia weakdeps), loaded only when the dep is present:
  PerfTest_LIKWIDExt.jl       LIKWID hardware performance counters
  PerfTest_MPIExt.jl          MPI-aware multi-rank benchmarking
  PerfTest_CUDAExt.jl         CUDA GPU energy/power sampling (WIP)
  PerfTest_AMDGPUExt.jl       AMDGPU energy/power via ROCm SMI ccall (WIP)
```

## Core concepts

### The rule engine (`ASTRule`)
- `struct ASTRule` = `(match, validation, transformation)` functions (`src/transform/datastruct.jl`).
  Most are built via `ASTRule(match, macro_params::Dict{Symbol,MacroParameter}, transformation)`,
  which auto-wraps `validateMacro(macro_params)` as the validation step.
- `ruleSet(context, rules::Vector{ASTRule})` (`src/PerfTest.jl`) builds a closure applying rules
  to one AST node. **Only the first matching rule in the vector runs — order matters.**
- `first_pass_rules` (testset/perftest/regression/roofline/... macro rules) run first via
  `MacroTools.prewalk`, producing sentinel tokens `:__PERFTEST_FW__`/`:__PERFTEST_AFTER__`.
  `second_pass_rules` (`prefix_macro_rule`, `suffix_macro_rule`) replace those sentinels with
  real prefix/suffix boilerplate. This two-pass split is why prefix/suffix code can't simply be
  emitted in the first pass — it depends on info only fully known after the first pass completes.
- A separate mini rule-set, `perftest_expression_ruleset` (`transform/parsing/target_transform.jl`),
  is used only inside `parseTarget` to interpolate outer-scope variables into a `@perftest`
  target so `BenchmarkTools.@benchmark` (which runs in module/global scope) can see them.
- `_treeRun`/`treeRun` in `src/PerfTest.jl` drive the whole pipeline; `treeRun`'s final step is
  `rewrapDoBlockBodies(MacroTools.prettify(module_full))` — see "Known rough edges" for why the
  `rewrapDoBlockBodies` wrapper exists.

### Context objects (`src/transform/datastruct.jl`)
Parse-time state, not thread-safe by design (one `PerfTest.ctx` module-global per transform):
- `GlobalContext` — whole-file: original path, error collection, valid formula symbols, `in_recursion`.
- `LocalContext` — scope-local: `depth_record` (testset-nesting stack), `custom_metrics` and
  `enabled_methodologies` (one inner vector per nesting level — pushed/popped as testsets open/close).
- `Context` wraps both plus `test_tree_expr_builder` (unused leftover from a removed tree-builder
  implementation — see "Known rough edges").

### Generic macro-argument validation (`src/transform/validation/macro.jl`)
Nearly every DSL macro (`@regression`, `@define_metric`, `@roofline`, `@perftest_config`, ...) is
declared declaratively as a `Dict{Symbol,MacroParameter}` (built via `defineMacroParams`, e.g. in
`src/execution/macros/regression.jl`) and parsed by one of two shared functions:
- `validateMacro(params)` — for macros with a trailing positional block arg (e.g.
  `@define_metric name=... units=... begin ... end`).
- `validateBlocklessMacro(params)` — for all-keyword macros (e.g. `@regression metrics=... threshold=...`).

Both type-check each `a = b` argument against `MacroParameter.type`. If the raw AST node's own
type doesn't satisfy it directly, they fall back to `resolveLiteral(b)` (unwraps `QuoteNode`s and
`Expr(:vect, ...)` literals into real `Symbol`/`String`/`Vector` values) plus `typeMatches`, which
additionally accepts a real `Vector{ET}` against a declared `Vector{Union{...}}` parameter type —
working around Julia's invariant generic typing. **Validation runs against the resolved value**
when the fallback path is used, not the raw AST — keep this in mind when adding new parameter types.

### Formula mini-language (`src/transform/validation/formula.jl`, `parsing/formula_transform.jl`)
`@define_metric`/`@roofline`/etc. bodies accept quoted-symbol "formulas" (e.g. `:autoflop`,
`:median_time`, dotted chains like `:flop.double.vector_512` for LIKWID counters). `formula_symbols`
is the built-in whitelist; `transformFormula`/`SBMID` resolve a symbol at runtime by checking, in
order: `_PRFT_GLOBALS.custom_benchmarks` → builtins → `test_res.metrics` → `test_res.auxiliar` →
(if LIKWID loaded) hardware counters. Dotted chains are collapsed by `collectSymbolChain` before
substitution so genuine field access isn't misparsed as a metric reference.

### Methodologies and scope inheritance (`src/transform/methodologies/`)
Each methodology (regression/roofline/perfcompare/mem-bandwidth) stores a `MethodologyParameters`
(id, `override::Bool`, `params::Dict`) per open testset scope. `captureMethodologyInfo(id, ...)`
(`methodologies/common.jl`) walks the scope stack **innermost-first**, merging `params` keys
first-write-wins and stopping early at the first `override=true` entry — this implements "inner
scope inherits outer scope's methodology config unless it opts to fully override it." `@regression`
redeclared in the same scope extends the existing entry in place (rather than pushing a competing
second entry that would lose under first-key-wins merge) — see `onRegressionDefinition`.

### Package extensions
CUDA/AMDGPU/LIKWID/MPI support lives in `ext/*.jl` as Julia package extensions (weakdeps in
`Project.toml`), loaded only when the user's environment has the corresponding package. Code in
`src/` checks `is_loaded(:LIKWID)` etc. (`src/extension_stubs.jl`) before calling extension
functionality, and extension-provided functions are forward-declared as stubs there.

## Public API surface (exports from `src/PerfTest.jl`)

Macros: `@perftest`, `@perftest_config`, `@perftest_threads`, `@on_perftest_exec`,
`@on_perftest_ignore`, `@export_vars` (deprecated), `@define_benchmark`,
`@define_eff_memory_throughput`/`@def_eff_mem`, `@define_metric`, `@define_test_metric`,
`@auxiliary_metric`, `@roofline`, `@perfcompare`/`@perfcmp`, `@regression`.
Functions: `runperftests`, `PerfTest.transform` (= `treeRun`), `magnitudeAdjust`,
`PerfTest.retrievePerfTests` (+ predicates `inTestSet`/`hasMetric`/`testPassed`/`testFailed`).

## Configuration system

`Configuration` submodule (`src/transform/configuration.jl`) defines `CONFIG_SHAPE` (schema),
`DEFAULT`/`PRECOMPILATION_CONFIG` dicts, and TOML-backed `load_config`/`save_config`/`merge_configs`
(deep merge, override wins). Sections: `general`, `regression`, `roofline`, `memory_bandwidth`,
`perfcompare`, `machine_benchmarking`, `MPI`, `bencher`. Users override via a `perftest_config.toml`
file and/or an inline `@perftest_config "toml string"` in the recipe (merged at both parse time and
re-emitted into the generated suite so the same config applies at execution time). Full key
reference: `docs/src/configuration_params.MD`.

## Testing

- `test/runtests.jl` is a **custom subprocess runner**, not a plain `include`-everything script: it
  `walkdir`s `test/`, picks up every `t*.jl` file, and runs each as its own `julia -O3
  --startup-file=no <file>` subprocess (so each `tN-*.jl` is an independent process/testset, not
  aggregated into one `Test` tree). Cleans up `.perftest_logs`/`.perftests` afterward.
- Individual files can be run standalone for fast iteration: `julia --project test/t2-validation-macro.jl`.
- `test/t1`–`t6` cover: formula transformation, generic macro-arg validation, end-to-end AST
  transforms (asserted via `PerfTest.dumpLogsString()` log content), a full transform→execute→
  persist→query pass (`t4`), the regression methodology across repeated runs (`t5`, run 3× in a
  loop to exercise baseline-then-compare behavior), and the no-perftest-macros passthrough case (`t6`).
- `test/test-recipes/ex*.jl` are fixture recipe scripts (not tests themselves) fed through
  `PerfTest.transform` by `t3`–`t6`. When fixing a transform/validation bug, the pattern is:
  add a minimal fixture recipe here, then assert on it from `t3` (or add a new `tN` file).
- **CI does not run the test suite.** `.github/workflows/CI.yml`'s `test:` job is commented out;
  only the `docs:` job (Documenter build + doctest) runs on push/PR. Always run
  `julia --project test/runtests.jl` (or the specific `tN` file you touched) manually — don't
  assume a green PR check means tests passed. Per user preference, the user runs the Julia test
  suite / `Pkg.instantiate` themselves; AST-only `julia -e` checks are an acceptable substitute
  when you can't run the full suite.
- `examples/` (e.g. `example-kkt-cholesky-regression`, `example-quickstart`) double as real-world
  integration tests: at least two recent bugs (vector-literal macro args rejected by validation;
  `do`-block tuple bodies corrupted by `MacroTools.prettify`) were discovered via a real example
  recipe rather than the unit tests. When debugging a transform issue, check whether an example
  under `examples/` reproduces it before writing a synthetic fixture.

## Known rough edges (read before refactoring nearby code)

- `src/transform/auxiliar.jl`'s `genTestName!`/`testsetUpdate!` reference `state.depth` and
  `ASTWalkDepthRecord`, which do not exist under those names in current `datastruct.jl`
  (`LocalContext.depth_record::Vector{DepthEntry}` is the real field). These two functions appear
  to be orphaned from a prior refactor — the actual test-naming logic lives inline in
  `transformPerftest` (`parsing/hierarchy_transform.jl`). Verify call sites before relying on them.
- The older explicit-stack tree-builder (`hierarchy_transform_test_region.jl` /
  `hierarchy_transform_benchmark_region.jl`, plus `suffix.jl`'s `oldperftestsuffix`) that predated the
  "hierarchy fusion" refactor (`f935fc7`) has been removed — `transformTestset`/`transformPerftest`/
  `backTokenToContextUpdate!` in `hierarchy_transform.jl` are the live implementation.
  `Context.test_tree_expr_builder` (`datastruct.jl`) is dead state left over from that removal (no
  remaining writer populates it meaningfully) — a candidate for a future follow-up cleanup, not yet
  removed.
  `@export_vars` (`validation/export_vars.jl`) is marked `# DEPRECATED` at its rule-definition site.
- `treeRun`'s final line, `rewrapDoBlockBodies(MacroTools.prettify(module_full))`
  (`src/PerfTest.jl`): `MacroTools.prettify`'s `flatten` pass strips a `:block` wrapper around a
  single-statement body — including a `do`-block's lambda body. If that single statement is itself
  a non-`:block` form (e.g. a tuple literal), Julia's `Base.show` for `:do` (unlike `:for`/`:if`/
  `:let`) doesn't defensively re-wrap it, so it gets printed as several bare comma-free statements
  instead of one tuple once written to the generated suite file. `rewrapDoBlockBodies`
  (`src/transform/auxiliar.jl`) walks the post-`prettify` tree and restores the block. Any future
  change to how the generated suite is prettified/serialized must preserve this fix.
- `MacroParameter` (`datastruct.jl`) has a long stack of positional-argument constructors kept
  purely for backward compatibility with existing macro-parameter definitions under
  `src/execution/macros/` — prefer the keyword constructor for new code, don't remove the old ones
  without checking every macro definition file.

## Repo hygiene

- Numerous macOS AppleDouble `._*` files and `.DS_Store` are scattered through `src/`, `test/`,
  `ext/`, and the repo root as untracked junk from a filesystem copy — never commit these, and
  don't treat them as real source files if they show up in a directory listing.
- `examples/example-llama-energy/` currently contains a large amount of untracked working-directory
  cruft (logs, `.ipynb_checkpoints`, a `core` dump, build artifacts) — treat it as scratch, not a
  clean reference example. `examples/example-kkt-cholesky-regression/`, `example-quickstart/`,
  `example-paper-implicitglobalgrid/`, and `example-paper-pardiso/` are the cleaner reference examples.

## Common development tasks

- **Add a new macro parameter type / relax validation** → `src/transform/validation/macro.jl`
  (`validateMacro`/`validateBlocklessMacro`) and `src/transform/datastruct.jl`
  (`MacroParameter`, `resolveLiteral`, `typeMatches`). Add a fixture recipe in
  `test/test-recipes/` + assertions in `test/t2-validation-macro.jl` (unit) and
  `test/t3-transforms.jl` (end-to-end).
- **Add a new user-facing macro** → define its `MacroParameter` dict + validation in a new file
  under `src/execution/macros/`, add the corresponding `ASTRule` in
  `src/transform/parsing/rules.jl`, register it in `first_pass_rules` in `src/PerfTest.jl`
  (mind ordering — first match wins), and export it from `src/PerfTest.jl` if user-facing.
- **Add a new methodology** (like regression/roofline) → new file under
  `src/transform/methodologies/`, following the `onXDefinition`/`buildX` pattern, wired through
  `captureMethodologyInfo`.
- **Add a new built-in metric** → `src/transform/metrics/primitives.jl`
  (`buildPrimitiveMetrics!`) for always-computed metrics, or point users at
  `@define_metric`/`@auxiliary_metric` (`metrics/custom.jl`) for user-defined ones.
- **Docs**: `docs/src/*.MD` mirrors this file at a more user-facing level (macros.md,
  configuration_params.MD, internals.MD documents exact rule-priority ordering, limitations.md).
  Update the relevant `docs/src/` page alongside any public-API or config-schema change.
