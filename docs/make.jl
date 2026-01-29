using PerfTest
using Documenter
using DocExtensions
using DocExtensions.DocumenterExtensions

const DOCSRC      = joinpath(@__DIR__, "src")
const DOCASSETS   = joinpath(DOCSRC, "assets")
const EXAMPLEROOT = joinpath(@__DIR__, "..", "examples")

DocMeta.setdocmeta!(PerfTest, :DocTestSetup, :(using PerfTest); recursive=true)


@info "Copy examples folder to assets..."
mkpath(DOCASSETS)
cp(EXAMPLEROOT, joinpath(DOCASSETS, "examples"); force=true)


@info "Preprocessing .MD-files..."
include("reflinks.jl")
MarkdownExtensions.expand_reflinks(reflinks; rootdir=DOCSRC)


@info "Building documentation website using Documenter.jl..."
makedocs(;
    modules  = [PerfTest, PerfTest.Configuration, PerfTest.BencherInterface],
    authors  = "Daniel Sergio Vega Rodriguez, Samuel Omlin, and contributors",
    repo     = "https://github.com/JuliaPerf/PerfTest.jl/blob/{commit}{path}#{line}",
    sitename = "PerfTest.jl",
    format   = Documenter.HTML(;
        prettyurls       = true, #get(ENV, "CI", "false") == "true",
        canonical        = "https://JuliaPerf.github.io/PerfTest.jl",
        collapselevel    = 1,
        sidebar_sitename = true,
        edit_link        = "master",
        #assets           = [asset("https://img.shields.io/github/stars/JuliaPerf/PerfTest.jl.svg", class = :ico)],
        #warn_outdated    = true,
    ),
    pages   = [
        "Introduction"  => "index.md",
        "Usage"         => "usage.md",
        "Macros"        => "macros.md",
        "Examples"      => [hide("..." => "examples.md"),
                            "examples/mock2-memorythroughput.md",
                            "examples/mock3-roofline.md",
                            "examples/mock4-recursive.md",
                           ],
        "Limitations"   => "limitations.md",
        "API reference" => "api.md",
    ],
)


@info "Deploying docs..."
deploydocs(;
    repo         = "github.com/JuliaPerf/PerfTest.jl",
    push_preview = true,
    devbranch    = "master",
)
