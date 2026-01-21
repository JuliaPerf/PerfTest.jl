using Test
using PerfTest

if !(PerfTest.Configuration.load_config() isa Nothing)

    include("t1-validation-formula.jl")
    include("t2-validation-macro.jl")
    include("t3-transforms.jl")

end