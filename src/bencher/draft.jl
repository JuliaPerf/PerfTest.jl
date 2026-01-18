# Add these functions to bencher_api.jl

using TOML

"""
    get_git_remote_info()

Extract organization and repository name from git remote URL.
Returns a tuple (organization, repository) or (nothing, nothing) if unable to determine.
"""
function get_git_remote_info()
    try
        repo = LibGit2.GitRepo(".")
        
        # Try to get the remote URL (usually "origin")
        remote_name = "origin"
        if !LibGit2.isremote(repo, remote_name)
            # If origin doesn't exist, try to get the first available remote
            remotes = LibGit2.remotes(repo)
            if isempty(remotes)
                LibGit2.close(repo)
                return (nothing, nothing)
            end
            remote_name = first(remotes)
        end
        
        remote = LibGit2.get(LibGit2.GitRemote, repo, remote_name)
        remote_url = LibGit2.url(remote)
        LibGit2.close(repo)
        
        # Parse the URL to extract organization and repository
        return parse_git_url(remote_url)
    catch e
        @warn "Could not determine git remote info: $e"
        return (nothing, nothing)
    end
end

"""
    parse_git_url(url::String)

Parse a git URL to extract organization and repository name.
Supports both HTTPS and SSH formats:
- https://github.com/organization/repository.git
- git@github.com:organization/repository.git
- https://gitlab.com/organization/repository.git
- etc.
"""
function parse_git_url(url::String)
    # Remove trailing .git if present
    url = rstrip(url, ".git")
    
    # SSH format: git@domain:organization/repository
    ssh_match = match(r"git@[^:]+:([^/]+)/(.+)$", url)
    if !isnothing(ssh_match)
        return (String(ssh_match.captures[1]), String(ssh_match.captures[2]))
    end
    
    # HTTPS format: https://domain/organization/repository
    https_match = match(r"https?://[^/]+/([^/]+)/(.+)$", url)
    if !isnothing(https_match)
        return (String(https_match.captures[1]), String(https_match.captures[2]))
    end
    
    # If no match found
    return (nothing, nothing)
end

"""
    get_project_info_from_toml(filename::String="Project.toml")

Extract project information from Project.toml file.
Returns a Dict with project metadata.
"""
function get_project_info_from_toml(filename::String="Project.toml")
    if !isfile(filename)
        return Dict{String, Any}()
    end
    
    try
        return TOML.parsefile(filename)
    catch e
        @warn "Could not parse $filename: $e"
        return Dict{String, Any}()
    end
end

"""
    detect_organization_name()

Attempt to detect the organization name from various sources:
1. Git remote URL
2. Environment variables
3. Project.toml metadata
"""
function detect_organization_name()
    # Try git remote first
    org, _ = get_git_remote_info()
    if !isnothing(org)
        return org
    end
    
    # Try environment variables
    for env_var in ["GITHUB_REPOSITORY_OWNER", "GITLAB_USER_LOGIN", "CI_PROJECT_NAMESPACE", "BENCHER_ORGANIZATION"]
        if haskey(ENV, env_var)
            return ENV[env_var]
        end
    end
    
    # Try Project.toml authors field
    project_info = get_project_info_from_toml()
    if haskey(project_info, "authors") && !isempty(project_info["authors"])
        # Extract organization from first author if it looks like "Organization <email>"
        first_author = first(project_info["authors"])
        author_match = match(r"^([^<]+)", first_author)
        if !isnothing(author_match)
            return strip(String(author_match.captures[1]))
        end
    end
    
    return nothing
end

"""
    detect_repository_name()

Attempt to detect the repository/project name from various sources:
1. Project.toml name field
2. Git remote URL
3. Current directory name
"""
function detect_repository_name()
    # Try Project.toml first
    project_info = get_project_info_from_toml()
    if haskey(project_info, "name")
        return project_info["name"]
    end
    
    # Try git remote
    _, repo = get_git_remote_info()
    if !isnothing(repo)
        return repo
    end
    
    # Fall back to current directory name
    return basename(pwd())
end

