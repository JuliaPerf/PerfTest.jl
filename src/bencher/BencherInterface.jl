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
    flatten_test_hierarchy(results::Dict{String, Union{Dict, Test_Result}}, prefix::String="") -> Dict{String, Test_Result}

Recursively flatten a nested dictionary of test results into a single-level dictionary.
The hierarchy levels are incorporated into the keys using "::" as a separator.

Example:
    {
        "level1": {
            "level2": {
                "benchmark_name": Test_Result
            }
        }
    }

    becomes:

    {
        "level1::level2::benchmark_name": Test_Result
    }
"""
function processTestHierarchy(results::Dict{String, Union{Dict, Test_Result}}; prefix::String="", auxiliaries = false :: Bool) :: Dict{String, Dict}

    flattened = Dict{String, Dict}()

    for (key, value) in results
        # Create the current path
        current_path = isempty(prefix) ? key : "$prefix::$key"

        if value isa Test_Result
            # We found a Test_Result, add it to our flattened dictionary
            for methodology in value.methodology_results
                flattened[current_path * "::" * methodology.name] = processMethodology(methodology)
            end
            if auxiliaries
                for (key,aux) in value.auxiliar
                    flattened[current_path * "::" * "AUX::" * aux.name] = convertValueWithMagnitude(aux.value, aux.magnitude_mult)
                end
                for (key,aux) in value.primitives
                    flattened[current_path * "::" * "AUX::"] = Dict()
                    flattened[current_path * "::" * "AUX::"][String(key)] = aux
                end
                for (key,aux) in value.metrics
                    flattened[current_path * "::" * "AUX::" * aux.name] = convertValueWithMagnitude(aux.value, aux.magnitude_mult)
                end
            end
        elseif value isa Dict
            # Recursively process nested dictionary
            nested_results = processTestHierarchy(
                value;
                prefix=current_path,
                auxiliaries=auxiliaries
            )
            merge!(flattened, nested_results)
        else
            @warn "Unexpected type encountered at $current_path: $(typeof(value))"
        end
    end

    return flattened
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

end  # module
