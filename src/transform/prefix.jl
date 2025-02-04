
### PREFIX FILLER
function perftestprefix(ctx :: Context)::Expr
    suite_name = "$(basename(ctx._global.original_file_path))_PERFORMANCE"

    if isdir("./$(ctx._global.configuration["general"]["save_folder"])")
    else
        mkdir("./$(ctx._global.configuration["general"]["save_folder"])")
    end

    return quote
        using Test
        using PerfTest: DepthRecord,Metric_Test,Methodology_Result,StrOrSym,Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!,measureMemBandwidth!,addLog,@PRFTBenchmark,PRFTBenchmarkGroup,@PRFTCapture_out,@PRFTCount_ops,PRFTflop,@PRFTSuppress

        # Where all needed data for the tests is going to saved
        _PRFT_GLOBAL = Dict{Symbol,Any}()
        # If no MPI there is just one "rank" which is the main one
        _PRFT_GLOBAL[:is_main_rank] = true
        _PRFT_GLOBAL[:comm_size] = 1
        MPISetup($mode, _PRFT_GLOBAL)

        $(
            if ctx._global.configuration["general"]["autoflops"]
                quote
                    using CountFlops
                end
            else
                quote
                    begin end
                end
            end
        )

        if _PRFT_GLOBAL[:is_main_rank]
            # Used to save data about this test suite if needed
            path = $("./$(ctx._global.configuration["general"]["save_folder"])/$(suite_name).JLD2")

            nofile = true
            if isfile(path)
                nofile = false
                _PRFT_GLOBAL[:datafile] = PerfTest.openDataFile(path)
            else
                _PRFT_GLOBAL[:datafile] = PerfTest.Perftest_Datafile_Root(PerfTest.Perftest_Result[],
                    PerfTest.Dict{PerfTest.StrOrSym,Any}[])

                PerfTest.p_yellow("[!]")
                println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
            end
        end

        # Do machine specs
        # Will compute peak flops and peak bandwidth and populate
        $(machineBenchmarks())

        # Methodology prefixes
        #$(regressionPrefix(ctx))
        #$(effMemThroughputPrefix(ctx))

        _PRFT_LOCAL_SUITE = PRFTBenchmarkGroup()
        # Additional, used to save values from the function evaluation that need to be reused in the testing phase
        _PRFT_LOCAL_ADDITIONAL = Dict()
    end
end
