

# Roofline

This mock example explains how to setup the effective roofline methodology.


```julia
using Test
using PerfTest

# Disable regression enable verbosity to see successful tests
@perftest_config "
[regression]
enabled = false
[general]
verbose = true
"


# TEST TARGET
function polynom(x :: Float64, coeff :: Vector{Float64})

    res = 0.

    for i in length(coeff):-1:1
        res += coeff[i] * x ^ i
    end

    return res
end

@testset "Example" begin

    N = 50

    coeff = rand(N)
    x = 1.0

    # To use a variable in macro formulas, it has to be exported (i.e. N)
    @export_vars N
    @roofline actual_flops=:autoflop target_ratio=0.1 begin
        :autoflop / ((1 + N)*4)
    end

    # Set the target
    res = @perftest polynom(x, coeff)
end
```

This test results in a success to meet the expectation.
