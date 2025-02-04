

function captureMethodologyInfo(id::Symbol, methodologies::Vector{Vector{MethodologyParameters}})::Union{MethodologyParameters,Nothing}
    # Initialize empty structures for merging parameters
    name :: Union{Nothing, AbstractString} = nothing
    merged_params = Dict{Symbol, Any}()
    override_found = false

    # Iterate through the methodologies from the end of the vector (backwards)
    for methodology_group in reverse(methodologies)
        for methodology in methodology_group
            if methodology.id == id
                # Set or update the name if it's empty
                if name isa Nothing
                    name = methodology.name
                end

                for (k, v) in methodology.params
                    if !haskey(merged_params, k)
                        merged_params[k] = v
                    end
                end

                # Mark that we found an entry with `override = true`
                override_found = methodology.override

                # If `override` is true, stop searching for more parameters
                if methodology.override
                    break
                end
            end
        end
        if override_found
            break
        end
    end

    if name isa Nothing
        return nothing
    end

    # Construct and return the resulting `MethodologyParameters`
    return MethodologyParameters(id=id, name=name, override=override_found, params=merged_params)
end
