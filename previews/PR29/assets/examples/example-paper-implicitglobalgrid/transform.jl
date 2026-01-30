
using Pkg

Pkg.update()
Pkg.instantiate()
using Revise,PerfTest
#PerfTest.toggleMPI()

@info "Transforming expression"
expr = PerfTest.transform(ARGS[1])

@info "Saving at ./test.jl"
PerfTest.saveExprAsFile(expr, "test.jl")

@info "Executing test suite"
include("test.jl")
