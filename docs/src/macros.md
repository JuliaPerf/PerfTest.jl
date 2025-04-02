```@meta
CurrentModule = PerfTest
```

# PerfTest macros quick reference

The following are the main macros used to define performance test suites. These shall be always used
inside a testset (see the [Test] package). Combining the different macros listed in this section gives
the full extent of the package features.

## Declaring test targets

```@docs
@perftest
```

## Declaring metrics

```@docs
@define_metric
@auxiliary_metric
```

## Declaring methodologies

```@docs
@perfcompare
@define_eff_memory_throughput
@roofline
```

## Structure and configuration

```@docs
@perftest_config
@on_perftest_exec
@on_perftest_ignore
@export_vars
```
