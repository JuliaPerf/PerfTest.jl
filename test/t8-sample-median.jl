using Test
using PerfTest

@testset "_sample_median tests" begin
    @test PerfTest._sample_median([1.0, 2.0, 3.0]) == 2.0
    @test PerfTest._sample_median([1.0, 2.0, 3.0, 4.0]) == 2.5
    @test PerfTest._sample_median([5.0]) == 5.0
    @test PerfTest._sample_median([3.0, 1.0, 2.0]) == 2.0
    @test PerfTest._sample_median([4, 1, 3, 2]) == 2.5
end