"""
    query_organization(; search::Union{String, Nothing}=nothing)

Query organizations accessible to the current user.
If search is provided, filter organizations by name.
"""
function query_organization(; search::Union{String, Nothing}=nothing)
    builder = RESTRequestBuilder()
    set_method!(builder, "GET")
    set_url!(builder, "$(BENCHER_CONFIG.api_url)/v0/organizations")
    set_bearer_token!(builder, BENCHER_CONFIG.api_key)
    
    if !isnothing(search)
        add_query_param!(builder, "search", search)
    end
    
    request = build(builder)
    success, response, error = make_request(request)
    
    if success
        return response
    else
        @error "Failed to query organizations: $error"
        return []
    end
end

"""
    auto_detect_configuration()

Automatically detect and suggest configuration based on the current repository.
Returns a Dict with suggested configuration values.
"""
function auto_detect_configuration()
    config = Dict{String, Any}()
    
    # Detect repository name
    repo_name = detect_repository_name()
    config["project_name"] = repo_name
    @info "Detected repository name: $repo_name"
    
    # Detect organization
    org_name = detect_organization_name()
    if !isnothing(org_name)
        config["organization_hint"] = org_name
        @info "Detected organization hint: $org_name"
        
        # Query for matching organizations
        if !isempty(BENCHER_CONFIG.api_key)
            orgs = query_organization(search=org_name)
            if length(orgs) == 1
                config["organization"] = orgs[1]["slug"]
                @info "Found matching Bencher organization: $(orgs[1]["name"]) ($(orgs[1]["slug"]))"
            elseif length(orgs) > 1
                config["organization_options"] = [org["slug"] => org["name"] for org in orgs]
                @info "Found multiple matching organizations:"
                for org in orgs
                    @info "  - $(org["name"]) ($(org["slug"]))"
                end
            else
                @warn "No matching Bencher organizations found for: $org_name"
            end
        end
    else
        @warn "Could not detect organization name"
    end
    
    # Get git info for reference
    org, repo = get_git_remote_info()
    if !isnothing(org) && !isnothing(repo)
        config["git_organization"] = org
        config["git_repository"] = repo
        @info "Git remote: $org/$repo"
    end
    
    # Get current branch
    branch = get_current_git_branch()
    config["branch"] = branch
    @info "Current git branch: $branch"
    
    # Get testbed info
    testbed = get_testbed_name()
    config["testbed"] = testbed
    @info "Testbed name: $testbed"
    
    return config
end

"""
    interactive_setup()

Interactive setup helper that auto-detects configuration and prompts for confirmation.
"""
function interactive_setup()
    println("\n Bencher Configuration Setup")
    println("="^40)
    
    # Check if API key is set
    api_key = get(ENV, "BENCHER_API_KEY", "")
    if isempty(api_key)
        println("\n  No BENCHER_API_KEY environment variable found.")
        println("Please set your API key first:")
        println("  export BENCHER_API_KEY=your-api-key-here")
        return
    end
    
    # Configure with API key temporarily to query organizations
    BENCHER_CONFIG.api_key = api_key
    
    # Auto-detect configuration
    detected = auto_detect_configuration()
    
    println("\n Detected Configuration:")
    println("-"^40)
    
    # Show detected values
    project_name = get(detected, "project_name", "unknown")
    println("Project Name: $project_name")
    
    if haskey(detected, "organization")
        println("Organization: $(detected["organization"])")
    elseif haskey(detected, "organization_options")
        println("Organization Options:")
        for (slug, name) in detected["organization_options"]
            println("  - $name ($slug)")
        end
    else
        println("Organization: Not detected!")
    end
    
    println("Branch: $(detected["branch"])")
    println("Testbed: $(detected["testbed"])")
    
    # Generate configuration code
    org_slug = get(detected, "organization", "your-organization-slug")
    
    println("\n Suggested Configuration Code:")
    println("-"^40)
    println("""
    configure_bencher(
        api_key = ENV["BENCHER_API_KEY"],
        organization = "$org_slug",
        current_project = "$project_name"
    )
    """)
    
    println("\n You can now use ensure_bencher_resources() to create/verify all resources.")
    
    return detected
end

# Export the new functions
export get_git_remote_info, detect_organization_name, detect_repository_name
export query_organization, auto_detect_configuration, interactive_setup