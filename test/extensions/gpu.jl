# Tests shared by the GPU extensions (CUDA and AMDGPU), which measure the energy of every device around each target.
# Their arguments: `pkg` the package of the backend, `array` the name of its array type, `energy` and `power` the
# symbols of their formulas, `slot` the index of their data in the extensions of a test result, `data` the name of the
# type of that data and `devices` the function of the extension listing the devices it measures

using LinearAlgebra
include("common.jl")

# Multiplications of 4096x4096 Float32 matrices of the workload, about 14 TFLOP, so it lasts long enough for the energy
# counters to register it (from ~0.2 s on the fastest GPUs to a few seconds)
const WORK_ITERATIONS = 100

# Whether the energy counters of `devices` do not decrease across a workload on the default device, and one increases
function energyIncreases(devices, array, synchronize)
    A = array(rand(Float32, 4096, 4096))
    C = similar(A)
    mul!(C, A, A)
    synchronize()
    before = [PerfTest.read_joule(d) for d in devices]
    for _ in 1:WORK_ITERATIONS
        mul!(C, A, A)
    end
    synchronize()
    after = [PerfTest.read_joule(d) for d in devices]
    @info "Energy of each device across the workload [J]: $(after .- before)"
    return all(after .>= before) && any(after .> before)
end

# A recipe measuring the workload, with `lines` (e.g. metric definitions) inside its testset
gpuRecipe(pkg, array, lines...) = """
using Test, PerfTest, $pkg, LinearAlgebra

@perftest_config "
[regression]
enabled = false
"

const A = $array(rand(Float32, 4096, 4096))
const C = similar(A)

function work!(C, A)
    for _ in 1:$WORK_ITERATIONS
        mul!(C, A, A)
    end
    $pkg.synchronize()
    return C
end

@testset "T" begin
$(join(lines, "\n"))
    @perftest samples = 3 evals = 1 work!(C, A)
end
"""

function gpuTransformTests(; pkg, energy, power, slot, data)
    @testset "$pkg - the generated suite measures the energy" begin
        intempdir() do
            source = string(transformed())
            @test PerfTest.num_errors() == 0
            @test occursin("$pkg.synchronize()", source)
            @test occursin("PerfTest.$data(energy, power)", source)
        end
    end

    @testset "$pkg - formulas read the energy and power of the test result" begin
        intempdir() do
            for (formula, field) in [":$energy" => "energy", ":$power" => "power",
                                     ":$energy.dev0" => "energy", ":$power.dev1" => "power"]
                @testset "$formula" begin
                    source = string(transformed(metric("m", formula)))
                    @test PerfTest.num_errors() == 0
                    @test occursin("test_res.extensions[$slot].$field", source)
                end
            end
            for formula in [":$energy.bogus", ":$energy.dev", ":$power.device0"]
                @testset "$formula is rejected" begin
                    @test rejected(metric("m", formula))
                end
            end
        end
    end
end

function gpuExecutionTests(; pkg, array, energy, power, slot, data, devices)
    datatype = getfield(Base.get_extension(PerfTest, Symbol("PerfTest_$(pkg)Ext")), Symbol(data))

    # The test result saved by the last execution of `file`, after checking it holds the GPU data in its slot
    function gpuTest(file)
        test = only(savedTests(file))
        @test test.extensions[slot] isa datatype
        @test all(e -> e isa PerfTest.NoExtensionData, test.extensions[setdiff(1:3, slot)])
        return test
    end

    @testset "$pkg - the energy of every device is measured" begin
        intempdir() do
            write("measure.jl", gpuRecipe(pkg, array))
            ok, _ = runRecipe("measure.jl")
            @test ok
            if ok
                test = gpuTest("measure.jl")
                e = test.extensions[slot].energy
                @info "Energy of each device measured by the suite [J]: $e"
                @test length(e) == length(devices())
                @test all(>(0), e)
                # Plausible for a GPU (e.g. not mJ taken as J)
                @test 5 < maximum(e) / test.primitives[:median_time] < 1500
            end
        end
    end

    @testset "$pkg - formulas of one device" begin
        intempdir() do
            write("device.jl", gpuRecipe(pkg, array, metric("energy_dev0", ":$energy.dev0"),
                                                     metric("power_dev0", ":$power.dev0")))
            ok, _ = runRecipe("device.jl")
            @test ok
            if ok
                test = gpuTest("device.jl")
                e = test.extensions[slot].energy
                t = test.primitives[:median_time]
                @test metricValue(test, :energy_dev0) isa Real
                @test metricValue(test, :energy_dev0) ≈ e[1]
                # Average power during the execution, in W
                @test isapprox(metricValue(test, :power_dev0), e[1] / t; rtol=0.5)
            end
        end
    end

    @testset "$pkg - formulas of every device" begin
        intempdir() do
            write("total.jl", gpuRecipe(pkg, array, metric("energy_total", ":$energy"),
                                                    metric("power_total", ":$power")))
            ok, _ = runRecipe("total.jl")
            @test ok
            if ok
                test = gpuTest("total.jl")
                e = test.extensions[slot].energy
                t = test.primitives[:median_time]
                @test metricValue(test, :energy_total) ≈ sum(e)
                @test isapprox(metricValue(test, :power_total), sum(e) / t; rtol=0.5)
            end
        end
    end
end
