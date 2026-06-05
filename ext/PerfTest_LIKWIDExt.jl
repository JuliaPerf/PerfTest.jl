module PerfTest_LIKWIDExt

using LIKWID
using PerfTest

if LIKWID.isavailable()
    @info "LIKWID is available. LIKWID-based benchmarks will be possible in the test suites."
else
    @warn "LIKWID is not available. LIKWID-based benchmarks will not be generated/executed."
end


end