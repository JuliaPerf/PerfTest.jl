# PerfTest.jl - A performance unit testing framework

NOTE: This package is under active development, bugs may lurk around, if a bug is found please raise an issue so it can be adressed. Thanks :)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaPerf.github.io/PerfTest.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaPerf.github.io/PerfTest.jl/dev)
[![CI](https://github.com/JuliaPerf/PerfTest.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/JuliaPerf/PerfTest.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaPerf/PerfTest.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaPerf/PerfTest.jl)

The package PerfTest provides the user with a performance regression unit testing framework. This package is focused on providing a simple and fast way to develop performance suites, with additional features to customise them for more comprehensice use cases.

## Basic performance evaluation

PerfTest.jl provides a set of macros to provide declarative instructions to the performance testing suit generator. A simple case will be shown here.

```julia
module VecOps
function innerProduct(A , B)
    @assert length(A) == length(B)

    r = 0.

    for i in eachindex(A)
        r += A[i] * B[i]
    end

    return r
end
end
```

In this example, we are implementing a inner product function as part of a bigger vector operation packages. We are interested in evaluating the performance of that product, the following test file is a recipe to do so:


```julia
using Test, PerfTest
include("VecOps.jl") # Either that or using/import 

# Disable regression enable verbosity to see successful tests
@perftest_config "
[general]
verbose = true

[regression]
enabled = false
"

@testset "Simple test" begin

    N = 1000
    A,B = rand(N), rand(N)

    @perfcompare :median_time < (0.000005 * N)
    @perftest VecOps.innerProduct(A,B)

end

```

Where:
    @perftest sets the computation to target for the tests.
    @perfcompare sets the testing methodology which is comparing the median time elapsed against a reference that is dependent on the size of the vectors.
    @perftest_config sets the configuration in a TOML format, in this case to disable automatic regression testing


PertTest.jl relies on a configuration file written in TOML to refer for settings that are not specified anywhere else. In case no file is present, it will be made with the default configuration enabled. Please see the documentation for more information.


## Dependencies

```
BenchmarkTools
CountFlops
CpuId
JLD2
JSON
MLStyle
MacroTools
STREAMBenchmark
Suppressor
UnicodePlots
Dates
 LinearAlgebra
Pkg
Printf
TOML
Test
```

## Installation
ImplicitGlobalGrid may be installed directly with the [Julia package manager](https://docs.julialang.org/en/v1/stdlib/Pkg/index.html) from the REPL:
```julia-repl
julia>]
  pkg> add https://github.com/JuliaPerf/PerfTest.jl
  pkg> test PerfTest
```

## Questions, comments and discussions

Please email: vegard@usi.ch or raise an issue.

## Your contributions

Help is more than welcome! If you have an idea/contribution that could benefit from this project, please share!
