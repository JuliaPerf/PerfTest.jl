

threads_validation = defineMacroParams([
    MacroParameter(Symbol(""),
                   ExtendedExpr,
                   validation_function= x -> Topology.validateArrangement(eval(x)),
                   mandatory= true)
])
"""
    This macro can be used to specify one or more thread pinning configurations for the performance test suite. By default one single thread is used.

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
"""
macro perftest_threads(anything)
    return :(begin end)
end