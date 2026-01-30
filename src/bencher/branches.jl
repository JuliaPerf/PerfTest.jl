
"""
    get_current_git_branch()

Get the current git branch name from the repository.
"""
function get_current_git_branch()
    try
        # Check pwd and parent, they usually tend to be the repository roots
        try
            repo = LibGit2.GitRepo(".")
        catch e
            repo = LibGit2.GitRepo("..")
        end
        head = LibGit2.head(repo)
        branch_name = LibGit2.shortname(head)
        LibGit2.close(repo)
        return branch_name
    catch e
        @warn "Could not determine git branch: $e"
        return "main"  # Default to main if we can't determine the branch
    end
end

"""
    search_branch(project_uuid::String, branch_name::String)

Search for a branch by name in the project.
"""
function search_branch(project_uuid::String, branch_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "GET")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/branches")
    set_bearer_token!(builder, config["api_key"])
    add_query_param!(builder, "name", branch_name)
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success && !isempty(response)
        return response[1]  # Return the first matching branch
    end
    
    return nothing
end

"""
    create_branch(project_uuid::String, branch_name::String)

Create a new branch in the project.
"""
function create_branch(project_uuid::String, branch_name::String, config :: Dict)
    builder = RESTRequestBuilder()
    set_method!(builder, "POST")
    set_url!(builder, "$(config["api_url"])/v0/projects/$(project_uuid)/branches")
    set_bearer_token!(builder, config["api_key"])
    set_body!(builder, Dict{String,Any}(
        "name" => branch_name
    ))
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success
        return response
    else
        error("Failed to create branch: $error")
    end
end