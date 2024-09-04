

# Basic example: time regression

Given a very simple function, which can be replaced by any other the user might want, we will build a time regression performance test suite.

```julia
function testfun(a :: Int)
    c = 1

    for i in 1:a
        c = c + (i ^ 2) / c
    end

    return c
end
```

The source file for the test suite would then be:

```julia
using PerfTest

@testset "Test unit" for i in [10000000,20000000,30000000]
    x = @perftest testfun(10)
end
```

This source specifies that the function shall be tested for the 3 different values on the test loop. The methodology used is time regression, this methodology will compare the median time attained with an historical reference and fail if outside the default tolerance interval.
