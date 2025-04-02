
using Pkg

Pkg.instantiate()
using PerfTest
PerfTest.toggleMPI()

@info "Transforming expression"
expr = PerfTest.transform("EXP_test_halo.jl")

@info "Saving at ./test.jl"
PerfTest.saveExprAsFile(expr, "test.jl")

@info "Executing test suite"
include("test.jl")
