
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

function gpuPowerMeasure end
function formulaGetGPUEnergy end
function formulaGetGPUPower end
function cuda_devices end
function CUDAExtensionData end
function read_joule end

function is_loaded(ext::Symbol)
    return is_loaded(Val(ext))
end
is_loaded(ext::Val) = false

abstract type Mode end
struct MPIMode <: Mode end
struct NormalMode <: Mode end

mode = NormalMode