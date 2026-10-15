module KktLDLT

export ldlt_factor_regressed!, ldlt_solve!

# THE REGRESSION: a naive, hand-rolled dense LDLᵀ (K = L*D*Lᵀ, L unit lower
# triangular, D diagonal with signed entries), generalized from
# KktCholesky.jl to the *indefinite* systems real interior-point solvers
# actually factor (a KKT/Newton matrix has a mixed-sign diagonal; it is not
# SPD, so plain Cholesky's `sqrt` doesn't apply). Standing in for "someone
# replaced the specialized sparse solver backend with a naive dense one" --
# see clarabel_perftest.jl, where `USE_FAST_FACTORIZATION = true` instead
# calls Clarabel's own real QDLDL backend directly, and only `false` routes
# through this kernel.
#
# K only needs to be *quasi-definite* (not necessarily SPD) for this to be
# numerically safe without pivoting: quasi-definite matrices admit an LDLᵀ
# factorization under *any* symmetric row/column permutation, including the
# identity, which is exactly the structural property that lets solvers like
# Clarabel.jl, OSQP, and QDLDL skip pivoting altogether.
#
# The trailing-submatrix update is embarrassingly parallel across rows: for
# fixed k, each iteration of `i` reads column k of L (already finalized this
# step) and writes only row i of L, so distinct `i`s touch disjoint memory --
# safe to hand to `Threads.@threads` with no synchronization. It still walks
# `L[i, j]` across a row (stride n, "kij" order) rather than down a column
# (stride 1, "kji" order), so per-core throughput remains the cache-unfriendly
# one from the original regression; threading only adds cores, it doesn't fix
# the access pattern.
function ldlt_factor_regressed!(L::Matrix{Float64}, D::Vector{Float64}, K::Matrix{Float64})
    n = size(K, 1)
    copyto!(L, K)
    @inbounds for k in 1:n
        D[k] = L[k, k]
        invDk = 1.0 / D[k]
        for i in (k+1):n
            L[i, k] *= invDk
        end
        Dk = D[k]
        Threads.@threads for i in (k+1):n
            @inbounds begin
                lik_Dk = L[i, k] * Dk
                @simd for j in (k+1):i
                    L[i, j] -= lik_Dk * L[j, k]
                end
            end
        end
    end
    @inbounds for k in 1:n
        L[k, k] = 1.0
        for i in 1:(k-1)
            L[i, k] = 0.0
        end
    end
    return L, D
end

# Solves K x = b given K = L*D*Lᵀ, in place into x.
function ldlt_solve!(x::Vector{Float64}, L::Matrix{Float64}, D::Vector{Float64}, b::Vector{Float64})
    n = length(b)
    z = similar(b)
    @inbounds for i in 1:n
        s = b[i]
        @simd for k in 1:(i-1)
            s -= L[i, k] * z[k]
        end
        z[i] = s
    end
    @inbounds for i in 1:n
        z[i] /= D[i]
    end
    @inbounds for i in n:-1:1
        s = z[i]
        @simd for k in (i+1):n
            s -= L[k, i] * x[k]
        end
        x[i] = s
    end
    return x
end

end # module
