using BenchmarkTools

StrOrSym = Union{String,Symbol}

"""
This struct is used in the test suite to save a metric measurement,
therefore its saves the metric `name`, its `units` space and its `value`.
"""
@kwdef struct Metric_Result{N}
    name::AbstractString
    # Used to identify the metric in some situations
    units::AbstractString
    value::N
end


"""
This struct is used in the test suite to save a metric reference,
a reference is meant to be later compared with a result, its combination gives the `Metric_Constraint` struct.
It holds:
 - A `reference` value.
 - `low_is_bad` registers if in this metric lower values are less desired than higher ones, or the opposite (e.g. time vs  FLOP/s).
"""
@kwdef struct Metric_Reference{N}
    reference::N
    low_is_bad::Bool
    # [!!] Unused yet
    custom_elements::Vector{Symbol} = Symbol[]
end

"""
This struct is used in the test suite to save a metric test result and its associated data, it saves the reference used and the toreance intervals in absolute and percentual values, also it shows if the test succeded and some additional variables for data printing
"""
@kwdef struct Metric_Constraint{N}
    reference::N
    threshold_min::N
    threshold_min_percent::Float64
    threshold_max::N
    threshold_max_percent::Float64
    low_is_bad::Bool
    succeeded::Bool
    # Additional metric X methodology data
    custom_plotting::Vector{Symbol}
    full_print::Bool
end


# A custom methodology element is used to save informational metrics, other special values and custom functions to be executed after testing.
Custom_Methodology_Elements = Union{Metric_Result,Float64,Function}


"""
This struct is used in the test suite to save a methodology result, which in turn is constituted of a group of metric results and their references. Additionally, custom elements that are not subject to test are also saved, e.g. informational metrics, printing functions.
"""
@kwdef struct Methodology_Result
    name::AbstractString
    metrics :: Vector{Pair{Metric_Result, Metric_Constraint}}
    custom_elements::Dict{Symbol, Custom_Methodology_Elements} = Dict{Symbol, Custom_Methodology_Elements}()
    custom_auto_print::Bool = true
end

"""
This struct saves a complete test suite result for one execution. It also saves the raw measurements obtained from the targets.
"""
@kwdef struct Perftest_Result
    timestamp :: Float64
    benchmarks :: BenchmarkGroup
    perftests :: Dict
end

"""
This struct is the root of the data recording file, it can save several performance test suite execution results.
"""
@kwdef struct Perftest_Datafile_Root
    results :: Vector{Perftest_Result}
    methodologies_history :: Vector{Dict{StrOrSym, Any}}
end

