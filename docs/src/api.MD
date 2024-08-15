```@meta
CurrentModule = PerfTest
```

# API reference

This is the official API reference of `PerfTest`. Note that it can also be queried interactively from the [Julia REPL] using the [help mode](https://docs.julialang.org/en/v1/stdlib/REPL/#Help-mode):
```julia-repl
julia> using PerfTest
julia>?
help?> PerfTest
```


## [`metrics`](@ref) type and basic constructors
```@docs
metrics
```


## [`regression`](@ref), [`suppress_output`](@ref), [`save_folder`](@ref)
```@docs
regression
suppress_output
save_folder
```


## Convenience type aliases and constructors
#### Index
* [`PerfTest.retvalExpressionParser`](@ref)
* [`PerfTest.metaGet`](@ref)

#### Documentation
```@autodocs
Modules = [PerfTest]
Order   = [:type]
Filter = t -> typeof(t) !== Array
```


## Functions -- additional to standard `AbstractArray` functionality
#### Index
```@index
Order = [:function]
```
#### Documentation
```@autodocs
Modules = [PerfTest]
Order   = [:function]
```
