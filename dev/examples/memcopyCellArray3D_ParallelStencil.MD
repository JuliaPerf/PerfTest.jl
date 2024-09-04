# Roofline example: option pricing

In this example we setup a roofline model methodology to test the resolution of a binomial tree using a slow implementation.

```julia
rfd_rt(r,t_per_p) = rfd(t) = exp(-r * t * t_per_p)
up_st(sigma, t_per_p) = exp(sigma * sqrt(t_per_p))

struct _Parameters
    sigma   :: Float64
    periods :: Int
    t_per_p :: Float64
    rfd     :: Function
    up      :: Float64
    K       :: Float64
    S0      :: Float64
    p       :: Float64
end

function setupProblem(sigma, t, periods_per_t, risk_free_rate, strike, price, p) :: _Parameters
    return _Parameters(
        sigma,
        t * periods_per_t,
        1 / periods_per_t,
        rfd_rt(risk_free_rate, 1 / periods_per_t),
        up_st(sigma, 1 / periods_per_t),
        strike,
        price,
        p
    )
end

function createBinomialTree(p :: _Parameters)::Tuple{Matrix,Array}

    nodes = (p.periods + 1) * p.periods ÷ 2
    # A and b
    Tree = zeros(Float64, nodes, nodes)
    B = zeros(Float64, nodes)

    # Fill the body of the tree with the discounted expectations
    for period in 1:(p.periods-1)
        _nodes = ((period-1)*period÷2+1):((period+1)*(period+0)÷2)
        for node in _nodes
            Tree[node, node] = -1
            Tree[node, node+period] = p.p * p.rfd(p.periods - period)
            Tree[node, node+period+1] = 1 - p.p * p.rfd(p.periods - period)
        end
    end

    # Fill the last level of the tree with the prices at maturity
    xa = ((p.periods - 1) * p.periods ÷ 2 + 1)
    xb = ((p.periods + 1) * (p.periods + 0) ÷ 2)
    down = 1 / p.up

    for node in xa:xb
        Tree[node, node] = 1
        B[node] = max((p.S0 * p.up^(xb - node) * down^(node - xa)) - p.K, 0.0)
    end
    return Tree, B
end


function solveTree(A::Matrix, b::Array, periods::Int)::Array

    nodes = (periods + 1) * periods ÷ 2
    X = zeros(Float64, nodes)
    # Last level nodes from a to b
    xa = ((periods - 1) * periods ÷ 2 + 1)
    xb = ((periods + 1) * (periods + 0) ÷ 2)
    for node in xa:xb
        X[node] = b[node]
    end
    # Tree core nodes
    for period in (periods-1):-1:1
        _nodes = ((period-1)*period÷2+1):((period+1)*(period+0)÷2)
        for node in _nodes
            X[node] = A[node, node+period] * b[node+period] + A[node, node+period+1] * b[node+period+1]
            b[node] = X[node]
        end
    end

    return X
end

option_price(solution :: Array) = solution[1]

```

The following is the recipe file that sets up the performance test suite:

```julia
using Test
using PerfTest

include("main3.jl")

# CONFIG
@perftest_config begin
    regression.enabled = false
    roofline.autoflops = true
    roofline.tolerance.min_percentage = 1.0
end


@testset "Performance Tests" begin

    @testset "Tree construction" begin

        @testset "Periods" for n_periods in [16, 64, 128]

            param = setupProblem(0.04, 1, n_periods, 0.04, 100, 100, 0.5)

            @roofline actual_flops=:autoflop target_ratio=0.05 begin
                mem = ((:iterator + 1) * :iterator)
                :autoflop / mem
            end
            A, b = createBinomialTree(param)


            @perftest solveTree(A, b, param.periods)
        end
    end
end
```

The recipe file specifies the following:
 - The target will be evaluated using a roofline model
 - The basic regression methodology is disabled
 - The tolerance below the threshold will be zero
 - The autoflops feature is enabled
 - The roofline macro additionally receives how to calculate the flop count (actual_lops=:autoflop) and the threshold of the actual performance vs model performance is 5%
