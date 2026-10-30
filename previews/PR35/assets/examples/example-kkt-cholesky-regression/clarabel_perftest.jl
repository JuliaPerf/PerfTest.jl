using Test, PerfTest, LIKWID
using Clarabel, QDLDL, LinearAlgebra, SparseArrays, Random

@perftest_threads :all

# Single, obviously-editable toggle simulating "a regression was introduced"
# -- same convention and demo walkthrough as kkt_perftest.jl (see README.md),
# except now it's plugged directly into Clarabel.jl's own solve.
#   true  -> the real, unmodified Clarabel/QDLDL backend, AMD-ordered
#            (sparse, specialized, exactly stock Clarabel)
#   false -> THE REGRESSION: the *same* real Clarabel/QDLDL backend, but
#            factored in natural (unpermuted) variable order instead of
#            AMD's fill-reducing order -- standing in for "someone
#            accidentally disabled/broke the fill-reducing permutation in
#            the sparse solver" -- see the QDLDL._get_amd_ordering override
#            below.
const USE_FAST_FACTORIZATION = true

# Which synthetic sparsity pattern build_qp() gives P (see build_qp below).
# Independent of, and orthogonal to, USE_FAST_FACTORIZATION above: this
# toggle controls *which QP gets solved*, not *how* it gets factored. A
# second top-level const, edited the same manual way as USE_FAST_FACTORIZATION
# (run_demo.sh only auto-sweeps that one; this one you flip by hand between
# full 4-step runs -- see README.md).
#   :random    -> Erdos-Renyi-style: edges between uniformly-random pairs of
#                 variables. The original/only model this file ever had;
#                 kept as the default so existing reference-file history
#                 still matches the model it was recorded against.
#   :geometric -> random geometric graph (RGG): n_vars points placed
#                 uniformly at random in [0,1]^2, edges are the
#                 (n_vars*avg_degree)/2 globally-closest pairs by Euclidean
#                 distance -- same target edge count as :random, so
#                 avg_degree stays a comparable density knob across both
#                 models; only the *connectivity pattern* differs (spatially
#                 local vs. uniform-random). See geometric_edges below.
const GRAPH_MODEL = :random #:geometric

# Only used when GRAPH_MODEL === :geometric (ignored otherwise). `nothing`
# is the original single-blob behavior: n_vars points spread uniformly over
# the whole [0,1]^2 domain, exactly as geometric_edges behaved before this
# toggle existed. Setting it to a number k softly caps how big a
# locally-dense group of points gets: points are drawn from
# ~n_vars/k randomly-placed Gaussian blobs instead of one uniform spread --
# "soft" because cluster membership is a random draw per point, not an
# exact/hard partition, so realized cluster sizes vary around k rather than
# being forced equal. See geometric_edges below for the mechanism and an
# important caveat: small k tends to fully *disconnect* the graph into
# separate components (nearest-neighbor edge selection exhausts a cluster's
# internal pairs before ever reaching another cluster), and disconnected
# components can never get fill-in between them under *any* ordering --
# so very small clusters should shrink AMD's relative advantage rather than
# grow it, the opposite direction from GRAPH_MODEL=:random's lack of
# separator structure.
const GRAPH_CLUSTER_SIZE = 512

# --- Override QDLDL's own fill-reducing-ordering selection ---------------
#
# QDLDL's permutation is chosen exactly once, at Clarabel.Solver(...)
# construction time, inside Clarabel.QDLDLDirectLDLSolver's constructor, via
# QDLDL.qdldl(KKT; ...)'s `perm` keyword. That keyword's default value is
# computed by the private helper QDLDL._get_amd_ordering(A, amd_dense_scale)
# (see QDLDL.jl's own doc comment on `qdldl`: "qdldl(A) uses the default AMD
# ordering ... qdldl(A,perm=nothing) factors without reordering" -- natural
# order is a first-class QDLDL-supported mode, not a hack). Every
# refactor!/solve! call afterward, one pair per Newton iteration, is purely
# numeric and reuses whatever permutation was picked here -- so overriding
# this one helper is enough to toggle AMD vs. natural order for the whole
# solve, and Clarabel.refactor!/Clarabel.solve! never need to be touched:
# both branches run Clarabel's real, unmodified QDLDL numeric code the
# entire time, only the permutation baked in at construction differs.
#
# After `using QDLDL`, Julia lets this module add or replace methods on any
# generic function for any type it doesn't own -- ordinary multiple
# dispatch, sometimes called "monkey-patching" (same mechanism the old
# refactor!/solve! overrides used). `_get_amd_ordering` is private
# (underscore-prefixed), not public API -- re-verify its name/signature if
# the pinned QDLDL version is ever bumped.
function QDLDL._get_amd_ordering(A, amd_dense_scale)
    if USE_FAST_FACTORIZATION
        # Stock QDLDL behavior, verbatim.
        meta = QDLDL.AMD.Amd()
        meta.control[QDLDL.AMD.AMD_DENSE] *= Float64(amd_dense_scale)
        return QDLDL.AMD.amd(A, meta)
    else
        return nothing
    end
