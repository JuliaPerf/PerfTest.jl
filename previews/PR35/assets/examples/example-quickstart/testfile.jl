using Test,PerfTest

include("module.jl")

@perftest_config "
[general]
verbose = 3
[regression]
dedicated_reference_file='reference.JLD2'
"

@testset "addReversed tests" begin
    N = 10
    # We want the size to be bigger on the performance test
    @on_perftest_exec begin
        N = 1_000_000
    end
    # We set the regression checker, we dont specify a metric therefore the default (median time elapsed) is used
    # low_is_bad=false time elapsed metrics are considered worse the bigger they are
    # threshold = 1.05 the test will fail if the time is 105% of the reference or greater, in other words: @test time_elapsed < 1.05 * reference
    @regression threshold=1.05 low_is_bad=false

    A = [i for i in 1:N]
    B = [N-i for i in 1:N]

    result = @perftest MyPackage.addReversed(A, B)
    @test sum(result) == N*N 
end