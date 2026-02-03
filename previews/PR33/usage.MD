# Usage

`PerfTest` provides a set of macros to instrument ordinary Julia test files with performance tests. The idea is to have the posibility of having a functional and a performance suite all in the same place.

The underlying idea of declaring performance tests can be boiled down the following:

1. Have a @testset that groups tests for a software unit
2. Tell PerfTest what is the target to be tested by using the macro @perftest
3. Tell PerfTest how the target shall be tested, which metrics are interesting, which of those metrics values would be considered a failure, this can be declared using the metric and methodology macros (see Macros)

The following dummy example embodies the paradigm of the package:

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


For more information have a look at the [Examples](@ref) and see the [API reference](@ref) for details on the usage of `PerfTest`.


## Installation

`PerfTest` can be installed directly with the [Julia package manager] from the [Julia REPL]:
```julia
  using Pkg
  Pkg.add("https://github.com/JuliaPerf/PerfTest.jl.git")
```

