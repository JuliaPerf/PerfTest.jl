using Test
using PerfTest

function testfun(a :: Int)

    c = 1

    for i in 1:a
        c = c + (i ^ 2) / c
    end

    return c
end


@testset "FIRST LEVEL" begin
	  @testset "SECOND LEVEL" begin

        # The flop count is given, automatic flop counting (:autoflop) is not supported
        @roofline actual_flops=40 target_ratio=0.5 begin
	          40 / 4
        end
        x = @perftest testfun(10)

        @test x == 29.299107353275982
    end
end
