# Tests of the CUDA extension (ext/PerfTest_CUDAExt.jl), see ../runtests.jl
# Needs a functional NVIDIA GPU whose energy counter NVML exposes (Volta or newer)

using CUDA
include("../gpu.jl")

const ext = Base.get_extension(PerfTest, :PerfTest_CUDAExt)

@testset "CUDA - extension loads" begin
    @test ext !== nothing
    @test PerfTest.is_loaded(:CUDA)
    @test CUDA.functional()
    devices = PerfTest.cuda_devices()
    @info "NVML devices: $devices"
    @test !isempty(devices)
    @test energyIncreases(devices, CuArray, CUDA.synchronize)
end

const BACKEND = (pkg = "CUDA", energy = :gpue, power = :gpup, slot = 2, data = "CUDAExtensionData")

gpuTransformTests(; BACKEND...)
gpuExecutionTests(; BACKEND..., array = "CuArray", devices = PerfTest.cuda_devices)
