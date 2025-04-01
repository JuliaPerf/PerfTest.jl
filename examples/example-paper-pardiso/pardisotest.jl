using Test
using PerfTest
using Pkg


# UNCOMMENT WHEN DOING THE BLAS BASED REGRESSION EXPERIMENT
#using Libdl
#Libdl.dlopen("libblas.so", Libdl.RTLD_GLOBAL)

using Pardiso
using Random
using SparseArrays
using LinearAlgebra
using MatrixMarket


# Initialize solver
ps = PardisoSolver()

set_msglvl!(ps, 1)

# Makes the matrix of interest

function build_sparse_matrix(nx, ny, nz, hx2, hy2, hz2)
    data = Float64[]
    row_indices = Int[]
    col_indices = Int[]

    for j in 0:(ny-1)
        for i in 0:(nx-1)
            for k in 0:(nz-1)
                row = k * nx * ny + j * nx + i + 1  # Julia is 1-based

                if k > 0  # Left neighbor
                    col = (k - 1) * nx * ny + j * nx + i + 1
                    push!(data, -hz2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end

                if i > 0  # Left neighbor
                    col = k * nx * ny + j * nx + (i - 1) + 1
                    push!(data, -hx2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end

                if j > 0  # Bottom neighbor
                    col = k * nx * ny + (j - 1) * nx + i + 1
                    push!(data, -hy2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end

                push!(data, 2 * (hx2 + hy2 + hz2))
                push!(row_indices, row)
                push!(col_indices, row)

                if k < nz - 1  # Right neighbor
                    col = (k + 1) * nx * ny + j * nx + i + 1
                    push!(data, -hz2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end

                if i < nx - 1  # Right neighbor
                    col = k * nx * ny + j * nx + (i + 1) + 1
                    push!(data, -hx2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end

                if j < ny - 1  # Top neighbor
                    col = k * nx * ny + (j + 1) * nx + i + 1
                    push!(data, -hy2)
                    push!(row_indices, row)
                    push!(col_indices, col)
                end

            end
        end
    end

    # Create sparse matrix
    sparse(row_indices, col_indices, data)
end


@testset "Pardiso GFLOP tests" begin

    @testset "Laplace for different N" for N in [i for i in [40,42,45,47,
						 50,52,55,
						 57,
						 60
						 ]]

        A = build_sparse_matrix(N,N,N, (N-1)^3 , (N-1)^3, (N-1)^3)


        # Dense auxiliary vectors
        x = zeros(Float64,N^3)
        b = zeros(Float64,N^3)

        ## We define operational intensity and thus enable a roofline test below
        #
        # Target ratio of 5% of roofline performance
        # Actual flops extracted from standard output
        # Operational intensity extraced from standard output as well
        @roofline target_ratio=0.4 actual_flops=begin
            flop = 1e9 * PerfTest.grepOutputXGetNumber(:printed_output,
                                                       "Gflop   for the numerical factorization:")
        end begin
            flop = 1e9 * PerfTest.grepOutputXGetNumber(:printed_output,
                                                       "Gflop   for the numerical factorization:")
            mem = sizeof(Float64) * PerfTest.grepOutputXGetNumber(:printed_output,
                                                                   "number of nonzeros in L")
            flop / mem
        end

        # Print pardiso output as well
        @auxiliary_metric name="OUT" units="String" begin
            :printed_output
        end

        # Do reorder phase previous to the test
        set_phase!(ps, 11)
        pardiso(ps, x, A, b)
        set_phase!(ps, 22)

        # Test performance, solver is the target
        @perftest samples=5 pardiso(ps, x, A, b)

    end

    @testset "Custom matrix" for mat in ["af_0_k101/af_0_k101.mtx", "af_shell3/af_shell3.mtx",
					  "pkustk10/pkustk10.mtx",
					  "pkustk11/pkustk11.mtx",
					  "pkustk12/pkustk12.mtx",
					  "pkustk13/pkustk13.mtx",
					  "pkustk14/pkustk14.mtx"
					  ]
        A = SparseMatrixCSC{Float64}(mmread(mat))

        # Dense auxiliary vectors
        x = zeros(Float64,size(A,1))
        b = zeros(Float64,size(A,1))

        ## We define operational intensity and thus enable a roofline test below
        #
        # Target ratio of 5% of roofline performance
        # Actual flops extracted from standard output
        # Operational intensity extraced from standard output as well
        @roofline target_ratio=0.4 actual_flops=begin
            flop = 1e9 * PerfTest.grepOutputXGetNumber(:printed_output,
                                                       "Gflop   for the numerical factorization:")
        end begin
            flop = 1e9 * PerfTest.grepOutputXGetNumber(:printed_output,
                                                       "Gflop   for the numerical factorization:")
            mem = sizeof(Float64) * PerfTest.grepOutputXGetNumber(:printed_output,
                                                                   "number of nonzeros in L")
            flop / mem
        end

        # Print pardiso output as well
        @auxiliary_metric name="OUT" units="String" begin
            :printed_output
        end

        # Do reorder phase previous to the test
        set_phase!(ps, 11)
        pardiso(ps, x, A, b)
        set_phase!(ps, 22)

        # Test performance, solver is the target
        @perftest samples=20 pardiso(ps, x, A, b)

    end
end

