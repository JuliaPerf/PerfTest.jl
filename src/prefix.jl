using Dates

### PREFIX FILLER
function perftestprefix(ctx :: Context)
    return quote
        using BenchmarkTools

        @show "AA"

        @show BenchmarkTools

        suite_name = $("$(basename(ctx.original_file_path))_PERFORMANCE")

        suite = BenchmarkGroup();
        l = suite;

        # CHECK BEGIN Check for previous performance test results to obtain a reference
        path = "./.perftest/$(suite_name).json"

        noref = true
        if isfile(path)
            noref = false
            reference = BenchmarkTools.load(path)
        else
            println("[!] No previous performance reference for this configuration has been found, measuring performance without evaluation.")
        end

    end
end
