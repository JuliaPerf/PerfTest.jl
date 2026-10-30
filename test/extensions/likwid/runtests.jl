# Tests of the LIKWID extension (ext/PerfTest_LIKWIDExt.jl), see ../runtests.jl
# The unit and transform tests only need LIKWID.jl to load, the execution ones need access to the hardware performance
# counters (e.g. perf_event_paranoid <= 0, or the LIKWID access daemon)

using LIKWID
include("../common.jl")

const ext = Base.get_extension(PerfTest, :PerfTest_LIKWIDExt)

# The performance groups LIKWID supports on this CPU, nothing if they cannot be listed
const GROUPS = try
    Set{String}(keys(LIKWID.PerfMon.supported_groups()))
catch e
    @warn "Could not list the LIKWID groups of this CPU, every group is assumed to be supported" exception = e
    nothing
end
supported(group) = GROUPS === nothing || group in GROUPS

# The per-width FLOP events (FP_ARITH_INST_RETIRED_*) are Intel's
const INTEL = occursin("Intel", Sys.cpu_info()[1].model)

@testset "LIKWID - extension loads" begin
    @test ext !== nothing
    @test PerfTest.is_loaded(:LIKWID)
    GROUPS === nothing || @info "LIKWID groups of this CPU: $(join(sort(collect(GROUPS)), ", "))"
end

# ----------------------------------------------------------------------------------------------------------------------
# Unit, no performance counters needed
# ----------------------------------------------------------------------------------------------------------------------

@testset "LIKWID - specifier classification" begin
    flop_sets = (:type => ext.flop_submetrics_type, :vec => ext.flop_submetrics_vectorize)

    c = ext.classify([:single, :vector_256], flop_sets...)
    @test c[:type] == :single && c[:vec] == :vector_256
    # In any order
    c = ext.classify([:vector_256, :single], flop_sets...)
    @test c[:type] == :single && c[:vec] == :vector_256
    # Nothing given, nothing chosen (the formulas apply their defaults)
    c = ext.classify(Symbol[], flop_sets...)
    @test c[:type] === nothing && c[:vec] === nothing

    @test_throws ErrorException ext.classify([:double, :single], flop_sets...)
    @test_throws ErrorException ext.classify([:bogus], flop_sets...)
    @test_throws ErrorException ext.classify([:l3], flop_sets...)
end

@testset "LIKWID - merging samples" begin
    # The shape of LIKWID's results: group => one Dict per thread => metric or event name => value
    sample(v) = Dict("FLOPS_DP" => [Dict("DP [MFLOP/s]" => v), Dict("DP [MFLOP/s]" => 2v)])

    # Fewer samples than needed for a variance, the median
    merged = ext._merge_likwid_samples([sample(1.0), sample(3.0), sample(2.0)])
    @test merged["FLOPS_DP"][1]["DP [MFLOP/s]"] == 2.0
    @test merged["FLOPS_DP"][2]["DP [MFLOP/s]"] == 4.0

    # Enough samples, the median with its variance
    n = PerfTest.MIN_VARIANCE_SAMPLES
    merged = ext._merge_likwid_samples([sample(Float64(i)) for i in 1:n])
    leaf = merged["FLOPS_DP"][1]["DP [MFLOP/s]"]
    @test leaf isa PerfTest.SampledValue
    @test leaf.value == PerfTest._sample_median(Float64.(1:n))
    @test leaf.n == n
end

