# Included by ex17-config-recursive.jl inside a testset

@perftest_config "
[general]
verbose = 1
max_saved_results = 3
"

@testset "INNER" begin
    @on_perftest_exec begin
        dumpConfig("INNER")
    end
    @perftest samples = 1 sin(1.0)
end
