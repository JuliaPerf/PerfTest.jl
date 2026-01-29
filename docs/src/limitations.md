# Limitations and future work:

There are a couple of things to keep into consideration when using the package:

1. GPU testing is technically supported, but it requires more effort from the developer to set up since the automatic measurements apart from time elapsed do not apply to GPUs (as of now).
2. The automatic flop counting feature works exclusively for Julia native functions, it can not measure the flops in C calls given the limitations of the subjacent package [CountFlops.jl]


## Features to be expected in the next versions:

1. Easier access to performance suite results after execution
2. Simplification of the package structure, there will be an emphasis on making the package easy to extend for unfamiliarised developers
3. Access to performance counter values through LIKWID
4. Alternative regression testing against git commits instead of last execution for easier testing
