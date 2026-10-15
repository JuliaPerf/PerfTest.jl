# Careful changing testset names (used for parsing)
using Test, PerfTest

@perftest_config "
[regression]
enabled = true
"

# Durations are deliberately far apart and, crucially, held constant across
# runs (no execution_number scaling): under the collapsed-to-last-iteration
# bug, every iteration ends up compared against n=3's (the last iteration's)
# short reference, so n=1/n=2's much longer runtime looks like a huge
# regression on the second execution even though each iteration's own
# runtime never changed. Correct per-iteration matching should pass every
# iteration on every execution.
durations = Dict(1 => 0.4, 2 => 0.2, 3 => 0.05)

@testset "Wrapper" begin

    @testset "Sleep by size" for n in [1, 2, 3]

        @perftest samples = 3 sleep(durations[n])

    end

end
