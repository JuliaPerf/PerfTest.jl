
using Pkg

Pkg.update()
Pkg.instantiate()
using PerfTest

@info "Transforming expression"
expr = PerfTest.transform(ARGS[1])

@info "Saving at ./test.jl"
PerfTest.saveExprAsFile(expr, "test.jl")

@info "Executing test suite"
include("test.jl")
