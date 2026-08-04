# =============================================================================
#  Post-process the persisted PerfTest results into the headline Pareto plot:
#  energy-per-token (x) vs. quality loss (y), one point per quantization level.
#
#  PRELIMINARY DRAFT — assumes results were persisted to the JLD2 datafile that
#  PerfTest.jl writes under ./.perftests/. Adjust the extraction to match the
#  Suite_Execution_Result schema of your PerfTest version, or (simpler) have the
#  recipe append rows to a CSV and load that here.
#
#  Uncomment the deps in Project.toml before running:
#     using DataFrames, CSV, CairoMakie, JLD2
# =============================================================================

# This is intentionally a skeleton: the exact JLD2 layout is internal to
# PerfTest (see src/execution/structs.jl :: Suite_Execution_Result / Test_Result).
# The most robust approach for a draft is to emit a CSV from the analysis and
# plot that. Below is the CSV-based path.

using CSV, DataFrames, CairoMakie

const RESULTS_CSV = get(ENV, "LLAMA_RESULTS_CSV", joinpath(@__DIR__, "results.csv"))

# Expected columns: quant, energy_per_token, tokens_per_joule, avg_power,
#                   throughput, perplexity, vram_gb
df = CSV.read(RESULTS_CSV, DataFrame)

# Quality loss vs the F16 baseline (perplexity increase, %).
base_ppl = df[df.quant .== "f16", :perplexity]
if !isempty(base_ppl) && !isnan(first(base_ppl))
    df.quality_loss_pct = 100 .* (df.perplexity .- first(base_ppl)) ./ first(base_ppl)
else
    df.quality_loss_pct .= NaN
end

fig = Figure(size = (720, 520))
ax = Axis(fig[1, 1];
    xlabel = "Energy per generated token  [J/token]",
    ylabel = "Quality loss vs F16  [% perplexity increase]",
    title  = "LLM inference: energy/quality Pareto (PerfTest.jl)")

scatter!(ax, df.energy_per_token, df.quality_loss_pct; markersize = 14)
for r in eachrow(df)
    text!(ax, r.energy_per_token, r.quality_loss_pct; text = r.quant,
          align = (:left, :bottom), offset = (6, 6))
end

out = joinpath(@__DIR__, "pareto_energy_quality.png")
save(out, fig)
@info "wrote $out"
