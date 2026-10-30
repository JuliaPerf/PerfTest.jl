module PerfTest_CUDAExt

"""
PerfTest_CUDAExt

TODO WIP CUDA extension for marker-based energy and power sampling.

Usage (example):

Notes:
"""

using PerfTest
using CUDA

function PerfTest.is_loaded(::Val{:CUDA}) return true end

struct CUDAExtensionData <: PerfTest.ExtensionData
    # Value type is loose (not a concrete SampledValue{Float64}) because whether a device's
    # entry is a SampledValue depends on nsamples >= MIN_VARIANCE_SAMPLES at measurement time.
    energy :: Vector{Any}
    power :: Vector{Any}
end

PerfTest.CUDAExtensionData(energy, power) = CUDAExtensionData(energy, power)

cuda_devices = []

PerfTest.cuda_devices() = [i for i in CUDA.NVML.devices()]

PerfTest.read_joule(d::CUDA.NVML.Device) = CUDA.NVML.energy_consumption(d)

function PerfTest.gpuPowerMeasure(e :: Expr, name)
    return quote
        begin
            devs = PerfTest.cuda_devices()
            nsamples = max(1, length(ts.benchmarks[$name]))
            # Compiles the reading of the counters before the samples, so it does not lengthen the window of the first one
            PerfTest.readEnergies(devs)
            energy_samples = Vector{Vector{Float64}}()
            power_samples = Vector{Vector{Float64}}()
            for _s in 1:nsamples
                CUDA.synchronize()
                pre = PerfTest.readEnergies(devs)
                _t0 = time_ns()
                # Execute
                $(e)
                CUDA.synchronize()
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

PerfTest.newSymbols(::Val{:gpue})  = PerfTest.formulaGetGPUEnergy
PerfTest.newSymbols(::Val{:gpup})  = PerfTest.formulaGetGPUPower

PerfTest.formulaGetGPUEnergy(properties) = deviceFormula(:energy, properties)
PerfTest.formulaGetGPUPower(properties) = deviceFormula(:power, properties)

# The `field` (energy or power) of the CUDA data of a test result (its second extension), the sum over the devices, or
# the one of device N with the specifier devN (numbered from 0, as NVML does)
function deviceFormula(field::Symbol, properties)
    isempty(properties) && return :(sum(test_res.extensions[2].$field))
    length(properties) == 1 || throw(ArgumentError("Too many specifiers: $(join(properties, ".")), expected one devN."))
    s = String(properties[1])
    m = match(r"^dev([0-9]+)$", s)
    m === nothing && throw(ArgumentError("Unknown specifier: $s"))
    return :(test_res.extensions[2].$field[$(parse(Int, m.captures[1]) + 1)])
end

end # module
