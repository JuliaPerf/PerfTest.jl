
using Test
using PerfTest


@testset "RECURSIVE" begin
	  include("ex4-perfcmp.jl")

    @testset "RECURSIVE 2" begin
	      include("ex4-perfcmp.jl")
    end
end
