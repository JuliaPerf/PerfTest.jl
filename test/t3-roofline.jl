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

        @define_test_metric nme="TEST" units="undef" reference=begin 3+1 end begin
	          4+1
        end
        x = @perftest testfun(10)

        @test x == 29.299107353275982
    end
end
