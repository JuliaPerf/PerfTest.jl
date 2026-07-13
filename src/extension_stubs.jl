
function resolveAlias end
function likwidEventsRetrieve end
function likwidMetricsRetrieve end
function perfmon end
function LIKWIDExtensionData end
macro PRFT_perfmon end

# Function headers that are needed beforehand cause julia cant support calling them from an extension afaik.
function formulaGetFlop end
function formulaGetFlops end
function formulaGetBandwidth end
function formulaGetEnergy end
function formulaGetPower end
function formulaGetGPU end
function formulaGetMisses end

function is_loaded(ext::Symbol)
    return false
end

abstract type Mode end
struct MPIMode <: Mode end
struct NormalMode <: Mode end

mode = NormalMode