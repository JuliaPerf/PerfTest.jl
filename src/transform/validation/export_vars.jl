
function export_vars_validation(macro_expr::ExtendedExpr, context::Context) :: Set{Symbol}

    @capture(macro_expr, @m_ args__)

    # Has to be used inside a testset
    if length(context._local.depth_record) < 1
        throwParseError!("Illegal call of @export_vars, it must be inside a testset, outside it is not needed since the scope is global", context)
    end

    parsed_params = Set{Symbol}()
    for arg in args
        if arg isa Symbol
            push!(parsed_params, arg)
        else
            throwParseError!("Invalid parameter \"$arg\" on @export_vars, it must be a Symbol", context)
        end
    end

    return parsed_params
end
