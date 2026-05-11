using Test,PerfTest

@perftest_config "
[regression]
enabled = false
[general]
verbose = 0
"

@define_benchmark name = "dummy" units = "units" begin
    42
end

@testset "No perf tests" begin

    @regression low_is_bad=false

    @perfcompare :dummy > 40

    @roofline actual_flops=:autoflop target_ratio=0.1 begin
        :autoflop / 42
    end

    @perftest begin
        sleep(0.1)
    end

    @testset "This should pass" begin
        @test 1 + 1 == 2
    end
end