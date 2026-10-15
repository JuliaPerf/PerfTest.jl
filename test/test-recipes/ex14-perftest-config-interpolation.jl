using Test
using PerfTest

@perftest_config "
[general]
verbose = 3
[regression]
enabled = true
dedicated_reference_file = 'ref_$(1 + 1).JLD2'
"

function testfun(a :: Int)
    c = 1
    for i in 1:a
        c = c + (i ^ 2) / c
    end
    return c
end

@testset "CONFIG INTERPOLATION" begin
    x = @perftest testfun(10)
    @test x == 29.299107353275982
end