@testset "LIKWID - retrieval from a test result" begin
    metrics = Dict("FLOPS_DP" => [Dict("DP [MFLOP/s]" => 1.0), Dict("DP [MFLOP/s]" => 2.0)])
    events = Dict("FLOPS_DP" => [Dict("FP_ARITH_INST_RETIRED_SCALAR_DOUBLE" => 10.0), Dict{String,Float64}()])
    res = PerfTest.Test_Result("T", PerfTest.ExtensionData[PerfTest.LIKWIDExtensionData(metrics, events),
                                                           PerfTest.NoExtensionData(), PerfTest.NoExtensionData()])

    # One value per thread, group and name as String or Symbol
    @test PerfTest.likwidMetricsRetrieve(res, :FLOPS_DP, "DP [MFLOP/s]") == [1.0, 2.0]
    @test PerfTest.likwidMetricsRetrieve(res, "FLOPS_DP", Symbol("DP [MFLOP/s]")) == [1.0, 2.0]
    # An event missing on a thread is 0 when not required
    @test PerfTest.likwidEventsRetrieve(res, :FLOPS_DP, :FP_ARITH_INST_RETIRED_SCALAR_DOUBLE; required=false) == [10.0, 0]
    @test_throws ArgumentError PerfTest.likwidEventsRetrieve(res, :FLOPS_DP, :FP_ARITH_INST_RETIRED_SCALAR_DOUBLE)
    # A group that was not measured
    @test_throws ArgumentError PerfTest.likwidMetricsRetrieve(res, :MEM, "Memory bandwidth [MBytes/s]")
    # A test result without LIKWID data
    nolikwid = PerfTest.Test_Result("T", PerfTest.ExtensionData[PerfTest.NoExtensionData()])
    @test_throws ArgumentError PerfTest.likwidMetricsRetrieve(nolikwid, :FLOPS_DP, "DP [MFLOP/s]")
    @test_throws ArgumentError PerfTest.likwidEventsRetrieve(nolikwid, :FLOPS_DP, :FP_ARITH_INST_RETIRED_SCALAR_DOUBLE)
end

# ----------------------------------------------------------------------------------------------------------------------
# Transform, no performance counters needed
# ----------------------------------------------------------------------------------------------------------------------

# Formula => the LIKWID group and metric it reads
const METRICS = [
    ":flop.double"              => ("FLOPS_DP", "DP [MFLOP/s]"),
    ":flop.single"              => ("FLOPS_SP", "SP [MFLOP/s]"),
    ":flops.double"             => ("FLOPS_DP", "DP [MFLOP/s]"),
    ":flop_s.single"            => ("FLOPS_SP", "SP [MFLOP/s]"),
    ":bw.mem"                   => ("MEM", "Memory bandwidth [MBytes/s]"),
    ":bw.l3.read"               => ("L3", "L3 load bandwidth [MBytes/s]"),
    ":bw.read.l3"               => ("L3", "L3 load bandwidth [MBytes/s]"),
    ":bw.l2.write"              => ("L2", "L2D evict bandwidth [MBytes/s]"),
    ":bw.mem.read_write_volume" => ("MEM", "Memory data volume [GBytes]"),
    ":energy.package"           => ("ENERGY", "Energy [J]"),
    ":energy.dram"              => ("ENERGY", "Energy DRAM [J]"),
    ":energy.all"               => ("ENERGY", "Energy [J]"),
    ":power.package"            => ("ENERGY", "Power [W]"),
    ":power.all"                => ("ENERGY", "Power [W]"),
    ":miss.l2"                  => ("L2CACHE", "L2 miss ratio"),
    ":miss.l3"                  => ("L3CACHE", "L3 miss ratio"),
    # Without specifiers, their defaults
    ":flop"                     => ("FLOPS_DP", "DP [MFLOP/s]"),
    ":flops"                    => ("FLOPS_DP", "DP [MFLOP/s]"),
    ":bw"                       => ("MEM", "Memory bandwidth [MBytes/s]"),
    ":miss"                     => ("L2CACHE", "L2 miss ratio"),
    ":energy"                   => ("ENERGY", "Energy [J]"),
    ":power"                    => ("ENERGY", "Power [W]"),
]

@testset "LIKWID - formulas read their metric and enable its group" begin
    intempdir() do
        for (formula, (group, name)) in METRICS
            @testset "$formula" begin
                ex = transformed(metric("m", formula))
                @test PerfTest.num_errors() == 0
                @test occursin("likwidMetricsRetrieve(test_res, :$group, \"$name\")", string(ex))
                groups = perfmonGroups(ex)
                @test length(groups) == 1 && group in groups[1]
            end
        end
    end
end

