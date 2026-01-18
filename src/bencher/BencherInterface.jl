module BencherInterface


export exportToJSON, writeJSONtoFile
using JSON
import PerfTest
import ..Metric_Result
import ..Metric_Test
import ..Methodology_Result
import ..Test_Result
import ..Suite_Execution_Result
import ..Perftest_Datafile_Root
import ..GlobalSuiteData


"""
    convert_value_with_magnitude(value::T, magnitude_mult::Number) where T

Apply magnitude multiplier to the value.
"""
function convertValueWithMagnitude(value::T, magnitude_mult::Number) where {T}
    if magnitude_mult != 0
        return value * magnitude_mult
    else
        return value
    end
end


"""
Process a methodology result to extract and format metrics with their corresponding thresholds.

Args:
    methodology: A Methodology_Result object containing metrics and test information.

Returns:
    A dictionary where keys are metric names and values are dictionaries containing the metric's
    processed value, lower threshold, and optionally a higher threshold.
"""
function processMethodology(methodology :: Methodology_Result) :: Dict{String, Dict}

    metrics = Dict{String, Dict}()

    for (metric, test) in methodology.metrics
        metrics[metric.name] = Dict()
        metrics[metric.name]["value"] = convertValueWithMagnitude(metric.value, metric.magnitude_mult)
        metrics[metric.name]["lower_value"] = test.threshold_min_percent * test.reference
        if test.threshold_max_percent isa Nothing
        else
            metrics[metric.name]["higher_value"] = test.threshold_max_percent * test.reference
        end
    end

    return metrics
end



"""
    write_results_to_file(filepath::String, json_data::Dict)

Write JSON data to a file.
"""
function writeJSONtoFile(filepath::String, json_data::Dict)
    open(filepath, "w") do io
        JSON.print(io, json_data, 4)  # 4 spaces indentation
    end
    @info "Results exported to $filepath"
end

"""
    export_suite_to_json(suite::Suite_Execution_Result) -> Dict

Convert an entire suite execution result to JSON format.
"""
function exportToJSON(filepath::String, suite::Suite_Execution_Result, include_auxiliaries = false)

    flattened = processTestHierarchy(suite.perftests; auxiliaries = include_auxiliaries)

    writeJSONtoFile(filepath, flattened)

end

end