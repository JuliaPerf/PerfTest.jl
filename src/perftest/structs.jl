using Dates
using BenchmarkTools

@kwdef struct Metric_Result{N}
    name::AbstractString
    units::AbstractString
    value::N
end

@kwdef struct Metric_Constraint{N}
    reference::N
    threshold_min::N
    threshold_min_percent::Float64
    threshold_max::N
    threshold_max_percent::Float64
    low_is_bad::Bool
end

@kwdef struct Methodology_Result
    name::AbstractString
    metrics :: Vector{Metric_Constraint}
end


@kwdef struct Perftest_Result
    timestamp :: Float64
    benchmarks :: BenchmarkGroup
    perftests :: Dict
end

@kwdef struct Perftest_Datafile_Root
    results :: Vector{Perftest_Result}
end

