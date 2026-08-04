# Case study — Energy efficiency of LLM inference vs. quantization

> **Status: preliminary draft.** This directory is a self-contained scaffold for a
> PerfTest.jl case study. The Julia recipe, the FFI binding, and the helper
> scripts are written to be runnable in shape, but the FFI struct layouts and the
> exact numbers must be validated on the target machine (see *Caveats*).

## The question

Almost every published `llama.cpp` benchmark reports **tokens per second**. For
production inference at scale, the metric that actually drives cost is
**energy per generated token (Joules/token)**. Quantization is the main lever for
reducing it — but it also degrades output quality.

This case study uses PerfTest.jl's new CUDA/NVML energy feature to answer:

> **How much energy does quantization save, and what does it cost in quality?**

The deliverable is a **Pareto plot**: energy-per-token (x) vs. quality loss vs.
the F16 baseline (y), one point per quantization level
(`F16 → Q8_0 → Q6_K → Q5_K_M → Q4_K_M → Q3_K_M → Q2_K`).

## Why this is a good demonstration of PerfTest.jl

- It measures a **real, non-Julia GPU workload** (llama.cpp's own CUDA context)
  entirely from a Julia test recipe. This works because NVML's
  `energy_consumption` is a **device-global** counter — PerfTest.jl (on CUDA.jl)
  reads it around each target, capturing whatever the GPU did, regardless of
  which CUDA context ran it.
- Inference is driven **in-process** via direct `ccall`s into `libllama`
  (`LlamaFFI.jl`), so prefill and decode can be bracketed **separately** and the
  energy attributed cleanly, without subprocess or model-load contamination.
- The measured targets are **idempotent by construction** (they reset the KV
  cache and re-prefill on every call), so repeated benchmark samples and the
  separate energy probe all start from an identical state — see *Idempotency*.
- It exercises PerfTest.jl idioms end-to-end: loop testsets, `@perftest`,
  `@export_vars`, custom/auxiliary metrics, a testable energy budget
  (`@define_test_metric`), and persisted results.

## Files

| File | Purpose |
|------|---------|
| `llama_energy_test.jl` | The PerfTest.jl recipe (quant sweep + energy metrics). |
| `LlamaFFI.jl`          | Minimal in-process `ccall` binding to a CUDA `libllama`. |
| `build_llama_cuda.sh`  | Build llama.cpp with `-DGGML_CUDA=ON`. |
| `get_models.sh`        | Download or quantize the GGUF weights. |
| `plot_results.jl`      | Produce the energy/quality Pareto figure. |
| `Project.toml`         | Deps (`PerfTest`, `CUDA`; optional plotting). |

## Requirements

- A **datacenter-class NVIDIA GPU** (V100 / A100 / H100 …). NVML
  `nvmlDeviceGetTotalEnergyConsumption` is supported on Volta+ datacenter cards;
  many consumer GeForce cards do **not** expose the cumulative energy counter.
- **A CUDA build of llama.cpp.** The registered `llama_cpp_jll` is **CPU-only**
  (no `libggml_cuda`), so it cannot be used here.
- A checkout of PerfTest.jl with the CUDA extension enabled.

## Reproduction

```bash
# 1. Build CUDA-enabled llama.cpp (set CUDA_ARCH: 70=V100, 80=A100, 90=H100)
CUDA_ARCH=80 ./build_llama_cuda.sh
export LLAMA_CPP_LIB=/abs/path/to/llama.cpp/build/bin/libllama.so

# 2. Get the weights (A = download prebuilt, B = quantize from an F16 base)
export LLAMA_MODEL_DIR=$PWD/models
export LLAMA_MODEL_BASE=Qwen2.5-7B-Instruct
./get_models.sh A

# 3. (Recommended) stabilise the GPU for repeatable energy numbers
sudo nvidia-smi -pm 1              # persistence mode
sudo nvidia-smi -lgc <min>,<max>  # lock graphics clocks

# 4. Run the study
julia --project=. -e 'using PerfTest; runperftests("llama_energy_test.jl")'
```

To generate the Pareto figure, populate `results.csv` (see `plot_results.jl`
header for the expected columns) and:

```bash
julia --project=. plot_results.jl
```

## Experimental design

| Aspect | Choice |
|--------|--------|
| Controlled | one model family, one GPU, full GPU offload, fixed prompt, fixed `N_GEN`, greedy (deterministic) decode, fixed flash-attention, locked clocks |
| Independent variable | GGUF quantization level (loop testset) |
| Primary metric | **Joules per generated token** (`decode_energy / N_GEN`) |
| Secondary | tokens/Joule, avg power (W), throughput (tok/s), VRAM |
| Quality axis | perplexity (or KL-divergence) vs the F16 baseline |

### Quality axis

Two ways to obtain perplexity (fill `PERPLEXITY` in the recipe):

- **Level A (simple):** run the CUDA-built `llama-perplexity` once per quant on a
  fixed corpus (e.g. a WikiText-2 slice) and paste the numbers in.
- **Level B (in-process):** compute perplexity through the same FFI by summing the
  log-probs of gold next-tokens. Cleaner, more work.

## How the recipe measures energy

The CUDA extension injects an NVML read before and after each `@perftest` target
(bracketed by a synchronize), storing the per-device delta. In the recipe:

- `@perftest ... LlamaFFI.generate!(s, PROMPT, N_GEN)` is the measured target
  (idempotent full request); its GPU energy is exposed to formulas as
  `:gpue.dev0` (Joules) and average power as `:gpup.dev0` (Watts).
- `@auxiliary_metric name="Energy/token" ... :gpue.dev0 / N_GEN` is the headline.
- `@define_test_metric name="Energy budget" reference=0.5 low_is_bad=false ...`
  demonstrates a **testable** energy target (fail the build if J/token exceeds
  the budget), which is the basis for energy-regression testing in CI.

## Idempotency (why the measured target self-resets)

LLM decoding is **stateful**: each `llama_decode` appends to the context KV
cache. A naive `decode_n!` target is therefore *not* idempotent — the 2nd
benchmark sample would continue from the 1st sample's state and eventually
overflow `n_ctx`.

You might reach for `@perftest setup=... teardown=...` to reset between runs.
That is **not sufficient** here, for two reasons specific to the current CUDA
energy extension:

1. The energy probe runs the target **once more, with no setup/teardown**
   (`hierarchy_transform.jl` injects `gpuPowerMeasure(expr)` directly), so a
   BenchmarkTools `setup` never runs for the energy measurement.
2. That energy run happens **after** the timing loop, so it would start from the
   most polluted state of all.

The robust fix used here is to make the measured targets **self-resetting**:
`generate!` and `prefill_only!` call `reset!` (clear the KV cache) at the start
of every invocation, so they are safe to call any number of times and always
start from an identical state — no `setup`/`teardown` required. If the extension
later gains setup/teardown support around the energy probe, the reset could move
there instead.

## Caveats (must-read for the draft)

1. **FFI struct layouts.** `LlamaModelParams` / `LlamaContextParams` in
   `LlamaFFI.jl` mirror the C structs so the `*_default_params()` calls work.
   These layouts change across llama.cpp commits — **verify them against the
   `llama.h` of the commit you build**, or regenerate the binding with
   `Clang.jl`. Pin and record the commit.
2. **Energy-feature prototype.** The PerfTest CUDA extension is still a prototype.
   Before trusting numbers, the known blockers should be fixed:
   unit conversion (NVML returns **millijoules**), real power (currently aliased
   to energy), honouring the `.devN` device specifier, gating the CUDA branch
   properly, and removing debug `@info` logs. See the project plan / issue
   tracker.
3. **Single-run energy.** Energy is measured on one execution of the target
   (separate from the timing samples). Use warmup + repetitions and report
   mean ± std for credibility.
4. **Whole-device counter.** NVML energy is device-global; run on an otherwise
   idle GPU, and consider subtracting an idle-power baseline.
5. **Determinism.** Greedy decoding is used so token counts and work are
   identical across repetitions; keep sampling out of the measured path.

## Open questions being finalised

- Model choice (Qwen2.5-7B, Apache-2.0 vs Llama-3.1-8B) and quant set.
- Quality metric: offline `llama-perplexity` (Level A) vs in-process (Level B).
- Whether to also demo **energy-regression testing** in CI.
