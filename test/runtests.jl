using Test
using PerfTest

excludedfiles = Set{String}([
])

if !(PerfTest.Configuration.load_config() isa Nothing)

    @info "This may take a couple of minutes..."
    exename   = joinpath(Sys.BINDIR, Base.julia_exename())
    testdir   = pwd()
    istest(f) = endswith(f, ".jl") && startswith(basename(f), "t")
    testfiles = sort(filter(istest, vcat([joinpath.(root, files) for (root, dirs, files) in walkdir(testdir)]...)))

    _nfail = 0
    printstyled("Testing package PerfTest.jl\n"; bold=true, color=:white)

    for f in testfiles
        println("")
        if f ∈ excludedfiles
            println("Test Skip:")
            println("$f")
            continue
        end
        try
            run(`$exename -O3 --startup-file=no $(joinpath(testdir, f))`)
        catch ex
            _nfail += 1
        end
    end

    rm(".perftest_logs", recursive=true, force=true)
    rm(".perftests", recursive=true,force=true)

    if _nfail == 0
    else
        printstyled("\n$nfail test(s) failed.\n"; bold=true, color=:red)
    end
end