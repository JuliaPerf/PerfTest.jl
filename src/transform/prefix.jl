
### PREFIX FILLER
function perftestprefix(ctx :: Context)::Expr
    suite_name = "$(basename(ctx._global.original_file_path))_PERFORMANCE"

    if isdir("./$(Configuration.CONFIG["general"]["save_folder"])")
    else
        mkdir("./$(Configuration.CONFIG["general"]["save_folder"])")
    end

    return quote
        using Test, Dates
        using PerfTest: DepthRecord,Metric_Test,Methodology_Result,StrOrSym,Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!,measureMemBandwidth!,addLog,@PRFTBenchmark,PRFTBenchmarkGroup,@PRFTCapture_out,@PRFTCount_ops,PRFTflop,@PRFTSuppress,Test_Result,by_index,regression,Suite_Execution_Result,savePrimitives,main_rank,GlobalSuiteData,@perftestset,PerfTestSet,extractTestResults,saveMethodologyData



        if main_rank()
            # Used to save data about this test suite if needed
            path = $("./$(Configuration.CONFIG["general"]["save_folder"])/$(suite_name).JLD2")


            nofile = true
            if isfile(path)
                nofile = false
                datafile = PerfTest.openDataFile(path)
            else
                datafile = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])

                PerfTest.p_yellow("[!]")
                println("Regression: No previous performance reference for this configuration has been found, measuring performance without evaluation.")
            end

            _PRFT_GLOBALS = GlobalSuiteData(datafile,path,$(ctx._global.original_file_path))
            MPISetup($mode, _PRFT_GLOBALS)
        end

        # Do machine specs
        # Will compute peak flops and peak bandwidth and populate
        $(machineBenchmarks())

        # Methodology prefixes
        #$(regressionPrefix(ctx))
        #$(effMemThroughputPrefix(ctx))

    end
end
