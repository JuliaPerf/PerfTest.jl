
magnitude_prefixes = Dict(
    1e3 => "K",
    1e6 => "M",
    1e9 => "G",
    1    => "",
    1e-3=> "m",
    1e-6=> "µ",
    1e-9=> "n"
)

# Used to directly turn a result into a convenient magnitude order
function magnitudeAdjust(m::Metric_Result)::Metric_Result

    # Check for valid number, do nothing if not
    if !(m.value isa Number)
        return m
    end

    # Check for the adequate order of magnitude
    for (magnitude_order, prefix) in magnitude_prefixes
        if 1e-1 <= (m.value / magnitude_order) < 1e2
            return newMetricResult(
                mode,
                name = m.name,
                units= m.units,
                value = m.value / magnitude_order,
                auxiliary = m.auxiliary,
                magnitude_prefix=prefix,
                magnitude_mult=magnitude_order
            )
        end
    end

    # Extremes beyond supported orders
    if m.value > 1
        return newMetricResult(
                mode,
                name = m.name,
                units= m.units,
                value = m.value / 1e9,
                auxiliary = m.auxiliary,
                magnitude_prefix="G",
                magnitude_mult=1e9
            )
    else
        return newMetricResult(
                mode,
                name = m.name,
                units= m.units,
                value = m.value * 1e9,
                auxiliary = m.auxiliary,
                magnitude_prefix="n",
                magnitude_mult=1e-9
            )
    end
end


