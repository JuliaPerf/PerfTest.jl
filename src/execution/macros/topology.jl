

threads_validation = defineMacroParams([
    MacroParameter(Symbol(""),
                   ExtendedExpr,
                   validation_function= x -> Topology.validateArrangement(eval(x)),
                   mandatory= true)
])
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

        [!] As of now, the pinning is not MPI aware, (this will come in PerfTest v1.2.4) in MPI cases use the manual pinning, with the list of integers.
        [!] This is a feature in development, more comprehensive features will be built over this later on (1.2.4).
"""
macro perftest_threads(anything)
    return :(begin end)
end