end

# --- A small box-constrained QP: min 0.5 x'Px + q'x  s.t. 0 <= x <= u -----
# P is a genuinely *sparse* SPD matrix -- a sparse graph (~avg_degree
# edges/node, model selected by GRAPH_MODEL above), diagonally dominant for
# guaranteed SPD-ness -- with its variable labeling randomly shuffled
# *after* the graph is built (load-bearing for either graph model: it hides
# any accidental good ordering from the natural-order branch). AMD's
# ordering is derived purely from the sparsity graph, so it recovers a good
# elimination order regardless of labeling; the *natural* (post-shuffle)
# order has no such luck. This is what makes disabling AMD (see
# USE_FAST_FACTORIZATION above) a dramatic, realistic regression: with a
# fully dense P, no permutation could avoid O(n^3) work either way, so
# disabling AMD would barely register.

# Uniformly-random edges between distinct variable pairs (Erdos-Renyi-style).
function random_edges(rng::AbstractRNG, n_vars::Int, nedges::Int)
    Ii = rand(rng, 1:n_vars, nedges)
    Jj = rand(rng, 1:n_vars, nedges)
    return Ii, Jj
end

# Random geometric graph (RGG): n_vars points placed uniformly at random in
# [0,1]^dim (or, if avg_cluster_size is given, drawn from randomly-placed
# Gaussian blobs instead -- see below); edges are the `nedges`
# globally-closest (i,j) pairs by Euclidean distance -- build_qp passes it
# the exact same `nedges` it computes for random_edges, so avg_degree stays
# a comparable density knob between the two graph models.
#
# Only the upper triangle (i<j) is computed -- no redundant symmetric n x n
# distance matrix -- and partialsortperm picks the closest `nedges` pairs
# without fully sorting all n*(n-1)/2 of them.
#
# Picking edges by globally-smallest distance (rather than each node's own
# k nearest neighbors) can leave a handful of nodes with unusually low or
# zero degree. That's fine here: build_qp's diagonal-dominance step below
# adds +1 to every diagonal entry unconditionally, so P stays SPD (P is
# always exactly graph-Laplacian-plus-I) regardless of degree variance --
# realistic point-cloud irregularity, not a correctness concern.
#
# Assumes nedges <= n*(n-1)/2 (avg_degree well under n_vars) -- true for
# every n_vars in this file's sweep; partialsortperm errors otherwise.
#
# `avg_cluster_size`: nothing (default) draws all n_vars points uniformly
# over [0,1]^dim, one blob spanning the whole domain. A number k instead
# picks ~n_vars/k random cluster centers and draws each point near a
# randomly-assigned center (Gaussian, clamped back into [0,1]^dim); the
# spread is ~0.3x the centers' own typical nearest-neighbor spacing, tight
# enough that same-size clusters don't usually overlap. At k=1 this
# degenerates back to ~n_vars independent single-point "clusters" whose
# centers are themselves uniform over [0,1]^dim -- i.e. the same as
# `nothing` -- so the two ends of the dial meet smoothly.
function geometric_edges(rng::AbstractRNG, n_vars::Int, nedges::Int;
                          dim::Int=2, avg_cluster_size::Union{Nothing,Real}=nothing)
    pts = if avg_cluster_size === nothing
        rand(rng, dim, n_vars)
    else
        nclusters = clamp(round(Int, n_vars / avg_cluster_size), 1, n_vars)
        centers = rand(rng, dim, nclusters)
        spread = 0.3 * nclusters^(-1.0 / dim)
        assign = rand(rng, 1:nclusters, n_vars)
        out = Matrix{Float64}(undef, dim, n_vars)
        @inbounds for v in 1:n_vars
            @views out[:, v] .= clamp.(centers[:, assign[v]] .+ spread .* randn(rng, dim), 0.0, 1.0)
        end
        out
    end
    npairs = (n_vars * (n_vars - 1)) ÷ 2
    dists = Vector{Float64}(undef, npairs)
    Is = Vector{Int}(undef, npairs)
    Js = Vector{Int}(undef, npairs)
    k = 0
    @inbounds for i in 1:n_vars, j in (i+1):n_vars
        k += 1
        s = 0.0
        for d in 1:dim
            s += (pts[d, i] - pts[d, j])^2
        end
        dists[k] = sqrt(s)
        Is[k] = i
        Js[k] = j
    end
    order = partialsortperm(dists, 1:nedges)
    return Is[order], Js[order]
