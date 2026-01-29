module BencherREST

    using LibGit2
    using HTTP
    using JSON
    using Dates
    import PerfTest
    import ..Metric_Result
    import ..Metric_Test
    import ..Methodology_Result
    import ..Test_Result
    import ..Perftest_Datafile_Root

    include("rest_queries.jl")
    include("projects.jl")
    include("branches.jl")
    include("testbeds.jl")
    include("metrics.jl")
    include("benchmarks.jl")

    """
        TODO flatten_test_hierarchy(results::Dict{String, Union{Dict, Test_Result}}, prefix::String="") -> Dict{String, Test_Result}

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
                    flattened[current_path] = Dict()
                    flattened[current_path][methodology.name] = methodology
                    flattened[current_path][methodology.name] = methodology
                end
                # TODO
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
        ensure_bencher_resources()

    Ensure that the current project, branch, and testbed exist in Bencher.
    Returns a tuple of (project, branch, testbed) with their respective information.
    """
    function ensure_bencher_resources(config :: Dict)
        # Check configuration
        if config["api_key"] == ""
            error("Bencher API key not configured.")
        end
        
        if config["organization"] == ""
            error("Bencher organization not configured.")
        end
        
        if config["project_name"] == ""
            error("Current project not configured.")
        end
        
        # Ensure project exists
        project_name = config["project_name"]
        @info "Checking for project: $project_name"
        
        project = search_project(project_name, config)
        if isnothing(project)
            @info "Project not found, creating: $project_name"
            project = create_project(project_name, config)
            @info "Created project: $(project["name"]) ($(project["uuid"]))"
        else
            @info "Found project: $(project["name"]) ($(project["uuid"]))"
        end
        
        project_uuid = project["uuid"]
        
        # Ensure branch exists
        branch_name = get_current_git_branch()
        @info "Checking for branch: $branch_name"
        
        branch = search_branch(project_uuid, branch_name, config)
        if isnothing(branch)
            @info "Branch not found, creating: $branch_name"
            branch = create_branch(project_uuid, branch_name, config)
            @info "Created branch: $(branch["name"]) ($(branch["uuid"]))"
        else
            @info "Found branch: $(branch["name"]) ($(branch["uuid"]))"
        end
        
        # Ensure testbed exists
        testbed_name = get_testbed_name()
        @info "Checking for testbed: $testbed_name"
        
        testbed = search_testbed(project_uuid, testbed_name, config)
        if isnothing(testbed)
            @info "Testbed not found, creating: $testbed_name"
            testbed = create_testbed(project_uuid, testbed_name, config)
            @info "Created testbed: $(testbed["name"]) ($(testbed["uuid"]))"
        else
            @info "Found testbed: $(testbed["name"]) ($(testbed["uuid"]))"
        end
        
        return (project, branch, testbed)
    end

    """
    
    """
    function exportSuiteToBencher(datafile :: Perftest_Datafile_Root, config :: Dict)
        # New report of benchmarks
        report_benchmarks = Dict()

        # Detect or create environment (org, project, branch, testbed)
        project, branch, testbed = ensure_bencher_resources(config)

        # Flatten data results
        results = processTestHierarchy(datafile.results[end].perftests)

        online_measures = get_all_measures(project["uuid"], config)
        # Create report
        # Export metrics and benchmarks        
        for (benchmark_name, result) in results
            for (methodology_name, methodology) in result
                # Regression methodology
                if methodology_name == "Performance Regression Testing"
                    metrics = Dict{String, Dict}()
                    for (key, pair) in methodology.custom_elements
                        metric, test = pair
                        # Publish metric if missing
                        if !haskey(online_measures, metric.name)
                            create_measure(project["uuid"], metric ,config) 
                        end

                        # Get metric uuid
                        m_uuid = search_measure(project["uuid"], metric.name, config)["uuid"]
                        metrics[m_uuid] = Dict()
                        metrics[m_uuid]["value"] = metric.value
                        metrics[m_uuid]["lower_value"] = test.threshold_min_percent * test.reference
                        if test.threshold_max_percent isa Nothing
                        else
                            metrics[m_uuid]["higher_value"] = test.threshold_max_percent * test.reference
                        end
                    end
                    # Aggregate benchmark results
                    report_benchmarks[benchmark_name] = metrics
                end
            end
        end

        # Publish benchmark_results
        submitReport(report_benchmarks, config)
    end



    # Export additional functions
    export get_package_metrics
    export configure_bencher, ensure_bencher_resources, exportSuiteToBencher
end