include("structs.jl")

### SUFFIX FILLER
function perftextsuffix(context :: Context)
    return quote
        suite = l

        if noref
            BenchmarkTools.save("./.perftest/$(suite_name).json", suite)
            print("[!] A perfomance reference has been saved.")
        else
            judgement = judge(median(suite),median(reference[1]))

            depth = PerfTests.DepthRecord[]
            @show typeof(depth)

            # Tolerance
            tolerance = PerfTests.FloatRange(0.7, 1.1, 1.0)

            # Test suite
            tt = Dict()
            try
	              $(context.test_tree_expr_builder[1][1])
            catch
                @warn "One or more performance tests have failed"
            end

            print("[!] $($(context.original_file_path)) Performance tests have been finished")
        end
    end
end
