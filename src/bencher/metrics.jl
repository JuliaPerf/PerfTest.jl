# bencher_metrics.jl

"""
    search_measure(project_uuid::String, measure_name::String)

Search for a measure by name in the project.
"""
function search_measure(project_uuid::String, measure_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "GET")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/measures")
    set_bearer_token!(builder, config["api_key"])
    add_query_param!(builder, "name", measure_name)
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success && !isempty(response)
        return response[1]  # Return the first matching measure
    end
    
    return nothing
end

"""
    get_all_measures(project_uuid::String)

Get all measures for a project.
"""
function get_all_measures(project_uuid::String, config :: Dict) :: Dict{String, Dict}
    all_measures = Dict()
    page = 1
    per_page = 100  # Maximum allowed per page
    
    while true
        builder = RESTRequestBuilder()
        set_method!(builder, "GET")
        set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/measures")
        set_bearer_token!(builder, config["api_key"])
        add_query_param!(builder, "page", string(page))
        add_query_param!(builder, "per_page", string(per_page))
        
        request = build(builder)
        success, response, error = make_request(request)
        
        if !success
            @error "Failed to get measures: $error"
            break
        end
        
        if isempty(response)
            break
        end
        
        for measure in response
            all_measures[measure["name"]] = measure
        end
        
        # If we got fewer items than requested, we've reached the end
        if length(response) < per_page
            break
        end
        
        page += 1
    end
    
    return all_measures
end

"""
    create_measure(project_uuid::String, metric::BencherMetric)
    
Create a new measure in the project.
"""
function create_measure(project_uuid::String, metric::Metric_Result, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "POST")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/measures")
    set_bearer_token!(builder, config["api_key"])
    set_body!(builder, Dict{String,Any}(
        "name" => metric.name,
        "units" => metric.units
    ))
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success
        return response
    else
        error("Failed to create measure '$(metric.name)': $error")
    end
end


"""
    validate_metric_results(results::Dict{String, Any}, measures_dict::Dict{String, Any})

Validate that all metrics in the results have corresponding measures.
"""
function validate_metric_results(results::Dict{String, Any}, measures_dict::Dict{String, Any})
    missing_metrics = String[]
    
    for (metric_name, _) in results
        if !haskey(measures_dict, metric_name)
            push!(missing_metrics, metric_name)
        end
    end
    
    if !isempty(missing_metrics)
        @warn "Results contain metrics not registered with Bencher: $(join(missing_metrics, ", "))"
        @warn "These metrics will be ignored in the report"
    end
    
    return missing_metrics
end

"""
    prepare_benchmark_results(raw_results::Dict{String, Any}, measures_dict::Dict{String, Any})

Prepare benchmark results for submission to Bencher.
Filters out any metrics that don't have corresponding measures.
"""
function prepare_benchmark_results(raw_results::Dict{String, Any}, measures_dict::Dict{String, Any})
    prepared_results = []
    
    for (metric_name, value) in raw_results
        if haskey(measures_dict, metric_name)
            measure = measures_dict[metric_name]
            push!(prepared_results, Dict(
                "measure" => measure["uuid"],
                "value" => value
            ))
        end
    end
    
    return prepared_results
end
