
using Pkg

Pkg.instantiate()
Pkg.build("Pardiso", verbose=true)

using PerfTest

@info "Transforming expression"
expr = PerfTest.transform("pardisotest.jl")

@info "Saving at ./test.jl"
PerfTest.saveExprAsFile(expr, "test.jl")

@info "Executing test suite"
include("test.jl")
