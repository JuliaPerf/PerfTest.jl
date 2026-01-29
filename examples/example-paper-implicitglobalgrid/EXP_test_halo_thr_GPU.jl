push!(LOAD_PATH, "../src")
using Test
using PerfTest
using BenchmarkTools
using CUDA, AMDGPU
using CellArrays, StaticArrays
import MPI, LoopVectorization

test_cuda = CUDA.functional()
test_amdgpu = AMDGPU.functional()

# CHANGE THIS AS REQUIRED
test_cpu = false
NTHREADS = 16
#

using ImplicitGlobalGrid; GG = ImplicitGlobalGrid
import ImplicitGlobalGrid: @require, longnameof
using ThreadPinning
pinthreads(:compact)
threadinfo()



SArray{S, T, N, L}(a::Number) where {S, T, N, L}          = SArray{S, T, N, L}(ntuple(_ -> a, Val(L)))
celldims                                                  = (2, 2)
Cell{T}                                                   = SMatrix{celldims..., T, prod(celldims)}
cellzeros0(::Type{T}, dims::Integer...) where {T<:Number} = (A=CPUCellArray{Cell{T},0}(undef, dims); A.data.=0.0; A)
cellzeros1(::Type{T}, dims::Integer...) where {T<:Number} = (A=CPUCellArray{Cell{T},1}(undef, dims); A.data.=0.0; A)
cellzeros0(dims::Integer...)                              = cellzeros0(Float64, dims...)
cellzeros1(dims::Integer...)                              = cellzeros1(Float64, dims...)

array_types              = ["CPU"]
cellarray_types          = ["CPU cell (B=0)", "CPU cell (B=1)"]
gpu_array_types          = []
gpu_cellarray_types      = []
device_types             = ["auto"]
gpu_device_types         = []
allocators               = Function[zeros]
cellallocators           = Function[cellzeros0, cellzeros1]
cpu_allocators           = Function[zeros]
cpu_cellallocators       = Function[cellzeros0, cellzeros1]
gpu_allocators           = []
gpu_cellallocators       = []
ArrayConstructors        = [Array]
CellArrayConstructors    = [CPUCellArray, CPUCellArray]
CPUArrayConstructors     = [Array]
CPUCellArrayConstructors = [CPUCellArray, CPUCellArray]
GPUArrayConstructors     = []
GPUCellArrayConstructors = []
CPUArray                 = Array

if test_cuda
    @define_CuCellArray
    cuzeros = CUDA.zeros
    cucellzeros0(::Type{T}, dims::Integer...) where {T<:Number} = (A=CuCellArray{Cell{T},0}(undef, dims); A.data.=0.0; A)
    cucellzeros1(::Type{T}, dims::Integer...) where {T<:Number} = (A=CuCellArray{Cell{T},1}(undef, dims); A.data.=0.0; A)
    cucellzeros0(dims::Integer...)                              = cucellzeros0(Float64, dims...)
    cucellzeros1(dims::Integer...)                              = cucellzeros1(Float64, dims...)
    push!(array_types, "CUDA")
    push!(cellarray_types, "CUDA cell (B=0)", "CUDA cell (B=1)")
    push!(gpu_array_types, "CUDA")
    push!(gpu_cellarray_types, "CUDA cell (B=0)", "CUDA cell (B=1)")
    push!(device_types, "CUDA")
    push!(gpu_device_types, "CUDA")
    push!(allocators, cuzeros)
    push!(cpu_allocators, zeros)
    push!(cpu_cellallocators, cellzeros0, cellzeros1)
    push!(cellallocators, cucellzeros0, cucellzeros1)
    push!(gpu_allocators, cuzeros)
    push!(gpu_cellallocators, cucellzeros0, cucellzeros1)
    push!(ArrayConstructors, CuArray)
    push!(CellArrayConstructors, CuCellArray, CuCellArray)
    push!(CPUArrayConstructors, Array)
    push!(CPUCellArrayConstructors, CPUCellArray, CPUCellArray)
    push!(GPUArrayConstructors, CuArray)
    push!(GPUCellArrayConstructors, CuCellArray, CuCellArray)
