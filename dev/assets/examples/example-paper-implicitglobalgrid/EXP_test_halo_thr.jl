
# NOTE: All tests of this file can be run with any number of processes.
# Nearly all of the functionality can however be verified with one single process
# (thanks to the usage of periodic boundaries in most of the full halo update tests).

push!(LOAD_PATH, "../src")
using Test
using PerfTest

import MPI, LoopVectorization
using ImplicitGlobalGrid; GG = ImplicitGlobalGrid
import ImplicitGlobalGrid: @require, longnameof
using ThreadPinning
pinthreads(:compact)
threadinfo()
NTHREADS = 16

# 256M Elements on STREAM Benchmark (2GB)
@perftest_config "
[machine_benchmarking]
memory_bandwidth_test_buffer_size = 536870912
"

array_types          = ["CPU"]
gpu_array_types      = []
device_types         = ["auto"]
gpu_device_types     = []
allocators           = Function[zeros]
gpu_allocators       = []
ArrayConstructors    = [Array]
GPUArrayConstructors = []
CPUArray             = Array

## Test setup
MPI.Init();
nprocs = MPI.Comm_size(MPI.COMM_WORLD); # NOTE: these tests can run with any number of processes.
ndims_mpi = GG.NDIMS_MPI;
nneighbors_per_dim = GG.NNEIGHBORS_PER_DIM; # Should be 2 (one left and one right neighbor).
# 256M Elements (2GB)
nx = Int(round(sqrt(536870912/16*NTHREADS/nprocs)));
ny = nx;
nz = 5;
dx = 1.0
dy = 1.0
dz = 1.0

@testset "Memory throughput" begin

    # NOTE: I have removed here many tests in order not to make this example too long.
    
    @testset "3. data transfer components" begin
        @testset "iwrite_sendbufs! / iread_recvbufs!" begin

            @testset "write_h2h! / read_h2h!" begin
                init_global_grid(nx, ny, nz; quiet=false, init_MPI=false);
                P  = zeros(nx,  ny,  nz  );
                P .= [iz*1e2 + iy*1e1 + ix for ix=1:size(P,1), iy=1:size(P,2), iz=1:size(P,3)];
                P2 = zeros(size(P));
                halowidths = (1,1,1)
                # (dim=3)
		buf = zeros(size(P ,1), size(P,2), halowidths[3]);
		ranges = [1:size(P,1), 1:size(P,2), 1:1];

		i = 0
		@define_eff_memory_throughput begin
                    (nx * ny * 8) * 3 * MPI.Comm_size(MPI.COMM_WORLD) / :median_time
                end
                @auxiliary_metric name="Time" units="s" begin
                    :median_time
                end
                @auxiliary_metric name="MPI" units="size" begin
                    MPI.Comm_size(MPI.COMM_WORLD);
                end
                for i in 1:1
                    GG.write_h2h!(buf, P, ranges, 3);
                end
                @perftest begin
             	   GG.read_h2h!(buf, P2, ranges, 3);
                end
                finalize_global_grid(finalize_MPI=false);
            end;


        end;
    end;
end;

## Test tear down
MPI.Barrier(MPI.COMM_WORLD)
MPI.Finalize()
