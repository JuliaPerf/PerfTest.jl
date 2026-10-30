module KktCholesky

using LinearAlgebra
using Random

export build_kkt_system, cholesky_factor_fast!, cholesky_factor_regressed!,
       forward_substitution!, back_substitution!, solve_kkt, relative_residual

# Synthetic SPD "condensed KKT" system K = AᵀA + σI, b -- representative of
# the normal-equations/Newton system solved every iteration of a QP/SOCP
# interior-point method (Clarabel.jl, OSQP, ECOS, ...). A is m×n with m<n,
# so AᵀA alone is only positive semi-definite (rank ≤ m); σI shifts every
# eigenvalue by σ>0, making K strictly positive definite regardless of rank.
function build_kkt_system(n::Int, m::Int; seed::Int=1, sigma::Float64=1e-2)
    rng = MersenneTwister(seed)
    A = randn(rng, m, n)
    K = Matrix(Symmetric(A' * A))
    @inbounds for i in 1:n
        K[i, i] += sigma
    end
    b = randn(rng, n)
    return K, b
end

# Unblocked right-looking Cholesky (K = L*Lᵀ), "kji" loop order: for each
# pivot k, the trailing-submatrix rank-1 update loops columns j (outer) then
# rows i (inner), so the innermost loop walks straight down a column of L --
# contiguous in Julia's column-major storage. This is the textbook loop
# order for column-major languages (Julia, Fortran, MATLAB, R).
function cholesky_factor_fast!(L::Matrix{Float64}, K::Matrix{Float64})
    n = size(K, 1)
    copyto!(L, K)
    @inbounds for k in 1:n
        L[k, k] = sqrt(L[k, k])
        invLkk = 1.0 / L[k, k]
        for i in (k+1):n
            L[i, k] *= invLkk
        end
        for j in (k+1):n
            ljk = L[j, k]
            @simd for i in j:n
                L[i, j] -= L[i, k] * ljk
            end
        end
    end
    @inbounds for j in 1:n, i in 1:(j-1)
        L[i, j] = 0.0
    end
    return L
end

# THE REGRESSION. Same algorithm, same operations, same floating-point
# results as `cholesky_factor_fast!` (bit-for-bit identical L, see README) --
# only the trailing-submatrix loop nest is transposed to "kij" order: rows i
# outer, columns j inner. `L[i, j]` for fixed i is now walked across a *row*,
# i.e. striding n elements through memory instead of 1. This is the kind of
# one-line-diff bug that shows up when porting/refactoring from a row-major
# reference (C, NumPy) without adjusting loop order for Julia's layout: no
# functional test can ever catch it (@simd is still there, the answer is
# still exactly right), only a performance-regression suite can.
function cholesky_factor_regressed!(L::Matrix{Float64}, K::Matrix{Float64})
    n = size(K, 1)
    copyto!(L, K)
    @inbounds for k in 1:n
        L[k, k] = sqrt(L[k, k])
        invLkk = 1.0 / L[k, k]
        for i in (k+1):n
            L[i, k] *= invLkk
        end
        for i in (k+1):n
            lik = L[i, k]
            @simd for j in (k+1):i
                L[i, j] -= lik * L[j, k]
            end
        end
    end
    @inbounds for j in 1:n, i in 1:(j-1)
        L[i, j] = 0.0
    end
    return L
end

function forward_substitution!(z::Vector{Float64}, L::Matrix{Float64}, b::Vector{Float64})
    n = length(b)
    @inbounds for i in 1:n
        s = b[i]
        @simd for k in 1:(i-1)
            s -= L[i, k] * z[k]
        end
        z[i] = s / L[i, i]
    end
    return z
end

# Solves Lᵀx = z; Lᵀ[i, k] = L[k, i].
function back_substitution!(x::Vector{Float64}, L::Matrix{Float64}, z::Vector{Float64})
    n = length(z)
    @inbounds for i in n:-1:1
        s = z[i]
        @simd for k in (i+1):n
            s -= L[k, i] * x[k]
        end
        x[i] = s / L[i, i]
    end
    return x
end

function solve_kkt(K::Matrix{Float64}, b::Vector{Float64}, fast::Bool=true)
    n = size(K, 1)
    L = Matrix{Float64}(undef, n, n)
    fast ? cholesky_factor_fast!(L, K) : cholesky_factor_regressed!(L, K)
    z = Vector{Float64}(undef, n)
    x = Vector{Float64}(undef, n)
    forward_substitution!(z, L, b)
    back_substitution!(x, L, z)
    return x
end

relative_residual(K, b, x) = norm(K * x - b) / norm(b)

end # module
