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
        repo = "https://github.com/CliMA/ClimaViz.jl",
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

DocumenterVitepress.deploydocs(;
    repo="https://github.com/CliMA/ClimaViz.jl",
    push_preview = true,
)
