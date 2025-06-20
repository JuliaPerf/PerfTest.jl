
using BenchmarkTools: BenchmarkGroup


mutable struct DepthRecord
    name :: AbstractString
    header_printed :: Bool

    DepthRecord(name) = new(name, false)
end

StrOrSym = Union{String,Symbol}

struct MPI_MetricInfo
    size :: Int
    reduct :: AbstractString
end

"""
This struct is used in the test suite to save a metric measurement,
therefore its saves the metric `name`, its `units` space and its `value`.
"""
struct Metric_Result{N}
    name::AbstractString
    # Used to identify the metric in some situations
    units::AbstractString
    value::N
    auxiliary::Bool
    # Below are magnitude specifiers for the value given (might not apply in some cases e.g. String
    magnitude_prefix::AbstractString
    magnitude_mult::Number
    # Additional data for MPI
    mpi :: Union{Nothing, MPI_MetricInfo}
end

function newMetricResult(::Type{<:NormalMode};name, units, value, auxiliary = false, magnitude_prefix = "", magnitude_mult = 0, reduct="")

    return Metric_Result(name,units,value,auxiliary, magnitude_prefix, magnitude_mult, nothing)
end

"""
This struct is used in the test suite to save a metric test result and its associated data, it saves the reference used and the toreance intervals in absolute and percentual values, also it shows if the test succeded and some additional variables for data printing
"""
@kwdef struct Metric_Test{N}
    reference::N
    threshold_min_percent::Float64
    threshold_max_percent::Union{Nothing, Float64}
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
    metrics :: Vector{Pair{Metric_Result, Metric_Test}} = Pair{Metric_Result, Metric_Test}[]
    custom_elements::Dict{Symbol, Custom_Methodology_Elements} = Dict{Symbol, Custom_Methodology_Elements}()
    custom_auto_print::Bool = true
end


"""

NOTE: SOME METRICS ARE REPEATED IN HERE AND INSIDE A METRIC RESULT, this redundancy is tolerated for now, the copy inside the methodology result might be substituted by a reference in the future.
"""
struct Test_Result
    name :: AbstractString
    primitives :: Dict{Symbol, Any}
    metrics :: Dict{Symbol,Metric_Result}
    auxiliar :: Dict{Symbol,Metric_Result}
    methodology_results :: Vector{Methodology_Result}

    Test_Result(name) = new(name,
                        Dict{Symbol,Metric_Result}(),
                        Dict{Symbol,Metric_Result}(),
                        Dict{Symbol,Metric_Result}(),
                        Methodology_Result[])
end


"""
This struct saves a complete test suite result for one execution. It also saves the raw measurements obtained from the targets.
"""
@kwdef struct Suite_Execution_Result
    timestamp::Float64
    benchmarks::BenchmarkGroup
    perftests::Dict{String, Union{Dict, Test_Result}}
end

"""
This struct is the root of the data recording file, it can save several performance test suite execution results.
"""
@kwdef struct Perftest_Datafile_Root
    results :: Vector{Suite_Execution_Result}
end



mutable struct GlobalSuiteData
    datafile :: Perftest_Datafile_Root
    datafile_path :: AbstractString
    origin_file :: AbstractString
    builtins :: Dict{Symbol,Any}
    custom_benchmarks::Dict{Symbol,Metric_Result}
    # TODO Migrate to testsets eventually, the following variables are used to do regression checks
    old::Union{Nothing, Dict{String,Union{Dict,Test_Result}}}
    new::Dict{String,Union{Dict,Test_Result}}

    GlobalSuiteData(datafile, path, origin) = new(datafile, path, origin, Dict{Symbol,Metric_Result}(), Dict{Symbol,Metric_Result}(), Dict{String,Union{Dict,Test_Result}}(), Dict{String,Union{Dict,Test_Result}}())
end

function main_rank() :: Bool
    return true
end

function ranks() :: Int
    return 1
end
