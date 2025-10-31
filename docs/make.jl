using ClimaViz
using Documenter
using DocumenterVitepress

# Set up DocMeta to enable docstring processing
DocMeta.setdocmeta!(ClimaViz, :DocTestSetup, :(using ClimaViz); recursive=true)

makedocs(;
    modules=[ClimaViz],
    authors="AlexisRenchon <a.renchon@gmail.com>",
    sitename="ClimaViz.jl",
    format=DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/CliMA/ClimaViz.jl",
        devbranch = "main",
        devurl = "dev",
    ),
    pages=[
        "Home" => "index.md",
        "API Reference" => "api.md",
        "Extensions" => "extensions.md",
        "Examples" => "examples.md",
    ],
    warnonly = [:missing_docs],
)

deploydocs(;
    repo="github.com/CliMA/ClimaViz.jl",
    target = "build", # this is where Vitepress stores its output
    branch = "gh-pages",
    devbranch = "main",
    push_preview = true,
)
