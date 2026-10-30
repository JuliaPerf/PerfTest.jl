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
    # Value type is loose (not a concrete SampledValue{Float64}) because whether a device's
    # entry is a SampledValue depends on nsamples >= MIN_VARIANCE_SAMPLES at measurement time.
    energy :: Vector{Any}
    power :: Vector{Any}
end

PerfTest.AMDGPUExtensionData(energy, power) = AMDGPUExtensionData(energy, power)

# ROCm SMI, opened when the extension is loaded, not when it is precompiled (which may happen on another machine)
const librocm_smi = Ref{Ptr{Cvoid}}(C_NULL)

# The function `name` of ROCm SMI
function rsmi(name::Symbol)
    librocm_smi[] == C_NULL && error("librocm_smi64 not found; AMDGPU energy/power measurements are not available.")
    return Libdl.dlsym(librocm_smi[], name)
end

# Throws if the ROCm SMI call `name` did not succeed, which returned `status` (RSMI_STATUS_SUCCESS is 0)
function checkRsmi(status::Integer, name::Symbol)
    status == 0 || error("ROCm SMI call $name failed with status $status.")
    return nothing
end

function __init__()
    # Searched in the system library paths, then in the ROCm installation
    lib = Libdl.find_library(["librocm_smi64"], [joinpath(get(ENV, "ROCM_PATH", "/opt/rocm"), "lib")])
    if lib == ""
        @warn "librocm_smi64 not found; AMDGPU energy/power measurements will error if used."
        return
    end
    handle = Libdl.dlopen(lib)
    status = ccall(Libdl.dlsym(handle, :rsmi_init), Cint, (UInt64,), 0)
    if status != 0
        @warn "ROCm SMI failed to initialize (status $status); AMDGPU energy/power measurements will error if used."
        return
    end
    librocm_smi[] = handle
    atexit(() -> ccall(rsmi(:rsmi_shut_down), Cint, ()))
end

amdgpu_devices = []

function PerfTest.amdgpu_devices()
    n = Ref{UInt32}(0)
    checkRsmi(ccall(rsmi(:rsmi_num_monitor_devices), Cint, (Ref{UInt32},), n), :rsmi_num_monitor_devices)
    # Device indices from 0, none when there are no devices
    return UInt32.(0:Int(n[])-1)
end

function PerfTest.read_joule(d::UInt32)
    energy = Ref{UInt64}(0)
    counter_resolution = Ref{Cfloat}(0)
    timestamp = Ref{UInt64}(0)
    checkRsmi(ccall(rsmi(:rsmi_dev_energy_count_get), Cint,
                    (UInt32, Ref{UInt64}, Ref{Cfloat}, Ref{UInt64}),
                    d, energy, counter_resolution, timestamp), :rsmi_dev_energy_count_get)
    energy[] * counter_resolution[] / 1e6 # microjoules -> joules
end

function PerfTest.gpuPowerMeasureAMD(e :: Expr, name)
    return quote
        begin
            devs = PerfTest.amdgpu_devices()
            nsamples = max(1, length(ts.benchmarks[$name]))
            # Compiles the reading of the counters before the samples, so it does not lengthen the window of the first one
            PerfTest.readEnergies(devs)
            energy_samples = Vector{Vector{Float64}}()
            power_samples = Vector{Vector{Float64}}()
            for _s in 1:nsamples
                AMDGPU.synchronize()
                pre = PerfTest.readEnergies(devs)
                _t0 = time_ns()
                # Execute
                $(e)
                AMDGPU.synchronize()
                _elapsed = (time_ns() - _t0) / 1e9
                post = PerfTest.readEnergies(devs)
                push!(energy_samples, post .- pre)
                # The average power of the execution, its energy over the time it took
                push!(power_samples, (post .- pre) ./ _elapsed)
            end
            energy = PerfTest.deviceMedians(energy_samples)
            power = PerfTest.deviceMedians(power_samples)
            @info energy, power
            energy, power
        end
    end
end

PerfTest.newSymbols(::Val{:amde})  = PerfTest.formulaGetAMDGPUEnergy
PerfTest.newSymbols(::Val{:amdp})  = PerfTest.formulaGetAMDGPUPower

PerfTest.formulaGetAMDGPUEnergy(properties) = deviceFormula(:energy, properties)
PerfTest.formulaGetAMDGPUPower(properties) = deviceFormula(:power, properties)

# The `field` (energy or power) of the AMDGPU data of a test result (its third extension), the sum over the devices, or
# the one of device N with the specifier devN (numbered from 0, as ROCm SMI does)
function deviceFormula(field::Symbol, properties)
    isempty(properties) && return :(sum(test_res.extensions[3].$field))
    length(properties) == 1 || throw(ArgumentError("Too many specifiers: $(join(properties, ".")), expected one devN."))
    s = String(properties[1])
    m = match(r"^dev([0-9]+)$", s)
    m === nothing && throw(ArgumentError("Unknown specifier: $s"))
    return :(test_res.extensions[3].$field[$(parse(Int, m.captures[1]) + 1)])
end

end # module
