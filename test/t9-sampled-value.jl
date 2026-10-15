using Test
using PerfTest

const SV = PerfTest.SampledValue

@testset "SampledValue construction" begin
    sv = SV([1.0, 2.0, 3.0, 4.0, 5.0], 3.0)
    @test sv.value == 3.0
    @test sv.n == 5
    @test sv.sem > 0

    single = SV([1.0], 1.0)
    @test single.sem == 0.0
    @test single.n == 1
end

@testset "SampledValue promotion / conversion" begin
    x = convert(SV{Float64}, 5.0)
    @test x.value == 5.0
    @test x.sem == 0.0
    @test x.n == typemax(Int)

    @test promote_type(SV{Float64}, Float64) == SV{Float64}
end

@testset "SampledValue comparisons ignore sem/n" begin
    a = SV(0.04, 0.01, 50)
    @test a < 0.05
    @test a == SV(0.04, 0.5, 3)
    @test !(a == 0.05)
end

@testset "SampledValue +/- (absolute quadrature)" begin
    a = SV(10.0, 1.0, 40)
    b = SV(5.0, 2.0, 60)
    s = a + b
    @test s.value == 15.0
    @test isapprox(s.sem, sqrt(1.0^2 + 2.0^2))
    @test s.n == 40

    d = a - b
    @test d.value == 5.0
    @test isapprox(d.sem, sqrt(1.0^2 + 2.0^2))

    @test (-a).value == -10.0
    @test (-a).sem == 1.0
    @test (+a).value == a.value
end

@testset "SampledValue * // (relative quadrature)" begin
    a = SV(10.0, 1.0, 40)   # 10% relative error
    b = SV(4.0, 0.4, 60)    # 10% relative error

    p = a * b
    @test p.value == 40.0
    @test isapprox(p.sem, 40.0 * sqrt(0.1^2 + 0.1^2))
    @test p.n == 40

    q = a / b
    @test q.value == 2.5
    @test isapprox(q.sem, 2.5 * sqrt(0.1^2 + 0.1^2))
end

@testset "SampledValue mixed arithmetic with plain Real" begin
    a = SV(10.0, 1.0, 40)
    r = a + 5.0
    @test r isa SV
    @test r.value == 15.0
    @test r.sem == 1.0   # plain Real contributes zero variance

    r2 = a * 2.0
    @test r2.value == 20.0
    @test isapprox(r2.sem, 2.0)   # relative error of a (10%) applied to new value (20.0)

    r3 = 100.0 / a
    @test r3.value == 10.0
end

@testset "SampledValue degenerate / division-by-zero cases" begin
    a = SV(10.0, 1.0, 40)
    zero_val = SV(0.0, 0.0, 40)
    d = a / zero_val
    @test isnan(d.value)
    @test isnan(d.sem)
end

@testset "sum over a Vector{SampledValue}" begin
    vals = [SV(1.0, 0.1, 40), SV(2.0, 0.2, 40), SV(3.0, 0.3, 40)]
    s = sum(vals)
    @test s.value == 6.0
    @test isapprox(s.sem, sqrt(0.1^2 + 0.2^2 + 0.3^2))
    @test s.n == 40
end
