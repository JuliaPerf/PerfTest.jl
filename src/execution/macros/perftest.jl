
perftest_validation = defineMacroParams([
    MacroParameter(:samples,
                   Int),
    MacroParameter(:setup,
                   ExtendedExpr),    
    MacroParameter(:teardown,
                   ExtendedExpr),
    MacroParameter(:seconds,
                   Int),
    MacroParameter(:evals,
                   Int),
    MacroParameter(:gctrial,
                   Bool),    
    MacroParameter(:gcsample,
                   Bool),
    MacroParameter(:time_tolerance,
                   Number),
    MacroParameter(Symbol(""),
                   ExtendedExpr,
                   true)
])
"""
This macro is used to signal that the wrapped expression is a performance test target, and therefore its performance will be sampled and then evaluated following the current suite configuration.

If the macro is evaluated it does not modify the target at all. The effects of the macro only show when the script is transformed into a performance testing suite.

This macro is sensitive to context since other adjacent macros can change how the target will be evaluated.
        
`julia
@perftest expression [parameters...]
`

Run a performance test on a given target expression.

# Basic usage

The simplest usage is to place `@perftest` in front of the expression you want to test:

`
julia> @perftest sin(1)
`

# Additional parameters

You can pass the following keyword arguments to configure the execution process:

- **`setup`**: An expression that is run once per sample before the benchmarked expression. The `setup` expression is run once per sample, and is not included in the timing results. Note that each sample can require multiple evaluations.

- **`teardown`**: An expression that is run once per sample after the benchmarked expression.

- **`samples`**: The number of samples to take. Execution will end if this many samples have been collected. Defaults to `10000`.

- **`seconds`**: The number of seconds budgeted for the benchmarking process. The trial will terminate if this time is exceeded (regardless of samples), but at least one sample will always be taken. In practice, actual runtime can overshoot the budget by the duration of a sample.

- **`evals`**: The number of evaluations per sample. For best results, this should be kept consistent between trials. A good guess for this value can be automatically set on a benchmark via `tune!`, but using `tune!` can be less consistent than setting `evals` manually (which bypasses tuning).

- **`gctrial`**: If `true`, run `gc()` before executing this benchmark's trial. Defaults to `true`.

- **`gcsample`**: If `true`, run `gc()` before each sample. Defaults to `false`.

- **`time_tolerance`**: The noise tolerance for the benchmark's time estimate, as a percentage. This is utilized after benchmark execution, when analyzing results. Defaults to `0.05`.

# Examples

## Basic performance test

`
julia> @perftest sin(1)
`

## With setup and teardown

`
 @perftest sort!(data) setup=(data=rand(100)) teardown=(data=nothing)
`

## With custom parameters

`
# Run with a 3-second time budget
 @perftest sin(x) setup=(x=rand()) seconds=3

# Limit to 100 samples with 10 evaluations each
 @perftest myfunction($data) samples=100 evals=10

# Disable garbage collection before each sample
 @perftest allocating_function() gcsample=false gctrial=false
`

# See Also

- [BenchmarkTools.jl Documentation](https://juliaci.github.io/BenchmarkTools.jl/dev/) for more details on the underlying `@benchmark` macro and its parameters.
"""
macro perftest(anything)
    return esc(anything)
end
