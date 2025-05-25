
function scopeAssignment(input_expr::Expr, context::Context)::Expr
 
        @capture(input_expr, a_ = b_)

        return quote
            a = $b
        end
end

function scopeArg(input_expr::Expr, context::Context)::Expr

        # Get both functions and macros since macro args need to be interpolated as well
        @capture(input_expr, f_(args__)) || @capture(input_expr, @f_(args__))

        processed_args = [isa(arg, Symbol) ?
            :($(Expr(:$,arg))) :
            arg for arg in args]

        if @capture(f, _._)
            return Expr(:call, f, processed_args...)
        else
            return Expr(:call, Expr(:$,f), processed_args...)
        end
end

function argProcess(args :: Vector)::Vector
    newargs = []
    for arg in args
        if isa(arg, Symbol)
            push!(newargs, :($(Expr(:$,arg))))
        elseif arg.head == :tuple
            push!(newargs, Expr(:tuple, argProcess(arg.args)...))
        else
            push!(newargs, arg)
        end
    end
    return newargs
end

function scopeVecFArg(input_expr::Expr, context::Context)::Expr

        @capture(input_expr, f_.(args__))


        # Process symbols
        processed_args = argProcess(args)


        return Expr(:., f, Expr(:tuple, processed_args...))
end

function scopeDotInterpolation(input_expr::Expr, context::Context)::Expr
    # If inside a benchmark target, the left side of the dot is interpolated to prevent failure reaching values stored in local scopes

        @capture(input_expr, a_.b_)
        if (isa(a, Symbol))
            return :(
                $(Expr(:$,a)).$b
            )
        else
            return input_expr
        end
end
