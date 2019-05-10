using Documenter
using StateSpace

makedocs(
    sitename = "StateSpace",
    format = Documenter.HTML(),
    modules = [StateSpace],
    pages = ["Documentation" => "index.md",
             "Interface" => "interface.md",
             "Examples" => [joinpath("examples",x) for x in readdir("docs/src/examples") if endswith(x, "md")]
            ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    deps   = Deps.pip("mkdocs", "python-markdown-math"),
    repo   = "github.com/npsm/StateSpace.jl.git",
)
