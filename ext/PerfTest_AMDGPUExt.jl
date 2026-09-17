module PerfTest_AMDGPUExt

"""
PerfTest_AMDGPUExt

TODO WIP AMDGPU extension for marker-based energy and power sampling.

Usage (example):

Notes:
AMDGPU.jl does not itself wrap the ROCm SMI library (unlike CUDA.jl, which
bundles NVML bindings), so energy accounting here calls into librocm_smi64
directly via ccall.
"""

using PerfTest
using AMDGPU
using Libdl

function PerfTest.is_loaded(::Val{:AMDGPU}) return true end

struct AMDGPUExtensionData <: PerfTest.ExtensionData
    energy :: Vector{Float64}
    power :: Vector{Float64}
end

PerfTest.AMDGPUExtensionData(energy, power) = AMDGPUExtensionData(energy, power)

const librocm_smi = Libdl.find_library(["librocm_smi64"])

function __init__()
    if librocm_smi == ""
        @warn "librocm_smi64 not found; AMDGPU energy/power measurements will error if used."
        return
    end
    ccall((:rsmi_init, librocm_smi), Cint, (UInt64,), 0)
    atexit(() -> ccall((:rsmi_shut_down, librocm_smi), Cint, ()))
end

amdgpu_devices = []

PerfTest.amdgpu_devices() = begin
    n = Ref{UInt32}(0)
    ccall((:rsmi_num_monitor_devices, librocm_smi), Cint, (Ref{UInt32},), n)
    [i for i in UInt32(0):UInt32(n[] - 1)]
end

function PerfTest.read_joule(d::UInt32)
    energy = Ref{UInt64}(0)
    counter_resolution = Ref{Cfloat}(0)
    timestamp = Ref{UInt64}(0)
    ccall((:rsmi_dev_energy_count_get, librocm_smi), Cint,
          (UInt32, Ref{UInt64}, Ref{Cfloat}, Ref{UInt64}),
          d, energy, counter_resolution, timestamp)
    energy[] * counter_resolution[] / 1e6 # microjoules -> joules
end

function PerfTest.gpuPowerMeasureAMD(e :: Expr, name)
    return quote
        begin
            devs = PerfTest.amdgpu_devices()
            nsamples = max(1, length(ts.benchmarks[$name]))
            energy_samples = Vector{Vector{Float64}}()
            for _s in 1:nsamples
                AMDGPU.synchronize()
                pre = []
                for d in devs
                    push!(pre, PerfTest.read_joule(d))
                end
                # Execute
                $(e)
                AMDGPU.synchronize()
                post = []
                for d in devs
                    push!(post, PerfTest.read_joule(d))
                end
                push!(energy_samples, Float64.(post .- pre))
            end
            energy = [PerfTest._sample_median([energy_samples[s][d] for s in 1:nsamples]) for d in eachindex(devs)]
            power = energy
            @info energy, power
            energy, power
        end
    end
end

PerfTest.newSymbols(::Val{:amde})  = PerfTest.formulaGetAMDGPUEnergy
PerfTest.newSymbols(::Val{:amdp})  = PerfTest.formulaGetAMDGPUPower

function PerfTest.formulaGetAMDGPUEnergy(properties)
    if length(properties) == 0
        return quote sum(test_res.extensions[3].energy) end
    end
    s = String(properties[1])
    if match(r"^dev[0-9]+$", s) !== nothing
        return quote test_res.extensions[3].energy end
    else
        throw(ArgumentError("Unknown specifier: $s"))
    end
end

function PerfTest.formulaGetAMDGPUPower(properties)
    if length(properties) == 0
        return quote sum(test_res.extensions[3].power) end
    end
    s = String(properties[1])
    if match(r"^dev[0-9]+$", s) !== nothing
        return quote test_res.extensions[3].power end
    else
        throw(ArgumentError("Unknown specifier: $s"))
    end
end

end # module
