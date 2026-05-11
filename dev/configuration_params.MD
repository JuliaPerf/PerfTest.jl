# Configuration Parameters

This document describes all configuration parameters available. Parameters are organized by section, they are specified in TOML format.

---

## `[general]`

General settings that control the overall behavior of the package.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `autoflops` | `Bool` | `true` | Whether the autoflop counter is enabled and accessible during testing. |
| `numas` | `String \| Integer \| Float64` | `"single"` | Amount of NUMAS to use when pinning threads. |
| `threads_per_numa` | `String \| Integer \| Float64` | `"single"` | Amount of threads to pin per NUMA. |
| `save_results` | `Bool` | `true` | Whether to record the results of executing the performance suite. |
| `logs_enabled` | `Bool` | `true` | Enable or disable the log subsystem. If false, this will prevent PerfTest from creating a log folder and log files.|
| `save_folder` | `String` | `".perftests"` | Folder where performance suite results shall be stored. |
| `max_saved_results` | `Int` | `20` | Maximum amount of performance test suite execution results to be saved in the result file for each suite. |
| `plotting` | `Bool` | `true` | Whether to have plots in the test output of methodologies that support it. |
| `verbose` | `Int` | `0` | Whether to output the collected logs in the standard output. |
| `recursive` | `Bool` | `true` | If enabled, whenever a file is included inside a recipe that is being transformed, it will be transformed as well. |
| `safe_formulas` | `Bool` | `false` | Deprecated. |
| `suppress_output` | `Bool` | `true` | Whether to hide the output of the test targets. If false the output of each execution will be shown, which will be probably a long output. |

---

## `[regression]`

Settings for regression testing.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `true` | Whether to use regression testing in this suite. |
| `dedicated_reference_file` | `String` | `""` | If not an empty string, a succesful suite execution will be saved into this file, as well as in the (result file see `[general] save_folder`). The last saved execution will be used as reference for regression testing. If empty the package will look at the result file instead, and find the latest sucessful execution as reference. |
| `default_threshold` | `Number` | `1.1` | The default threshold of the `@regression` macro if no threshold is specified. |
| `use_bencher` | `Bool` | `false` | Whether to enable Bencher to upload results to an online CI/CD performance benchmark platform. THIS FEATURE IS EXPERIMENTAL and likely unstable. |

---

## `[roofline]`

Settings for roofline analysis.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `true` | Whether to use roofline methodologies in this suite. |
| `default_threshold` | `Number` | `0.5` | Default threshold of the `@roofline` macro if no threshold is specified. |

---

## `[memory_bandwidth]`

Settings for memory bandwidth analysis.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `true` | Whether to use effective memory throughput methodology in this suite. |
| `default_threshold` | `Number` | `0.5` | Default thresholds of the `@define_eff_mem_throughput` macro if no threshold is specified. |

---

## `[perfcompare]`

Settings for performance comparison.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `true` | Whether to use the `@perfcompare` macro in this suite. |

---

## `[machine_benchmarking]`

Settings for benchmarking the underlying machine.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `memory_bandwidth_test_buffer_size` | `Int` | `0` | If 0 a buffer size for bandwith benchmarks is used so its at least 4 times bigger than the biggest cache level of the machine. If non-zero this value is used to set the buffer size instead. |

---

## `[MPI]`

Settings for MPI-based execution.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | `Bool` | `false` | Whether to enable the MPI aware performance suite generation, this will mainly make sure tests are measured in all ranks but evaluated on the main rank only, and that machine benchmarks take into account all ranks.|
| `mode` | `String` | `"reduce"` | This has no function as of now, but it will be used in future versions of perftest. |

---

## `[bencher]`

Settings for [Bencher](https://bencher.dev) integration. This feature is experimental, and likely prone to bugs.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `api_key` | `String` | `""` | The Bencher platform key to use to connect to bencher. |
| `api_url` | `String` | `"https://api.bencher.dev"` | The API url. |
| `project_name` | `String` | `""` | The name of the project where metrics and testbeds shall be posted. |
| `organization` | `String` | `""` | The organization that holds the project. |
| `custom_testbed_name` | `String` | `""` | The customized identification of this machine (a.k.a testbed for Bencher) when uploading posting suite execution results. |