# Formula => the LIKWID group, the events it sums and the events it must not
const EVENTS = [
    ":flop.double.scalar"     => ("FLOPS_DP", ["SCALAR_DOUBLE"], ["PACKED_DOUBLE"]),
    ":flop.vector_256"        => ("FLOPS_DP", ["256B_PACKED_DOUBLE"], ["SCALAR_DOUBLE", "128B_PACKED_DOUBLE", "512B_PACKED_DOUBLE"]),
    ":flop.single.vector_512" => ("FLOPS_SP", ["512B_PACKED_SINGLE"], ["SCALAR_SINGLE", "128B_PACKED_SINGLE", "256B_PACKED_SINGLE"]),
    # Every vector width, no scalar
    ":flop.vector"            => ("FLOPS_DP", ["128B_PACKED_DOUBLE", "256B_PACKED_DOUBLE", "512B_PACKED_DOUBLE"], ["SCALAR_DOUBLE"]),
]

@testset "LIKWID - per-width FLOP formulas sum their events" begin
    intempdir() do
        for (formula, (group, present, absent)) in EVENTS
            @testset "$formula" begin
                ex = transformed(metric("m", formula))
                @test PerfTest.num_errors() == 0
                source = string(ex)
                for event in present
                    @test occursin("likwidEventsRetrieve(test_res, :$group, :FP_ARITH_INST_RETIRED_$event", source)
                end
                for event in absent
                    @test !occursin("FP_ARITH_INST_RETIRED_$event", source)
                end
                groups = perfmonGroups(ex)
                @test length(groups) == 1 && group in groups[1]
            end
        end
    end
end

@testset "LIKWID - invalid specifiers are rejected" begin
    intempdir() do
        # Conflicting, unknown, a rate per width, no L1 metric, two levels, a level for energy, a kind for misses
        for formula in [":flop.double.single", ":flop.bogus", ":flops.vector_256", ":bw.l1", ":bw.mem.l3",
                        ":energy.l2", ":miss.read"]
            @testset "$formula" begin
                @test rejected(metric("m", formula))
            end
        end
    end
end

@testset "LIKWID - generated suite" begin
    intempdir() do
        # A test without LIKWID metrics measures no group
        ex = transformed()
        @test PerfTest.num_errors() == 0
        @test perfmonGroups(ex) == [String[]]
        # The suite imports LIKWID itself, it calls the extension when it executes
        @test occursin("using LIKWID", string(ex))
    end
end

# ----------------------------------------------------------------------------------------------------------------------
# Execution, needs access to the performance counters
# ----------------------------------------------------------------------------------------------------------------------

# Elements of the daxpy measured by the execution tests, its vectors (256 MiB each) are much bigger than the caches
const N = 2^25

# A recipe measuring the daxpy, with `lines` (e.g. metric definitions) inside its testset. `header` imports the packages
kernelRecipe(lines...; samples = 5, header = "using Test, PerfTest, LIKWID") = """
$header
using ThreadPinningCore
# PerfTest calls LIKWID with autopin = false, which measures the CPUs the threads are on, so they must stay there
ThreadPinningCore.pinthread(ThreadPinningCore.getcpuid())

@perftest_config "
[regression]
enabled = false
"

function daxpy!(y, a, x)
    @inbounds @simd for i in eachindex(x, y)
        y[i] = muladd(a, x[i], y[i])
    end
    return y
end

@testset "T" begin
    x = rand($N)
    y = rand($N)
$(join(lines, "\n"))
    @perftest samples = $samples evals = 1 daxpy!(y, 2.0, x)
end
"""

# The test result saved by the last execution of `file`, after checking it holds the LIKWID data in its slot
function likwidTest(file)
    test = only(savedTests(file))
    @test test.extensions[1] isa ext.LIKWIDExtensionData
    @test all(e -> e isa PerfTest.NoExtensionData, test.extensions[2:end])
    return test
end

@testset "LIKWID - a recipe without LIKWID metrics executes" begin
    intempdir() do
        write("plain.jl", kernelRecipe())
        ok, _ = runRecipe("plain.jl")
        @test ok
        ok && likwidTest("plain.jl")
    end
end

@testset "LIKWID - a recipe that does not import LIKWID executes" begin
    intempdir() do
        write("nousing.jl", kernelRecipe(; header = "using Test, PerfTest"))
        ok, _ = runRecipe("nousing.jl")
        @test ok
        ok && likwidTest("nousing.jl")
    end
end

