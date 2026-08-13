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
    energy :: Vector{Float64}
    power :: Vector{Float64}
end

PerfTest.CUDAExtensionData(energy, power) = CUDAExtensionData(energy, power)

cuda_devices = []

PerfTest.cuda_devices() = [i for i in CUDA.NVML.devices()]

PerfTest.read_joule(d::CUDA.NVML.Device) = CUDA.NVML.energy_consumption(d)

function PerfTest.gpuPowerMeasure(e :: Expr)
    return quote
        begin
            CUDA.synchronize()
            pre = []
            post = []
            for d in PerfTest.cuda_devices()
                push!(pre, PerfTest.read_joule(d))
            end         
            # Execute
            $(e)
            CUDA.synchronize()
            for d in PerfTest.cuda_devices()
                push!(post, PerfTest.read_joule(d))
            end
            energy = post .- pre
            power = energy 
            @info energy, power
            energy, power
        end
    end
end

PerfTest.newSymbols(::Val{:gpue})  = PerfTest.formulaGetGPUEnergy
PerfTest.newSymbols(::Val{:gpup})  = PerfTest.formulaGetGPUPower

function PerfTest.formulaGetGPUEnergy(properties)
    if length(properties) == 0
        return quote sum(test_res.extensions[2].energy) end
    end
    s = String(properties[1])
    if match(r"^dev[0-9]+$", s) !== nothing
        return quote test_res.extensions[2].energy end
    else
        throw(ArgumentError("Unknown specifier: $s"))
    end
end

function PerfTest.formulaGetGPUPower(properties)
    if length(properties) == 0
        return quote sum(test_res.extensions[2].power) end
    end
    s = String(properties[1])
    if match(r"^dev[0-9]+$", s) !== nothing
        return quote test_res.extensions[2].power end
    else
        throw(ArgumentError("Unknown specifier: $s"))
    end
end

end # module
