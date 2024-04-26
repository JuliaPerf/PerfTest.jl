using Dates
using BenchmarkTools

@kwdef struct Metric_Result{N}
    name::AbstractString
    units::AbstractString
    value::N
    reference::N
    threshold_min::N
    threshold_max::N
    low_is_bad::Bool
end

@kwdef struct Methodology_Result
    name::AbstractString
    metrics :: Vector{Metric_Result}
end


@kwdef struct Perftest_Result
    timestamp :: Float64
    benchmarks :: BenchmarkGroup
    perftests :: Dict
end

@kwdef struct Perftest_Datafile_Root
    results :: Vector{Perftest_Result}
end
