# Tests of the AMDGPU extension (ext/PerfTest_AMDGPUExt.jl), see ../runtests.jl
# Needs a functional AMD GPU and ROCm SMI (librocm_smi64)

using AMDGPU
include("../gpu.jl")

const ext = Base.get_extension(PerfTest, :PerfTest_AMDGPUExt)

@testset "AMDGPU - extension loads" begin
    @test ext !== nothing
    @test PerfTest.is_loaded(:AMDGPU)
    @test AMDGPU.functional()
    # Opened when the extension is loaded, in the system library paths or the ROCm installation (ROCM_PATH)
    @test ext.librocm_smi[] != C_NULL
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
