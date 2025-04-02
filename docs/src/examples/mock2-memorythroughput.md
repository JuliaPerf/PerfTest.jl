
# Effective memory throughput

This mock example explains how to setup the effective memory throughput methodology.

The memory bandwidth test is more appropriate for functions that are primarily moving data, with reduced protagonism to computation performance.

```julia

using Test
using PerfTest


@perftest_config "
[regression]
enabled = false
"


# TEST TARGET
function copyvec_squared(a :: Vector{Int})

    b = zeros(length(a))

    for i in 1:length(a)
        b[i] = a[i] * a[i]
    end

    return b
end

@testset "Example" begin

    N = 1000000

    a = rand(Int, N)

    # To use a variable in macro formulas, it has to be exported (i.e. N)
    @export_vars N
    # The ratio sets the threshold, being 1.0 the maximum empirical bandwidth and 0.6 = 60% of such maximum
    @define_eff_memory_throughput ratio=0.6 begin
        # The main block of the macro holds the formula for the bandwidth (therefore BYTES divided by SECONDS) on
        # one single execution of the test target.
        # In this case per execution N elements of 4 Bytes are Read on Memort + Written
        # on Cache + Written on Memory (Copy on write assumption by default)
        # The median time is considered an adequate measure for the denominator in this case
        # THUS:
        N * 4 * 3 / :median_time
    end

    # Set the target
    b = @perftest copyvec_squared(a)
end
```

This test results in a failure to meet the expectation.
