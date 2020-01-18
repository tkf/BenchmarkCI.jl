using BenchmarkCI
using Test

@testset "BenchmarkCI.jl" begin
    mktempdir(prefix = "BenchmarkCI_jl_test_") do dir
        cd(dir) do
            run(`git clone https://github.com/tkf/BenchmarkCIExample.jl`)
            cd("BenchmarkCIExample.jl")

            # Run a test without $GITHUB_TOKEN
            withenv(
                "JULIA_LOAD_PATH" => "@:@stdlib",
                "CI" => "true",
                "GITHUB_EVENT_PATH" => nothing,
            ) do
                BenchmarkCI.runall()
            end
        end
    end
end
