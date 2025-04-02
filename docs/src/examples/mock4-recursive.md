

# Recursive Suite Generation

This mock example explains how PerfTest can recursively integrate files into a performance test suite.


```julia
using Test
using PerfTest


# Note the config here disables verbosity but the nested files enable it, inside the nested file its config has priority
@perftest_config "
[regression]
enabled = false
[general]
verbose = false
"

@testset "A" begin
    @testset "A.1" begin
        # Check that time elapsed is less than one second, applies to the targets inside this testset
        @perfcompare :median_time < 1
        # Being "mock3-roofline.jl" a file with the roofline mock example source code.
        include("mock3-roofline.jl")
    end
    include("mock3-roofline.jl")
end
```

This will execute the same roofline test but under different hierarchies, also the first one will have an
additional performance metric assertion with perfcompare. All test are successful.
