

threads_validation = defineMacroParams([
    # Of any type, so parseThreadsMacro reports an invalid one along with the arrangements it can be (see validateThreadsArgument)
    MacroParameter(Symbol(""),
                   Any,
                   mandatory= true)
])

# What the argument of @perftest_threads can be, named in its parse errors
THREADS_OPTIONS = "A thread arrangement is :single, :numa, :all, a tuple (#numas, #threads_per_numa) whose elements are " *
                  "positive integers or ratios of integers in (0, 1] (e.g. (1, 1//2)), or a list of them. " *
                  "A list of positive integers is a manual pinning to those thread ids (e.g. [1, 2])."

"""
Whether `x`, the argument of a @perftest_threads, is a literal, so its value is known when the recipe is transformed: a
number, a string, a quoted symbol (e.g. `:numa`), a ratio of integers (e.g. `1//2`), or a tuple or a list of them.
"""
isThreadsLiteral(x::Union{Number,AbstractString}) = true
isThreadsLiteral(x::QuoteNode) = x.value isa Symbol
isThreadsLiteral(x::Expr) = x.head in (:tuple, :vect) ? all(isThreadsLiteral, x.args) :
                            x.head === :call && length(x.args) == 3 && x.args[1] === :// && all(a -> a isa Integer, x.args[2:3])
isThreadsLiteral(x) = false

"""
Check `x`, the argument of a @perftest_threads, each reason it is invalid is reported with `report`. Returns whether it
is valid.
"""
function validateThreadsArgument(x, report::Function)::Bool
    if !isThreadsLiteral(x)
        report("`$x` is not a literal, the arrangement is read when the recipe is transformed so a variable or any other expression is not supported.")
        return false
    end
    # Only literals, see isThreadsLiteral, as the generated suite evaluates them
    value = try
        eval(x)
    catch e
        report("`$x` cannot be evaluated, $(sprint(showerror, e)).")
        return false
    end
    return Topology.validateArrangement(value, report)
end

"""
    This macro can be used to specify one or more thread pinning configurations for the performance test suite. Not calling this macro on the recipe leaves the threads unpinned.

    # Arguments
        A thread specification or a list of them. A thread specification can be:
        (#numas, #threads_per_numa) or a shortcut symbol like :single, :numa or :all
        Example:
            (1, 1) or :single   -> One thread on one numa node
            (1, 2)              -> Two threads on two numa nodes
            (1, 1//1) or :numa  -> All threads on one numa node
            (1, 1//2)           -> Half of the threads available for one numa node
            (2, 1)              -> One thread on each of two numa nodes 
            (1//1,1//1) or :all -> All posible threads on all numa nodes

        Alternatively a list of integers can be passed which will be interpreted as a manual pinning.

        The argument must be a literal, as it is read when the recipe is transformed: a variable or any other expression,
        as well as an invalid arrangement, is reported as a parse error.

        The arrangement is resolved on the machine that executes the suite, e.g. :numa takes the size of a NUMA domain of that machine.

        It takes priority over the thread setting of the configuration (general.numas and general.threads_per_numa) for
        the number of threads runperftests launches the suite with.

        [!] As of now, the pinning is not MPI aware, (this will come in PerfTest v1.2.4) in MPI cases use the manual pinning, with the list of integers.
        [!] This is a feature in development, more comprehensive features will be built over this later on (1.2.4).
"""
macro perftest_threads(anything)
    return :(begin end)
end