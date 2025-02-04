
struct MetricMeasure{V}
    name::String
    units:: String
    value:: V
end

function newLocalScope(name::String, body::Expr)::Expr
    return quote
        _PRFT_LOCAL[$name] = Dict{PerfTest.StrOrSym,Any}()
        _PRFT_LOCAL[$name][:additional] = _PRFT_LOCAL[:additional][$name]
        _PRFT_LOCAL[$name][:suite] = _PRFT_LOCAL[:suite][$name]
        _PRFT_LOCAL[$name][:depth] = _PRFT_LOCAL[:depth]
        let _PRFT_LOCAL = _PRFT_LOCAL[$name]
            push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord($name))
            _PRFT_LOCAL[:primitives] = Dict{Symbol,Any}()
            _PRFT_LOCAL[:metrics] = Dict{Symbol,Metric_Result}()
            _PRFT_LOCAL[:auxiliar] = Dict{Symbol,Metric_Result}()
            $body
            pop!(_PRFT_LOCAL[:depth])
        end
    end
end


function newLocalScopeFor(name::String, iterator :: ExtendedExpr, body::Expr)::Expr
    return quote
        _PRFT_LOCAL[$name*"_"*string($iterator)] = Dict{PerfTest.StrOrSym,Any}()
        _PRFT_LOCAL[$name * "_" * string($iterator)][:additional] = _PRFT_LOCAL[:additional][$name* "_" * string($iterator)]
        _PRFT_LOCAL[$name * "_" * string($iterator)][:suite] = _PRFT_LOCAL[:suite][$name* "_" * string($iterator)]
        _PRFT_LOCAL[$name * "_" * string($iterator)][:depth] = _PRFT_LOCAL[:depth]
        let _PRFT_LOCAL = _PRFT_LOCAL[$name * "_" * string($iterator)]
            push!(_PRFT_LOCAL[:depth], PerfTest.DepthRecord($name * "_" * string($iterator)))
            _PRFT_LOCAL[:primitives] = Dict{Symbol,Any}()
            _PRFT_LOCAL[:metrics] = Dict{Symbol,Metric_Result}()
            _PRFT_LOCAL[:auxiliar] = Dict{Symbol,Metric_Result}()
            $body
            pop!(_PRFT_LOCAL[:depth])
        end
    end
end

# EXCEPTIONAL FUNCTION SHALL BE MOVED TO EXECUTION SOONER OR LATER - NOTE
function buildPrimitiveMetrics!(::Type{NormalMode}, _PRFT_LOCAL::Dict, _PRFT_GLOBAL::Dict{Symbol,Any})
        _PRFT_LOCAL[:primitives][:median_time] = median(_PRFT_LOCAL[:suite]).time / 1e9
        _PRFT_LOCAL[:primitives][:min_time] = minimum(_PRFT_LOCAL[:suite]).time / 1e9
        _PRFT_LOCAL[:primitives][:autoflop] = _PRFT_LOCAL[:additional][:autoflop]
        _PRFT_LOCAL[:primitives][:ret_value] = _PRFT_LOCAL[:additional][:ret_value]
        _PRFT_LOCAL[:primitives][:printed_output] = _PRFT_LOCAL[:additional][:printed_output]
        _PRFT_LOCAL[:primitives][:iterator] = _PRFT_LOCAL[:additional][:iterator]
end


