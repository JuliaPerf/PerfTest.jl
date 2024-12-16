
magnitude_prefixes = Dict(
    1e3 => "K",
    1e6 => "M",
    1e9 => "G",
    1    => "",
    1e-3=> "m",
    1e-6=> "µ",
    1e-9=> "n"
)

function magnitudeAdjust(value :: Number, unit :: String) :: Pair{Number, String}
    # Check for the adequate order of magnitude
    for (magnitude_order, prefix) in magnitude_prefixes
        if 1e-1 <= (value / magnitude_order) < 1e2
            return Pair(value / magnitude_order, prefix * unit)
        end
    end

    # Extremes beyond supported orders
    if value > 1
        return Pair(value / 1e9, "G" * unit)
    else
        return Pair(value * 1e9, "n" * unit)
    end
end

# Just in case a non numeric metric is passed to the function
function magnitudeAdjust(value :: Any, unit :: String) :: Pair{Number, String}
    return Pair(value, unit)
end


# Used to directly turn a result into a convenient magnitude order
function resultAdjust(result :: Metric_Result) :: Metric_Result
    newval,newunit = magnitudeAdjust(result.value, result.units)

    return Metric_Result(
        name = result.name,
        value = newval,
        units = newunit,
        auxiliary = result.auxiliary
    )
end
