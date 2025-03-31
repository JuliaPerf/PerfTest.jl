# Macro validation
function defineMacroParams(params :: AbstractArray{MacroParameter})
    return Dict{Symbol, MacroParameter}([(p.name, p) for p in params])
end

function validateMacro(macro_param :: Dict{Symbol, MacroParameter})

    function _validationFunction(macro_expr::ExtendedExpr, context::Context)::Union{Nothing,Dict{Symbol,Any}}

        @capture(macro_expr, @m_ args__)


        mandatory = sum([a.second.mandatory for a in macro_param])
        _all = length(macro_param)
        # Invalid parameter numbers
        if !(mandatory <= length(args) <= _all)
            throwParseError!("Invalid number of arguments in $m, expected from $mandatory to $_all, got $(length(args))",context)
            return nothing
        end

        @show args, mandatory

        # 0 Arg macro
        if length(macro_param) == 0
            return nothing
        end

        # Parameter appearance check-list
        checklist = Set{Symbol}()

        parsed_params = Dict{Symbol,Any}()

        for arg in args[1:(end-1)]
            @matchast arg quote
                # Assignment
                ($a = $b) => begin
                    if haskey(macro_param, a)
                        param_info = macro_param[a]
                        if param_info.type >: typeof(b)
                            if param_info.param_validation_function(b)
                                parsed_params[a] = b
                                push!(checklist, a)
                            else
                                # Invalid parameter value
                                throwParseError!("Invalid parameter value for $a in macro $m", context)
                            end
                        else
                            # Invalid parameter type
                            throwParseError!("Invalid parameter type $(typeof(b)) for $a in macro $m, expected $(param_info.type)",context)
                        end
                    else
                        # Invalid parameter name
                        throwParseError!("Invalid parameter name $a for macro $m",context)
                    end
                end
                # No assigment
                _ => throwParseError!("Malformed macro $m",context)
            end
        end

        # Last argument (unnamed, usually a block)
        param_info = macro_param[Symbol("")]
        param = args[end]
        @matchast param quote
	          ($a = $b) => (throwParseError!("Last parameter cannot be a keyword parameter on macro $m",context); return nothing)
            $_ => nothing
        end
        if typeof(param) <: param_info.type
            if param_info.param_validation_function(param)
                parsed_params[Symbol("")] = param
                push!(checklist, Symbol(""))
            else
                push!(checklist, Symbol(""))
                throwParseError!("Invalid expression in macro $m",context)
            end
        else
            push!(checklist, Symbol(""))
            # Invalid parameter type
            throwParseError!("Invalid parameter type in macro $m, expected $(param_info.type) got $(typeof(param))",context)
        end

        # Check all mandatory parameters are present
        if !all([param.first in checklist || !param.second.mandatory for param in macro_param])
            throwParseError!("Missing mandatory parameters in macro $m",context)
            return nothing
        end

        # Manifest defaults on absent parameters
        for param in macro_param
            if !(param.first in checklist) && param.second.has_default
                parsed_params[param.first] = param.second.default_value
            end
        end

        return parsed_params
    end
end


function validateBlocklessMacro(macro_param::Dict{Symbol,MacroParameter})

    function _validationFunction(macro_expr::ExtendedExpr, context::Context)::Union{Nothing,Dict{Symbol,Any}}

        @capture(macro_expr, @m_ args__)


        mandatory = sum([a.second.mandatory for a in macro_param])
        _all = length(macro_param)
        # Invalid parameter numbers
        if !(mandatory <= length(args) <= _all)
            throwParseError!("Invalid number of arguments in $m, expected from $mandatory to $_all, got $(length(args))",context)
            return nothing
        end

        # 0 Arg macro
        if length(macro_param) == 0
            return nothing
        end

        # Parameter appearance check-list
        checklist = Set{Symbol}()

        parsed_params = Dict{Symbol,Any}()

        for arg in args[1:end]
            @matchast arg quote
                # Assignment
                ($a = $b) => begin
                    if haskey(macro_param, a)
                        param_info = macro_param[a]
                        if param_info.type >: typeof(b)
                            if param_info.param_validation_function(b)
                                parsed_params[a] = b
                                push!(checklist, a)
                            else
                                # Invalid parameter value
                                throwParseError!("Invalid parameter value for $a in macro $m", context)
                            end
                        else
                            # Invalid parameter type
                            throwParseError!("Invalid parameter type $(typeof(b)) for $a in macro $m, expected $(param_info.type)",context)
                        end
                    else
                        # Invalid parameter name
                        throwParseError!("Invalid parameter name $a for macro $m",context)
                    end
                end
                # No assigment
                _ => throwParseError!("Malformed macro $m",context)
            end
        end

        # Check all mandatory parameters are present
        if !all([param.first in checklist || !param.second.mandatory for param in macro_param])
            throwParseError!("Missing mandatory parameters in macro $m",context)
            return nothing
        end

        # Manifest defaults on absent parameters
        for param in macro_param
            if !(param.first in checklist) && param.second.has_default
                parsed_params[param.first] = param.second.default_value
            end
        end

        return parsed_params
    end
end
