# Annex test suite of the package extensions, kept outside CI as each one needs hardware or libraries CI does not have
# (hardware performance counters for LIKWID, an NVIDIA GPU for CUDA, an AMD GPU and ROCm SMI for AMDGPU).
#
# Usage, from the root of the repository:
#     julia +1.12 test/extensions/runtests.jl [likwid] [cuda] [amdgpu]
# with no argument every extension is tested. Each extension has its own environment (test/extensions/<ext>), which
# is resolved and instantiated first, and its tests run in a fresh process so only that extension is loaded.
#
# Julia 1.11 or 1.12: the environments take PerfTest from this repository with [sources], which needs 1.11, and on
# Linux 1.13 cannot precompile ThreadPinning 0.7 (through BandwidthBenchmark).

const EXTENSIONS = ["likwid", "cuda", "amdgpu"]

selected = isempty(ARGS) ? EXTENSIONS : lowercase.(ARGS)
unknown = setdiff(selected, EXTENSIONS)
isempty(unknown) || error("Unknown extension(s) $(join(unknown, ", ")), the extensions are $(join(EXTENSIONS, ", ")).")

exename = joinpath(Sys.BINDIR, Base.julia_exename())
failed = String[]

for ext in selected
    dir = joinpath(@__DIR__, ext)
    printstyled("\nTesting extension $ext\n"; bold=true, color=:white)
    try
        # Resolved every time, so the environment follows the dependencies of PerfTest
        run(`$exename --startup-file=no --project=$dir -e "using Pkg; Pkg.resolve(); Pkg.instantiate()"`)
        run(Cmd(`$exename -O3 --startup-file=no --project=$dir runtests.jl`; dir=dir))
    catch
        push!(failed, ext)
    end
end

if !isempty(failed)
    printstyled("\nExtension test(s) failed: $(join(failed, ", "))\n"; bold=true, color=:red)
    error("$(length(failed)) extension test file(s) failed.")
end
