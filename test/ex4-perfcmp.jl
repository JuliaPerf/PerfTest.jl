using Test
using PerfTest

function testfun(a :: Int)

    sleep(1)
end


@testset "FIRST LEVEL" begin
	  @testset "SECOND LEVEL" begin

        @perfcompare :median_time < 3
        @perfcompare :median_time < 5
        # @perfcompare :median_time < 1
        x = @perftest samples=5 testfun(10)
    end
end