end
if test_amdgpu
    @define_ROCCellArray
    roczeros = AMDGPU.zeros
    roccellzeros0(::Type{T}, dims::Integer...) where {T<:Number} = (A=ROCCellArray{Cell{T,0}}(undef, dims); A.data.=0.0; A)
    roccellzeros1(::Type{T}, dims::Integer...) where {T<:Number} = (A=ROCCellArray{Cell{T,1}}(undef, dims); A.data.=0.0; A)
    roccellzeros0(dims::Integer...)                              = roccellzeros0(Float64, dims...)
    roccellzeros1(dims::Integer...)                              = roccellzeros1(Float64, dims...)
    push!(array_types, "AMDGPU")
    push!(cellarray_types, "AMDGPU cell (B=0)", "AMDGPU cell (B=1)")
    push!(gpu_array_types, "AMDGPU")
    push!(gpu_cellarray_types, "AMDGPU cell (B=0)", "AMDGPU cell (B=1)")
    push!(device_types, "AMDGPU")
    push!(gpu_device_types, "AMDGPU")
    push!(allocators, roczeros)
    push!(cpu_allocators, zeros)
    push!(cpu_cellallocators, cellzeros0, cellzeros1)
    push!(cellallocators, roccellzeros0, roccellzeros1)
    push!(gpu_allocators, roczeros)
    push!(gpu_cellallocators, roccellzeros0, roccellzeros1)
    push!(ArrayConstructors, ROCArray)
    push!(CellArrayConstructors, ROCCellArray, ROCCellArray)
    push!(CPUArrayConstructors, Array)
    push!(CPUCellArrayConstructors, CPUCellArray, CPUCellArray)
    push!(GPUArrayConstructors, ROCArray)
    push!(GPUCellArrayConstructors, ROCCellArray, ROCCellArray)
end
allocators_union           = [allocators... cellallocators...]
cpu_allocators_union       = [cpu_allocators... cpu_cellallocators...]
gpu_allocators_union       = [gpu_allocators... gpu_cellallocators...]
ArrayConstructors_union    = [ArrayConstructors... CellArrayConstructors...]
CPUArrayConstructors_union = [CPUArrayConstructors... CPUCellArrayConstructors...]
GPUArrayConstructors_union = [GPUArrayConstructors... GPUCellArrayConstructors...]
array_types_union          = [array_types... cellarray_types...]
gpu_array_types_union      = [gpu_array_types... gpu_cellarray_types...]
device_types_union         = [device_types... device_types... device_types...]
gpu_device_types_union     = [gpu_device_types... gpu_device_types... gpu_device_types...]


## Test setup
MPI.Init();
nprocs = MPI.Comm_size(MPI.COMM_WORLD); # NOTE: these tests can run with any number of processes.
ndims_mpi = GG.NDIMS_MPI;
nneighbors_per_dim = GG.NNEIGHBORS_PER_DIM; # Should be 2 (one left and one right neighbor).
nx = Int(round(sqrt(1024^3/4/16*NTHREADS/nprocs)));
ny = nx;
nz = 5;
dx = 1.0
dy = 1.0
dz = 1.0


