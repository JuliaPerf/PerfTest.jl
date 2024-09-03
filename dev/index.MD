# [PerfTest.jl] [![Star on GitHub](https://img.shields.io/github/stars/JuliaPerf/PerfTest.jl.svg)](https://github.com/JuliaPerf/PerfTest.jl/stargazers)
The package `PerfTest` provides the user with a performance regression unit testing framework. This framework consists of a collection of macros used to declaratively define a performance test suite. Scripts with said macros can then be transformed into performance suites using the `transform` method. This package is focused on providing an easy and fast way to develop performance suites, with additional features to customise them following the demands of the use case.

## Dependencies
`PerfTest` relies on:
 - [MacroTools]
 - [JLD2]
 - [MPI]
 - [STREAMBenchmark]
 - [GFlops]
 - [UnicodePlots]
 - [Test]
 - [Suppressor]

## Contributors
This project has been developed as a Master's thesis by Daniel Sergio Vega Rodriguez.
Thus, the contributors to this project have been so far:
- Daniel Sergio Vega Rodriguez ([@Dvegrod](https://github.com/Dvegrod)), Università della Svizzera italiana (USI): developer
- Dr. Samuel Omlin ([@omlins](https://github.com/omlins)), Swiss National Supercomputing Centre (CSCS), ETH Zurich: original idea and Master's thesis supervisor
- Prof. Olaf Schenk, Università della Svizzera italiana (USI): Master's thesis supervisor
- Dr. Pasadakis Dimosthenis, Università della Svizzera italiana (USI): additional advisor
