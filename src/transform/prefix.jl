
### PREFIX FILLER
function perftestprefix(ctx::Context)::Expr
    suite_name = "$(basename(ctx._global.original_file_path))_PERFORMANCE"

    return quote
        using Test, Dates
        $(mode == MPIMode ? :(using MPI; PerfTest.MPISetup(PerfTest.MPIMode)) : :(nothing))
        # The suite calls the extensions loaded during the transform (e.g. PerfTest.perfmon, CUDA.synchronize), the
        # process that executes it loads them as well, whether the recipe imports their packages or not
        $(PerfTest.is_loaded(:LIKWID) ? quote using LIKWID end : quote end)
        $(PerfTest.is_loaded(:CUDA) ? quote using CUDA end : quote end)
        $(PerfTest.is_loaded(:AMDGPU) ? quote using AMDGPU end : quote end)
        using PerfTest: DepthRecord, Metric_Test, Methodology_Result, StrOrSym, Metric_Result, magnitudeAdjust, MPISetup, newMetricResult, buildPrimitiveMetrics!, measureCPUPeakFlops!, measureMemBandwidth!, addLog, @PRFTBenchmark, PRFTBenchmarkGroup, @PRFTCapture_out, @PRFTSuppress, Test_Result, by_index, regression, Suite_Execution_Result, savePrimitives, main_rank, GlobalSuiteData, @perftestset, PerfTestSet, extractTestResults, saveMethodologyData, Configuration, metricSampledValue, SampledValue

        _t_begin = time()
        _GLOBAL_MODE = $mode

        if main_rank($mode)
            # Used to save data about this test suite if needed, its folder is created when the results are saved.
            # Read on execution, so an interpolated save_folder takes its value
            path = "./" * Configuration.CONFIG["general"]["save_folder"] * $("/$(suite_name).JLD2")

            nofile = true
            if isfile(path)
                nofile = false
                datafile = PerfTest.openDataFile(path)
            else
                datafile = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
            end

            # Regression data
            regression_path = Configuration.CONFIG["regression"]["dedicated_reference_file"]
            # If absent use default data file, otherwise check if exists and open custom file
            if regression_path != "" && isfile(regression_path)
                regression_file = PerfTest.openDataFile(regression_path)
            else
                if regression_path != ""
                    regression_file = PerfTest.Perftest_Datafile_Root(PerfTest.Suite_Execution_Result[])
                else
                    regression_file = datafile
                    regression_path = path
                end
            end

            _PRFT_GLOBALS = GlobalSuiteData(datafile, path, $(ctx._global.original_file_path))

            if length(regression_file.results) > 0
                for i in length(regression_file.results):-1:1
                    if length(retrievePerfTests(regression_path, get=:tests, where_pred=testFailed, execution=i)) == 0
                        _PRFT_GLOBALS.old = regression_file.results[i].perftests
                        println("Regression: Previous performance reference for this configuration has been found, regression tests could be performed. Regression is currenctly $($(Configuration.CONFIG["regression"]["enabled"]) ? "enabled" : "disabled")).")
                        break
                    end
                end
            else
                _PRFT_GLOBALS.old = nothing
            end
        else
            _PRFT_GLOBALS = GlobalSuiteData()
        end

        # Do machine probe
        $(machineBenchmarks(mode, ctx))

    end
end
