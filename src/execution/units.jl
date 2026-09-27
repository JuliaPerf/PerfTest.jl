
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
#
# `showvar=true` is passed to every newMetricResult call below deliberately: this function
# rescales an *already-built* Metric_Result, it isn't making a fresh showvar decision. If `m`
# never carried a variance (the common case, since newMetricResult defaults to showvar=false),
# metricSampledValue(m) returns a bare value and showvar=true here has no effect. If `m` does
# carry one, that means whoever built it already opted in — this just carries that decision
# through the rescale rather than silently dropping it.
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
                value = metricSampledValue(m) / magnitude_order,
                auxiliary = m.auxiliary,
                magnitude_prefix=prefix,
                magnitude_mult=magnitude_order,
                showvar=true
            )
        end
    end

    # Extremes beyond supported orders
    if m.value > 1
        return newMetricResult(
                mode,
                name = m.name,
                units= m.units,
                value = metricSampledValue(m) / 1e9,
                auxiliary = m.auxiliary,
                magnitude_prefix="G",
                magnitude_mult=1e9,
                showvar=true
            )
    else
        return newMetricResult(
                mode,
                name = m.name,
                units= m.units,
                value = metricSampledValue(m) * 1e9,
                auxiliary = m.auxiliary,
                magnitude_prefix="n",
                magnitude_mult=1e-9,
                showvar=true
            )
    end
end

function absoluteMagnitude(m::Metric_Result)::Metric_Result
    if !(m.value isa Number)
        return m
    end
    return newMetricResult(
        mode,
        name = m.name,
        units= m.units,
        value = metricSampledValue(m) * m.magnitude_mult,
        auxiliary = m.auxiliary,
        magnitude_prefix="",
        magnitude_mult=1,
        showvar=true
    )
end
