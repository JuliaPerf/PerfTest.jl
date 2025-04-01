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

        @roofline actual_flops=:autoflop target_ratio=0.5 begin
	          :autoflop / 4
        end
        x = @perftest testfun(10)

        @test x == 29.299107353275982
    end
end
