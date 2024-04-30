
using BandwidthBenchmark
using Suppressor

include("../structs.jl")
include("../config.jl")
include("../perftest/structs.jl")
include("../perftest/data_handling.jl")
include("../metrics.jl")


# THIS FILE SAVES THE MAIN COMPONENTS OF THE EMPYRICAL EFFECTIVE MEM. THROUGHPUT
# METHODOLOGY BEHAVIOUR

function effMemThroughputPrefix(ctx::Context)::Expr
    return effective_memory_throughput.enabled ?
           quote
               using BandwidthBenchmark
               using Suppressor
    end : quote
        begin end
    end
end

function effMemThroughputSuffix(ctx::Context)::Expr
    return effective_memory_throughput.enabled ?
           quote
               # Begin probing the maximum memory throughput
               @suppress_out begin
                   global bench_data_frame = bwbench(; niter=3);
               end
               MT_reference = maximum(bench_data_frame[!, "Rate (MB/s)"])
    end : quote
        begin end
    end
end

function effMemThroughputEvaluation()::Expr
    return effective_memory_throughput.enabled ?
           quote
        # TODO
        for (flags, result) in local_customs
            if :mem_throughput in flags
                # Threshold
                min = 0.0
                max = 2.0
                # TODO
                # Ratio
                ratio = result.value / MT_reference
                # test
                _test = min < ratio < max


                constraint = PerfTests.Metric_Constraint(
                    reference=MT_reference,
                    threshold_min=min * MT_reference,
                    threshold_min_percent=min,
                    threshold_max=max * MT_reference,
                    threshold_max_percent=max,
                    low_is_bad=true
                )

                # Print result
                if _test
                    PerfTests.printMetric(result, constraint, length(depth), false, true, false)
                else
                    PerfTests.printMetric(result, constraint, length(depth), false, true, true)
                end
                # Register metric results TODO

                @test _test
            end
        end
    end : quote end
end
