
"""
    search_project(project_name::String)

Search for a project by name in the organization.
"""
function search_project(project_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "GET")
    set_url!(builder, "$(config["api_url"])/v0/organizations/$(config["organization"])/projects")
    set_bearer_token!(builder, config["api_key"])
    add_query_param!(builder, "name", project_name)
    
    request = build(builder)
    success, response, error = make_request(request)

    if success && !isempty(response)
        return response[1]  # Return the first matching project
    end
    
    return nothing
end

"""
    create_project(project_name::String)

Create a new project in the organization.
"""
function create_project(project_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "POST")
    set_url!(builder, "$(config["api_url"])/v0/organizations/$(config["organization"])/projects")
    set_bearer_token!(builder, config["api_key"])
    set_body!(builder, Dict{String,Any}(
        "name" => project_name,
        "visibility" => "public"
    ))
    
    request = build(builder)
    success, response,_error = make_request(request)
    
    if success
        return response
    else
        @error "Failed to create project: " * _error
    end
end


