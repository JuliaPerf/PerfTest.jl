
### PREFIX FILLER
function perftestprefix(ctx :: Context)::Expr
    suite_name = "$(basename(ctx._global.original_file_path))_PERFORMANCE"

    if isdir("./$(Configuration.CONFIG["general"]["save_folder"])")
    else
        mkdir("./$(Configuration.CONFIG["general"]["save_folder"])")
    end

    return quote
        using Test, Dates
        using PerfTest: DepthRecord,Metric_Test,Methodology_Result,StrOrSym,Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!,measureMemBandwidth!,addLog,@PRFTBenchmark,PRFTBenchmarkGroup,@PRFTCapture_out,@PRFTCount_ops,PRFTflop,@PRFTSuppress,Test_Result,by_index,regression,Suite_Execution_Result,savePrimitives,main_rank,GlobalSuiteData,@perftestset,PerfTestSet,extractTestResults,saveMethodologyData,Configuration

        _t_begin = time()

        MPISetup($mode)
        
        if main_rank($mode)
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
            
            # Regression data
            regression_path = Configuration.CONFIG["regression"]["custom_file"]
            # If absent use default data file, otherwise check if exists and open custom file
            if regression_path != "" && isfile(regression_path)
                regression_file = PerfTest.openDataFile(regression_path)
            else
                if regression_path != ""
                    @error "Regression data file $regression_file could not be opened or found"
                else
                    regression_file = datafile
                end
            end

            _PRFT_GLOBALS = GlobalSuiteData(datafile,path,$(ctx._global.original_file_path))

            if length(regression_file.results) > 0
                _PRFT_GLOBALS.old = regression_file.results[end].perftests
            else
                _PRFT_GLOBALS.old = nothing
            end
        else
            _PRFT_GLOBALS = GlobalSuiteData()
        end

        # Do machine specs
        # Will compute peak flops and peak bandwidth and populate
        $(machineBenchmarks(mode))

        # Methodology prefixes
        #$(regressionPrefix(ctx))
        #$(effMemThroughputPrefix(ctx))

    end
end