end

function build_qp(n_vars::Int; seed::Int=1, avg_degree::Int=6, graph_model::Symbol=:random,
                   avg_cluster_size::Union{Nothing,Real}=nothing)
    rng = MersenneTwister(seed)
    nedges = (n_vars * avg_degree) ÷ 2
    if graph_model === :random
        Ii, Jj = random_edges(rng, n_vars, nedges)
    elseif graph_model === :geometric
        Ii, Jj = geometric_edges(rng, n_vars, nedges; avg_cluster_size=avg_cluster_size)
    else
        error("build_qp: unknown graph_model = $(repr(graph_model)); expected :random or :geometric")
    end
    keep = Ii .!= Jj
    Ii, Jj = Ii[keep], Jj[keep]
    vals = -(abs.(randn(rng, length(Ii))) .+ 0.1)
    P0 = sparse(Ii, Jj, vals, n_vars, n_vars)
    P0 = P0 + P0'
    d = vec(sum(abs, P0; dims=2)) .+ 1.0          # diagonal dominance -> SPD
    P0 = P0 - spdiagm(0 => diag(P0)) + spdiagm(0 => d)
    perm = randperm(rng, n_vars)
    P = P0[perm, perm]
    q = randn(rng, n_vars)
    A = sparse([-I(n_vars); I(n_vars)] .* 1.0)
    b = [zeros(n_vars); fill(5.0, n_vars)]
    cones = [Clarabel.NonnegativeConeT(n_vars), Clarabel.NonnegativeConeT(n_vars)]
    return P, q, A, b, cones
end

# Constructing a fresh Solver and solving it in one call keeps this @perftest
# target self-contained (no BenchmarkTools `setup=` interpolation needed).
function solve_fresh_qp(P, q, A, b, cones, settings)
    solver = Clarabel.Solver(P, q, A, b, cones, settings)
    Clarabel.solve!(solver)
    return solver
end

@perftest_config "
[general]
verbose = 3
[regression]
enabled = true
dedicated_reference_file = 'clarabel_reference_$(gethostname())_$(GRAPH_MODEL).JLD2'
"


@testset "Wrapper" begin

	@testset "Clarabel QP solve" for n_vars in [32, 64, 128, 256, 512, 1024, 2048, 2560]
        #n_vars = 256
        @info n_vars
        P, q, A, b, cones = build_qp(n_vars; graph_model=GRAPH_MODEL, avg_cluster_size=GRAPH_CLUSTER_SIZE)
        settings = Clarabel.Settings(verbose=false)

        @define_metric name="attained_gflops" units="GFLOP/s" begin
            :flop / 1e9 / :median_time
        end
        @define_metric name="l3_bandwidth" units="GBytes/s" begin
#              (:flop / 1e6) / (:bw.l3.read_write * :median_time)
               :bw.l3.read_write_volume
	end

        @regression metrics=[:median_time, :attained_gflops, :l3_bandwidth] threshold=[1.15, 0.85, 1.15] low_is_bad=[false, true, false]

	solver = @perftest samples=20 evals=1 solve_fresh_qp(P, q, A, b, cones, settings)

        # Always passes: AMD-ordered and naturally-ordered QDLDL solve the
        # exact same problem to the same answer (see README.md) -- only
        # Clarabel's performance ever regresses, never its correctness.
        @test solver.solution.status == Clarabel.SOLVED
    end

end
