# Quickstart

`PerfTest` provides a set of macros to instrument ordinary Julia test files with performance tests. The idea is to have the posibility of having a functional and a performance suite all in the same place.

The underlying idea of declaring performance tests can be boiled down the following:

1. Have a @testset that groups tests for a software unit
2. Tell PerfTest what is the target to be tested by using the macro @perftest
3. Tell PerfTest how the target shall be tested, which metrics are interesting, which of those metrics values would be considered a failure, this can be declared using the metric and methodology macros (see Macros)

The following dummy example presents how a recipe file looks like:

```julia
using ExampleModule : innerProduct, Test, PerfTest   # Importing the target and test libraries
@testset "Roofline Test" begin
    a,b = rand(1e6),rand(1e6)

    @roofline actual_flops=:autoflop target_ratio=0.5
        :autoflop / (2 * 8 * 1e6)
    end

    @perftest innerProduct(a, b)
    @test innerProduct(a,b) == sum(a .* b)
end
```

The following things can be appreciated in this example:
1. This is a combined functional and performance unit test suite (there is both @test and @perftest present)
2. The target of the perftest is the innerProduct function
3. The performance test methodology is a roofline model, the developer expects innerProduct to perform at least at 50% of the maximum flop performance set by the roofline. The operational intensity is defined on the main block of the macro. :autoflop is a symbol that enables the use of an automatic flop count feature.

## How to use, a first PerfTest.jl recipe

Lets assume we are a developer that wants to track performance regressions on the components of a package in development. We have the following module:

```julia
module MyPackage

# Add [a[1],a[2],...a[end]] and [b[end], b[end-1],...,b[1]] elementwise
function addReversed(A :: Vector{<: Number}, B:: Vector{<: Number}) :: Vector{<:Number}
   return [a + b for (a,b) in zip(A, reverse(B))]
end

end
```

We want to track the performance of this package in order to detect performance regressions. To do so we build the following test recipe:

```julia
using Test,PerfTest

@perftest_config "
[general]
verbose = true
[regression]
dedicated_reference_file='reference.JLD2'
"

@testset "addReversed tests" begin
    N = 10
    # We want the size to be bigger on the performance test
    @on_perftest_exec begin
        N = 1_000_000
    end
    # We set the regression checker, we dont specify a metric therefore the default (median time elapsed) is used
    # low_is_bad=false time elapsed metrics are considered worse the bigger they are
    # threshold = 1.05 the test will fail if the time is 105% of the reference or greater, in other words: @test time_elapsed < 1.05 * reference
    @regression threshold=1.05 low_is_bad=false

    A = [i for i in 1:N]
    B = [N-i for i in 1:N]

    result = @perftest addReversed(A, B)
    @test sum(result) == N*N 
end
```

### Running the functional test side of the recipe:

```julia
    include("testfile.jl")
```

Or if the file is in the test folder of the package:
```julia
    using Pkg; Pkg.test()
```

Or alternatively:
```julia
    using Test; runtests("testfile.jl")
```

### Running the performance test side of the recipe:

We are doing regression, so in case no reference has been made we will need to execute it at least twice. Once to record the reference, and after that whenever the developer wants to check for a performance regression.

The first time PerfTest is run on a specific directory, a configuration file will be created with a set of default values. Configuration parameters can be set as well by the `@perftest_config` macro, as seen above. The macro takes the highest priority over any other configuration source.
```julia
    # This will record a successful performance suite
    using PerfTest; runperftests("testfile.jl")
```

In between, the developer adds new changes to the implementation or checks out a different git branch.

```julia
    # This will compare the suite results against the reference, if the tests are sucessful the results become the reference.
    using PerfTest; runperftests("testfile.jl")
```


For more information have a look at the [Examples](@ref) and see the [API reference](@ref) for details on the usage of `PerfTest`.

## Main use cases of this package:

This package supports both performance testing by regression checks and by performance methodologies, e.g roofline models. It is meant to cover the following two situations:

    1. A developer wants to track potential regressions over the course of package development.
    2. A developer wants to set machine-agnostic performance tests by using methodologies or custom metrics that are normalized by machine parameters, with the purpose of verifying that the package profits from the capabilities of the machines its been executed on.
        2.1. During development.
        2.2. During the whole software lifecycle, users can check if the package is properly set up in their machine.

## Installation

`PerfTest` can be installed directly with the [Julia package manager] from the [Julia REPL]:
```julia
  using Pkg
  Pkg.add("https://github.com/JuliaPerf/PerfTest.jl.git")
```

