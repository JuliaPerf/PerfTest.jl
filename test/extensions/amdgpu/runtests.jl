# Tests of the AMDGPU extension (ext/PerfTest_AMDGPUExt.jl), see ../runtests.jl
# Needs a functional AMD GPU and ROCm SMI (librocm_smi64) when the extension is precompiled and executed

using AMDGPU
include("../gpu.jl")

const ext = Base.get_extension(PerfTest, :PerfTest_AMDGPUExt)

@testset "AMDGPU - extension loads" begin
    @test ext !== nothing
    @test PerfTest.is_loaded(:AMDGPU)
    @test AMDGPU.functional()
    # Looked up when the extension is precompiled, empty if ROCm SMI was not found then
    @test ext.librocm_smi != ""
    devices = PerfTest.amdgpu_devices()
    @info "ROCm SMI devices: $devices"
    @test !isempty(devices)
    # Without devices, an underflow of the count would list typemax(UInt32) of them
    @test length(devices) < 1024
    @test energyIncreases(devices, ROCArray, AMDGPU.synchronize)
end

const BACKEND = (pkg = "AMDGPU", energy = :amde, power = :amdp, slot = 3, data = "AMDGPUExtensionData")

gpuTransformTests(; BACKEND...)
gpuExecutionTests(; BACKEND..., array = "ROCArray", devices = PerfTest.amdgpu_devices)
