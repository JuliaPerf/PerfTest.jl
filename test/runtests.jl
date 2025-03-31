using Test
using PerfTest

PerfTest.Configuration.load_config()

include("t1-validation-formula.jl")
include("t2-validation-macro.jl")
include("t3-transforms.jl")
