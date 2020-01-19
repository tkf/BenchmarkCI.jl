using BenchmarkCI
using Test

@testset "BenchmarkCI.jl" begin
    mktempdir(prefix = "BenchmarkCI_jl_test_") do dir
        cd(dir) do
            run(`git clone https://github.com/tkf/BenchmarkCIExample.jl`)
            cd("BenchmarkCIExample.jl")

            # Run a test without $GITHUB_TOKEN
            withenv("CI" => "true", "GITHUB_EVENT_PATH" => nothing) do
                BenchmarkCI.runall()
            end
        end
    end

    err = nothing
    @test try
        BenchmarkCI.error_on_missing_github_token()
        false
    catch err
        true
    end
    @test occursin("`GITHUB_TOKEN` is not set", sprint(showerror, err))
end
