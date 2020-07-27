using Documenter
using BenchmarkCI

makedocs(;
    sitename = "BenchmarkCI",
    format = Documenter.HTML(),
    modules = [BenchmarkCI],
)

deploydocs(;
    repo = "github.com/tkf/BenchmarkCI.jl",
    push_preview = true,
)
