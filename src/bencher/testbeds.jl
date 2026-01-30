
"""
    get_testbed_name()

Get the testbed name based on hostname and architecture.
"""
function get_testbed_name()
    hostname = gethostname()
    arch = String(Sys.ARCH)
    return "$(hostname)_$(arch)"
end


"""
    search_testbed(project_uuid::String, testbed_name::String)

Search for a testbed by name in the project.
"""
function search_testbed(project_uuid::String, testbed_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "GET")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/testbeds")
    set_bearer_token!(builder, config["api_key"])
    add_query_param!(builder, "name", testbed_name)
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success && !isempty(response)
        return response[1]  # Return the first matching testbed
    end
    
    return nothing
end

"""
    create_testbed(project_uuid::String, testbed_name::String)

Create a new testbed in the project.
"""
function create_testbed(project_uuid::String, testbed_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "POST")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/testbeds")
    set_bearer_token!(builder, config["api_key"])
    set_body!(builder, Dict{String, Any}(
        "name" => testbed_name
    ))
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success
        return response
    else
        error("Failed to create testbed: $error")
    end
end
