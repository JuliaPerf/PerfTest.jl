
macro perftest(anything)
    return esc(anything)
end

# Perftest_config macro, used to set customised configuration
macro perftest_config(expr)
    # It deletes the contents and does nothing since this macro wont
    # be evaluated during performance testing but during functional testing
    # The contents are used by parsing them during the test translation
    return begin end
end

macro on_perftest_exec(anything)
    return :(
        begin end
    )
end

macro on_perftest_ignore(anything)
    return esc(anything)
end

macro define_metric(expr)
    return :(
        begin end
    )
end

macro define_eff_memory_throughput(expr)
    return :(
        begin end
    )
end

macro metric_def_visible(expr)
    return expr
end

# TODO
macro define_reference(expr)
    return :(
        begin end
    )
end

macro roofline(opint_formula, cpu_peak=nothing, membw_peak=nothing)
    return :(
        begin end
    )
end

macro auxiliary_metric(formula, name, units)
    return :(
        begin end
    )
end
