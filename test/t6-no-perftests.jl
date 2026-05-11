
using Test, PerfTest

@testset "No perf tests" begin
    include("test-recipes/ex9-no-perftests.jl")

    @test all([r isa Test.DefaultTestSet for r in Test.get_testset().results])
end