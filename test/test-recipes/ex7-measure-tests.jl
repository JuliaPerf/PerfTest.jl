# Careful changing testset names (used for parsing)

using Test
using PerfTest

@perftest_config "
[regression]
enabled = false
"

@testset "Time Measurements" begin
    # Test that sleep duration is measured correctly
    sleep_duration = 0.1

    # Test multiple sleep calls with varying durations
    @testset "This should pass" begin

        @testset "Perfcompare" for duration in [0.1, 0.5]
            @auxiliary_metric name="Duration" units="" begin
                :median_time
            end
            @perfcompare duration * 0.9 < :median_time < duration * 1.1
            @perftest samples = 5 sleep(duration)
        end

        @testset "Effective mem throughput" begin
            space = 1_000_000_000
            time = 0.5

            @define_benchmark name = "dummy" units = "Byte/s" begin
                space / time
            end
            @define_eff_memory_throughput ratio = 0.97 custom_benchmark=dummy begin
                space / :median_time
            end
            @perftest samples = 5 sleep(time)
        end

        @testset "Custom metric" begin
            @define_metric name = "apples" units = "apples" begin
                5
            end

            @auxiliary_metric name = "pears" units = "pears" begin
                8
            end

            @perfcompare (:apples < :pears)
            @perftest sleep(0.1)
        end

        @testset "Roofline hardcoded" begin
            @roofline actual_flops=10 target_ratio=0.8 cpu_peak=120 membw_peak=100 begin
                4 / 4
            end
            @perftest sleep(0.1)
        end


        @testset "Roofline perfect" begin
            @on_perftest_exec begin
                global _flops = _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]/10
                global _opint = 10
            end

            @roofline actual_flops=_flops target_ratio=0.9 begin
                _opint
            end

            @perftest sleep(0.1)
        end
    end

    @testset "This should fail" begin

        @testset "Perfcompare" for duration in [0.1, 0.5]
            @perfcompare duration * 0.9 > :median_time
            @perfcompare duration * 1.1 < :median_time
            @perftest samples = 5 sleep(duration)
        end

        @testset "Effective mem throughput" begin
            space = 1_000_000_000
            time = 0.5

            @define_benchmark name = "dummy" units = "Byte/s" begin
                space / time * 2
            end
            @define_eff_memory_throughput ratio = 0.97 custom_benchmark=dummy begin
                space / :median_time
            end
            @perftest samples = 5 sleep(time)
        end

        @testset "Custom metric" begin
            @define_metric name = "apples" units = "apples" begin
                5
            end

            @auxiliary_metric name = "pears" units = "pears" begin
                8 
            end

            @perfcompare :apples > :pears
            @perftest sleep(0.1)
        end

        @testset "Roofline hardcoded" begin
            @roofline actual_flops=10 target_ratio=0.95 cpu_peak=120 membw_peak=100 begin
                6 / 4
            end
            @perftest sleep(0.1)
        end

        @testset "Roofline perfect" begin
            @on_perftest_exec begin
                global _flops = _PRFT_GLOBALS.builtins[:CPU_FLOPS_PEAK]/10/2
                global _opint = 10
            end

            @roofline actual_flops=_flops target_ratio=0.9 begin
                _opint
            end

            @perftest sleep(0.1)
        end
    end
end
