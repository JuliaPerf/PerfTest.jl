using Dates
using BenchmarkTools

StrOrSym = Union{String,Symbol}

@kwdef struct Metric_Result{N}
    name::AbstractString
    # Used to identify the metric in some situations
    units::AbstractString
    value::N
end


# This is used when the struct below has not been built yet
@kwdef struct Metric_Reference{N}
    reference::N
    low_is_bad::Bool
    # [!!] Unused yet
    custom_elements::Vector{Symbol} = Symbol[]
end

@kwdef struct Metric_Constraint{N}
    reference::N
    threshold_min::N
    threshold_min_percent::Float64
    threshold_max::N
    threshold_max_percent::Float64
    low_is_bad::Bool
    succeeded::Bool
    # Additional metric X methodology data
    custom_plotting :: Vector{Symbol}
    full_print::Bool
end

# Fields to save additional data for a methodology
# For example cpu peak in roofline methodology
Custom_Methodology_Elements = Union{Metric_Result, Float64, Function}

@kwdef struct Methodology_Result
    name::AbstractString
    metrics :: Vector{Pair{Metric_Result, Metric_Constraint}}
    custom_elements::Dict{Symbol, Custom_Methodology_Elements} = Dict{Symbol, Custom_Methodology_Elements}()
    custom_auto_print::Bool = true
end


@kwdef struct Perftest_Result
    timestamp :: Float64
    benchmarks :: BenchmarkGroup
    perftests :: Dict
end

@kwdef struct Perftest_Datafile_Root
    results :: Vector{Perftest_Result}
    methodologies_history :: Vector{Dict{StrOrSym, Any}}
end

