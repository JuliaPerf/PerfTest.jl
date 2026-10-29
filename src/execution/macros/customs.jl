
define_metric_validation = defineMacroParams([
    MacroParameter(
        :name,
        String,
        true
    ),
    MacroParameter(
        :units,
        String,
        true
    ),
    # Symbol that identifies the metric, Symbol(name) when absent, see metricSymbol
    MacroParameter(
        :symbol,
        metricID()
    ),
    MacroParameter(
        Symbol(""),
        ExtendedExpr,
        true
    )
])

"""
This macro is used to define a new custom metric. The metric result can be used subsequently by other macros.

# Arguments
 - `name` : the name of the metric for identification purposes.
 - `units` : the unit space that the metric values will be in.
 - `symbol` : (optional) the symbol other formulas and macros (e.g `@regression metrics=...`) use to refer to the metric, a Symbol or a String. Defaults to the name as a symbol (name="example" -> :example).
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally some special symbols are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable to it. NOTE: If there is the need of referring to a variable on a formula block, it first needs to be exported using the macro @export_vars, otherwise an error will occur.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: not supported, automatic flop counting is outdated (it is always 0), a formula that uses it is reported as a parse error. Write the flop count of the target explicitly instead.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.
 -  Any symbol representing a custom metric or benchmark, its `symbol` if given, otherwise its name as a symbol (e.g metric with symbol=:ex -> :ex, metric with name="example" and no symbol -> :example)

# Example:

    @define_metric name="Effective bandwidth" units="GB/s" symbol=:bw begin
        1e-9 * 1000 / :median_time
    end
    @define_metric name="Bandwidth per core" units="GB/s" begin
        :bw / 8
    end
    @regression metrics=:bw
"""
macro define_metric(args...)
    return :(
        begin end
    )
end


define_test_metric_validation = defineMacroParams([
    MacroParameter(
        :name,
        String,
        true
    ),
    MacroParameter(
        :units,
        String,
        true
    ),
    MacroParameter(
        :reference,
        ExtendedExpr,
        true
    ),
    MacroParameter( # By default lower than threshold is considered as a failure
        :low_is_bad,
        Bool,
        true,
        false
    ),
    MacroParameter(
        Symbol(""),
        ExtendedExpr,
        true
    )
])

macro define_test_metric(args...)
    return :(begin end)
end

# Same parameters
auxiliary_metric_validation = define_metric_validation
"""
  Defines a custom metric for informational purposes that will not be used for testing but will be printed as output. The metric cannot be used by other macros.

# Arguments
 - `name` : the name of the metric for identification purposes.
 - `units` : the unit space that the metric values will be in.
 - `symbol` : (optional) the symbol that identifies the metric, a Symbol or a String. Defaults to the name as a symbol (name="example" -> :example).
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally some special symbols are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable to it.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: not supported, automatic flop counting is outdated (it is always 0), a formula that uses it is reported as a parse error. Write the flop count of the target explicitly instead.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.
 -  Any symbol representing a custom metric or benchmark, its `symbol` if given, otherwise its name as a symbol (e.g metric with symbol=:ex -> :ex, metric with name="example" and no symbol -> :example)
"""
macro auxiliary_metric(formula, name, units)
    return :(
        begin end
    )
end


define_eff_memory_throughput_validation = defineMacroParams([
    MacroParameter(:ratio,
                   Union{ExtendedExpr, Number},
                   #Validation filters illegal numbers but will not check expressions
                   (x) -> x isa ExtendedExpr ? true : (0.0 <= x <= 1.0),
    ),
    MacroParameter(
        :mem_benchmark,
        metricID(),
        (x) -> metricID(x) in [:MEM_STREAM_COPY, :MEM_STREAM_ADD, :MEM_BENCH_STRIAD, :MEM_BENCH_SDAXPY],
        :MEM_STREAM_COPY, #default
    ),
    MacroParameter(
        :custom_benchmark,
        Symbol,),
    MacroParameter(Symbol(""),
                   ExtendedExpr,
                   true)
])
"""

`@define_eff_memory_throughput [kwargs...] begin {formula block} end`

`@def_mem_thr [kwargs...] begin {formula block} end`

This macro is used to define the memory bandwidth of a target in order to execute the effective memory thorughput methodology.

# Arguments
 - formula block : an expression that returns a single value, which would be the metric value. The formula can have any julia expression inside and additionally special symbols listed below are supported. The formula may be evaluated several times, so its applied to every target in every test set or just once, if the formula is defined inside a test set, which makes it only applicable on it and onto children testset.
 - ratio : the allowed minimum percentage over the maximum attainable that is allowed to pass the test, it can be a number or a Julia expression that evaluates to a number
 - benchmark : which bandwidth kernel benchmark to use (e.g :MEM_STREAM_COPY for transfer operation, :MEM_BENCH_STRIAD (Shoenauer triad) for computing operations), :MEM_BENCH_SDAXPY (Shoenauer Daxpy) useful when not sure if copy on write is happening)
 - custom_benchmark : if a previously defined benchmark name is passed, the methodology will use it as the maximum bandwidth reference.

# Special symbols:
 - `:median_time` : will be substituted by the median time the target took to execute in the benchmark.
 - `:minimum_time`: will be substituted by the minimum time the target took to execute in the benchmark.
 - `:ret_value` : will be substituted by the return value of the target.
 - `:autoflop`: not supported, automatic flop counting is outdated (it is always 0), a formula that uses it is reported as a parse error. Write the flop count of the target explicitly instead.
 - `:printed_output` : will be substituted by the standard output stream of the target.
 - `:iterator` : will be substituted by the current iterator value in a loop test set.
 -  Any symbol representing a custom metric or benchmark, its `symbol` if given, otherwise its name as a symbol (e.g metric with symbol=:ex -> :ex, metric with name="example" and no symbol -> :example)

# Example:

The following definition assumes that each execution of the target expression involves transacting 1000 bytes. Therefore the bandwith is 1000 / execution time.

    @define_eff_memory_throughput begin
          1000 / :median_time
    end

"""
macro define_eff_memory_throughput(args...)
    return :(
        begin end
    )
end
var"@def_eff_mem" = var"@define_eff_memory_throughput"


"""
@export_vars vars...

Exports the specified symbols --along with the values they hold at the moment of the calling-- to the scope of metric definitions. In order to use any variable on the definition of a metric such variable needs to be exported with this macro.
"""
macro export_vars(symbols...)
    return :(
        begin end
    )
end


# Same parameters
define_benchmark_validation = define_metric_validation
"""
    Defines a customized reference to compare against. Must be always defined inside a testset.

# Arguments
 - name : (string) an identifier for the custom benchmark, methodologies that use it will refer to it using this name as a symbol, unless `symbol` is given.
 - units: (string) units of the reference value.
 - symbol: (optional, symbol or string) the symbol formulas and methodologies (e.g `custom_benchmark=...`) use to refer to the benchmark. Defaults to the name as a symbol.
 - formula: an expression to calculate the reference value.
"""
macro define_benchmark(args...)
    return :(
        begin end
    )
end
