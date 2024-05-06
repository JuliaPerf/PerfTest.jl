
using Suppressor
using STREAMBenchmark

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
               using Suppressor
               using STREAMBenchmark
    end : quote
        begin end
    end
end

function effMemThroughputSuffix(ctx::Context)::Expr
    return effective_memory_throughput.enabled ?
           quote
               # Begin probing the maximum memory throughput
               $(if verbose
                     quote
                         @suppress_out begin
                        global bench_data = STREAMBenchmark.benchmark()
                    end
                end
            else
                quote
                    println("="^26 * "Maximum memory throughput calculation" * "="^26)
                    global bench_data = STREAMBenchmark.benchmark()

                    println("="^26 * "=====================================" * "="^26)
                 end
                 end)
               MT_reference = bench_data.multi.maximum
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
                min = $(effective_memory_throughput.tolerance.min_percentage)
                max = $(effective_memory_throughput.tolerance.max_percentage)
                
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
                    low_is_bad=true,
                    succeeded=_test,

                    custom_plotting=Symbol[],
                    full_print = $(verbose ? :(true) : :(!_test))
                )

                # Print result
                if _test
                    PerfTests.printMetric(result, constraint, length(depth))
                else
                    PerfTests.printMetric(result, constraint, length(depth))
                end
                # Register metric results TODO

                @test _test
            end
        end
    end : quote end
end