@testset "LIKWID - FLOPS_DP" begin
    if !supported("FLOPS_DP")
        skipped("the CPU has no FLOPS_DP group")
    else
        intempdir() do
            write("flops.jl", kernelRecipe(metric("flop_count", ":flop.double"),
                                           metric("flop_rate", ":flops.double"),
                                           metric("flop_events", ":flop.double.scalar + :flop.double.vector")))
            ok, _ = runRecipe("flops.jl")
            @test ok
            if ok
                test = likwidTest("flops.jl")
                # A multiplication and an addition per element. The count comes from LIKWID's rate times the median
                # time measured by BenchmarkTools, so only roughly
                @test 0.5 * 2N <= metricValue(test, :flop_count) <= 2 * 2N
                @test metricValue(test, :flop_rate) > 0
                if INTEL
                    # Counted exactly by the events
                    @test isapprox(metricValue(test, :flop_events), 2N; rtol=0.05)
                else
                    skipped("the per-width FLOP events are Intel's")
                end
            end
        end
    end
end

@testset "LIKWID - bare aliases take their defaults" begin
    if !supported("FLOPS_DP")
        skipped("the CPU has no FLOPS_DP group")
    else
        intempdir() do
            write("bare.jl", kernelRecipe(metric("flop_bare", ":flop"), metric("flop_count", ":flop.double")))
            ok, _ = runRecipe("bare.jl")
            @test ok
            if ok
                test = likwidTest("bare.jl")
                @test isapprox(metricValue(test, :flop_bare), metricValue(test, :flop_count); rtol=1e-6)
            end
        end
    end
end

@testset "LIKWID - MEM" begin
    if !supported("MEM")
        skipped("the CPU has no MEM group")
    else
        intempdir() do
            write("mem.jl", kernelRecipe(metric("mem_volume", ":bw.mem.read_write_volume"), metric("mem_bw", ":bw.mem")))
            ok, _ = runRecipe("mem.jl")
            @test ok
            if ok
                test = likwidTest("mem.jl")
                # Reads x and y and writes y, 8 bytes each per element, in GBytes
                @test 0.5 * 24N / 1e9 <= metricValue(test, :mem_volume) <= 2 * 24N / 1e9
                @test metricValue(test, :mem_bw) > 0
            end
        end
    end
end

@testset "LIKWID - cache misses" begin
    lines = String[]
    supported("L2CACHE") && push!(lines, metric("l2_miss_ratio", ":miss.l2"))
    supported("L3CACHE") && push!(lines, metric("l3_miss_ratio", ":miss.l3"))
    if isempty(lines)
        skipped("the CPU has no L2CACHE or L3CACHE group")
    else
        intempdir() do
            write("miss.jl", kernelRecipe(lines...))
            ok, _ = runRecipe("miss.jl")
            @test ok
            if ok
                test = likwidTest("miss.jl")
                for sym in (:l2_miss_ratio, :l3_miss_ratio)
                    haskey(test.metrics, sym) && @test 0 <= metricValue(test, sym) <= 1
                end
            end
        end
    end
end

@testset "LIKWID - ENERGY" begin
    if !supported("ENERGY")
        skipped("the CPU has no ENERGY group")
    else
        intempdir() do
            write("energy.jl", kernelRecipe(metric("energy_pkg", ":energy.package"), metric("power_pkg", ":power.package")))
            ok, _ = runRecipe("energy.jl")
            @test ok
            if ok
                test = likwidTest("energy.jl")
                @test metricValue(test, :energy_pkg) > 0
                @test 0 < metricValue(test, :power_pkg) < 1000
            end
        end
    end
end

@testset "LIKWID - samples enough for a variance" begin
    if !supported("FLOPS_DP")
        skipped("the CPU has no FLOPS_DP group")
    else
        intempdir() do
            n = PerfTest.MIN_VARIANCE_SAMPLES
            write("variance.jl", kernelRecipe(metric("flop_count", ":flop.double"); samples = n))
            ok, _ = runRecipe("variance.jl")
            @test ok
            if ok
                test = likwidTest("variance.jl")
                leaf = test.extensions[1].metrics["FLOPS_DP"][1]["DP [MFLOP/s]"]
                @test leaf isa PerfTest.SampledValue
                @test leaf.n == n
                # The variance propagates through the formula
                v = metricValue(test, :flop_count)
                @test isfinite(v) && v > 0
            end
        end
    end
end
