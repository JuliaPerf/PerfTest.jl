# Each migration: old_dict -> new_dict, bumping version to `version`.
const MIGRATIONS = Tuple{NTuple{3,Int}, Function}[]

register_migration!(version::NTuple{3,Int}, f::Function) =
    push!(MIGRATIONS, (version, f))

function apply_migrations(root::AbstractDict)
    stored = Tuple(root[VERSION_KEY])
    # Sort by version ascending, just in case of insertion order issues.
    sorted = sort(MIGRATIONS; by = first)
    for (v, f) in sorted
        if v > stored
            root = f(root)
            root[VERSION_KEY] = v
            stored = v
        end
    end
    if stored > CURRENT_VERSION
        @warn "PerfTest-Deserialization: the version of perftest that wrote the test results v$(stored) is newer than the current one v$(CURRENT_VERSION), this could lead to undefined behaviour."
    end
    if stored != CURRENT_VERSION
        root[VERSION_KEY] = CURRENT_VERSION
    end
    return root
end

# Registered migrations start from version 2.2