@testset "Memory throughput" begin

    # Benchmark result multiplied by two to account for a write + read of the same bytes
    @define_benchmark name="GPUBandwidthCUDA" units="B/s" begin
        if CUDA.functional()
            size_mb = 1000
            # Convert size from MB to bytes
            size_bytes = size_mb * 1024 * 1024
            # Create data on CPU
            host_data = rand(Float32, div(size_bytes, sizeof(Float32)))
            # Preallocate GPU array
            device_data = CUDA.zeros(Float32, length(host_data))
            # Benchmark
            b = @benchmark begin CUDA.@sync(copyto!($device_data, $host_data))end;
            size_bytes / (median(b.times) / 1e9)
        else 
            0
        end
    end
    
    @define_benchmark name="GPUBandwidthROC" units="B/s" begin
        if AMDGPU.functional()
            # Same as CUDA but with roc
            size_mb = 1000
            size_bytes = size_mb * 1024 * 1024
            host_data = rand(Float32, div(size_bytes, sizeof(Float32)))
            device_data = AMDGPU.zeros(Float32, length(host_data))
            b = @benchmark begin AMDGPU.@sync(copyto!($device_data, $host_data)) end;
            size_bytes / (median(b.times) / 1.0e9)
        else 
            0
        end
    end

    # NOTE: I have removed here many tests in order not to make this example too long.
    @testset "3. data transfer components" begin
        @testset "iwrite_sendbufs! / iread_recvbufs!" begin

            @auxiliary_metric name = "Time" units = "s" begin
                :median_time
            end
            @auxiliary_metric name = "MPI" units = "size" begin
                MPI.Comm_size(MPI.COMM_WORLD)
            end

            @testset "write_h2h! / read_h2h!" begin
                if test_cpu
                    init_global_grid(nx, ny, nz; quiet=false, init_MPI=false)
                    P = zeros(nx, ny, nz)
                    P .= [iz * 1e2 + iy * 1e1 + ix for ix = 1:size(P, 1), iy = 1:size(P, 2), iz = 1:size(P, 3)]
                    P2 = zeros(size(P))
                    halowidths = (1, 1, 1)
                    # (dim=3)
                    buf = zeros(size(P, 1), size(P, 2), halowidths[3])
                    ranges = [1:size(P, 1), 1:size(P, 2), 1:1]

                    # See beggining of EXP_test_halo_thr.jl for more info on the x3 multiplier
                    @define_eff_memory_throughput begin
                        (nx * ny * 8) * 3 * MPI.Comm_size(MPI.COMM_WORLD) / :median_time
                    end	

                    i = 0
                    for i in 1:1
                        GG.write_h2h!(buf, P, ranges, 3);
                    end
                    @perftest begin
                    GG.read_h2h!(buf, P2, ranges, 3);
                    end
                    finalize_global_grid(finalize_MPI=false);
                end
            end;

            @static if test_cuda || test_amdgpu
                @testset "write_d2x! / write_d2h_async! / read_x2d! / read_h2d_async!" for (array_type, device_type, gpuzeros, GPUArray) in zip(gpu_array_types, gpu_device_types, gpu_allocators, GPUArrayConstructors)
                    init_global_grid(nx, ny, nz; quiet=true, init_MPI=false, device_type=device_type);
                    P  = zeros(nx,  ny,  nz  );
                    P .= [iz*1e2 + iy*1e1 + ix for ix=1:size(P,1), iy=1:size(P,2), iz=1:size(P,3)];
                    P  = GPUArray(P);
                    halowidths = (1,1,1)
                    if array_type == "CUDA"
                        # (dim=3)
                        dim = 3
                        P2 = gpuzeros(eltype(P), size(P))
                        buf = zeros(size(P, 1), size(P, 2), halowidths[dim])
                        buf .= 0.0
                        P2 .= 0.0
                        ranges = [1:size(P, 1), 1:size(P, 2), 1:1]
                        nthreads = (1, 1, 1)
                        halosize = [(r[end] - r[1]) + 1 for r = ranges]
                        nblocks = Tuple(ceil.(Int, halosize ./ nthreads))
                        custream = stream();
            	        @define_eff_memory_throughput custom_benchmark=GPUBandwidthCUDA begin
                	        (nx * ny * 8) * MPI.Comm_size(MPI.COMM_WORLD) / :median_time
            	        end	
                        @perftest begin
                            CUDA.@sync GG.read_h2d_async!(buf, P2, ranges, custream)
                        end
                    elseif array_type == "AMDGPU"
                        # (dim=3)
                        dim = 3
                        P2 = gpuzeros(eltype(P), size(P))
                        buf = zeros(size(P, 1), size(P, 2), halowidths[dim])
                        ranges = [1:size(P, 1), 1:size(P, 2), 1:1]
                        nthreads = (1, 1, 1)
                        halosize = [(r[end] - r[1]) + 1 for r = ranges]
                        nblocks = Tuple(ceil.(Int, halosize ./ nthreads))
                        rocstream = AMDGPU.HIPStream()
            	        @define_eff_memory_throughput custom_benchmark=GPUBandwidthROC begin
                	        (nx * ny * 8) * MPI.Comm_size(MPI.COMM_WORLD) / :median_time
            	        end	
                        @perftest begin
                            GG.read_h2d_async!(buf, P2, ranges, rocstream)
                            AMDGPU.synchronize()
                        end
                    end
                    finalize_global_grid(finalize_MPI=false);
                end;
            end

        end;
    end;
end;

## Test tear down
MPI.Barrier(MPI.COMM_WORLD)
MPI.Finalize()
