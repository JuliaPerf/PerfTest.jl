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


## [`PerfTest`](@ref) type and basic constructors
```@docs
PerfTest
```


## Convenience type aliases and constructors
#### Index
* [`CellArrays.CPUCellArray`](@ref)
* [`CellArrays.CuCellArray`](@ref)
* [`CellArrays.ROCCellArray`](@ref)

#### Documentation
```@autodocs
Modules = [PerfTest]
Order   = [:type]
Filter = t -> typeof(t) !== CellArray
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
