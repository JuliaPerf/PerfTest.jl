"""
"""
function rfc3339_formatter(dt::DateTime)
    return Dates.format(dt, dateformat"yyyy-mm-ddTHH:MM:SS.sssZ")
end

"""
""" 
function submitReport(report :: Dict, config :: Dict) # Ensure all resources exist (including metrics) project, branch, testbed, measures_dict = sync_metrics()

    project, branch, testbed = ensure_bencher_resources(config)

    # Convert to JSON string for the results array
    results_json = JSON.json(report)

    # Submit the report
    builder = RESTRequestBuilder()
    set_method!(builder, "POST")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project["uuid"])/reports")
    set_bearer_token!(builder, config["api_key"])
    set_body!(builder, Dict{String,Any}(
        "branch" => branch["uuid"],
        "testbed" => testbed["uuid"],
        "start_time" => rfc3339_formatter(Dates.now()),
        "end_time" => rfc3339_formatter(Dates.now()),
        "results" => [results_json],
        "settings" => Dict(
            "adapter" => "json"
        )
    ))

    request = build(builder)
    success, response, error = make_request(request)

    if success
        @info "Successfully submitted benchmark results"
        return response
    else
        @error "Failed to submit benchmark results: $error"
        return nothing
    end
end
