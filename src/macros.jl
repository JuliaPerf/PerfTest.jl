
macro perftest(anything)
    return esc(anything)
end

macro perftest_config(anything)
    return :(
        begin end
    )
end

macro on_perftest_exec(anything)
    return :(
        begin end
    )
end

macro on_perftest_ignore(anything)
    return esc(anything)
end

# TODO
macro define_metric(expr)
    return :(
        begin end
    )
end

macro define_eff_memory_throughput()
    return :(
        begin end
    )
end

# TODO
macro define_reference(expr)
    return :(
        begin end
    )
end
