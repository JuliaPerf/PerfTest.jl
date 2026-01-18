
using Test
using PerfTest

@perftest_config "
[regression]
enabled = true
use_bencher = true
"

function testfun()
    sleep(1)
    return
end


@testset "FIRST LEVEL" begin
	  @testset "SECOND LEVEL" begin
	      x = @perftest testfun()
    end
end
