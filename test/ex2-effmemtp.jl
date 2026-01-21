using Test
using PerfTest

@perftest_config "
[regression]
enabled = false
[general]
verbose = true
"

function testfun(a :: Int)

    c = 1

    for i in 1:a
        c = c + (i ^ 2) / c
    end

    return c
end


@testset "FIRST LEVEL" begin
	  @testset "SECOND LEVEL" begin

        @define_eff_memory_throughput ratio=0.01 begin
	          2.0 + 5.0 * 1_000_000_000
        end
        @perftest x = testfun(10)

        @test x == 29.299107353275982
    end
end
