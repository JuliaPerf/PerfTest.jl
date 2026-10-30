# Limitations and future work:

There are a couple of things to keep into consideration when using the package:

1. GPU testing is technically supported, but it requires more effort from the developer to set up since the automatic measurements apart from time elapsed do not apply to GPUs (as of now).
2. Automatic flop counting is not supported (the `:autoflop` primitive is always 0), the flop count of a target has to be given explicitly, e.g. with `@roofline actual_flops = ...`.
3. LIKWID and GPU (CUDA/AMDGPU) energy/power measurements are repeated to match the actual number of samples `BenchmarkTools` took for the same test (median-aggregated, with the spread preserved as a standard-error-of-the-mean interval when `showvar=true` and at least 30 samples were taken — see `@regression`/`@perfcompare`'s `showvar` argument), so their cost scales with whatever `samples=`/`seconds=`/`evals=` the test uses — tune those explicitly on tests using these extensions if you don't want extension sampling to inherit `BenchmarkTools`' adaptive defaults.


## Features to be expected in the next versions:

1. Easier access to performance suite results after execution
2. Simplification of the package structure, there will be an emphasis on making the package easy to extend for unfamiliarised developers
3. Access to performance counter values through LIKWID
4. Alternative regression testing against git commits instead of last execution for easier testing
