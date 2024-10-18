
### PREFIX FILLER
function perftestprefix(ctx :: Context)::Expr
    return quote
        using Test;
        using BenchmarkTools;
        $(
            if roofline.autoflops
                quote using CountFlops; end
            else
                quote begin end end
            end
        )

        # __PERFTEST__.Test.eval(quote
        #      function record(ts::DefaultTestSet, t::Union{Fail,Error})
        #          push!(ts.results, t)
        #      end
        # end)

        suite_name = $("$(basename(ctx.original_file_path))_PERFORMANCE")

        # Used to save data about this test suite if needed
        path = "./$(PerfTest.save_folder)/$(suite_name).JLD2"
        if isdir("./$(PerfTest.save_folder)")
        else
            mkdir("./$(PerfTest.save_folder)")
        end

        nofile = true
        if isfile(path)
            nofile = false
            data = PerfTest.openDataFile(path)
        else
            data = PerfTest.Perftest_Datafile_Root(PerfTest.Perftest_Result[],
                                                    PerfTest.Dict{PerfTest.StrOrSym, Any}[])

            PerfTest.p_yellow("[!]")
            println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
        end

        l = BenchmarkGroup()

        # Methodology prefixes
        $(regressionPrefix(ctx))
        $(effMemThroughputPrefix(ctx))

        # Export tree, used to save values from the function evaluation that need to be reused in the testing phase
        export_tree = Dict()
    end
end
