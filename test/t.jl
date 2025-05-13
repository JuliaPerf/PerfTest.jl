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


