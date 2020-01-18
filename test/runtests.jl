using BenchmarkCI
using Test

@testset "BenchmarkCI.jl" begin
    mktempdir(prefix="BenchmarkCI_jl_test_") do dir
        cd(dir) do
            run(`git clone https://github.com/tkf/BenchmarkCIExample.jl`)
            cd("BenchmarkCIExample.jl")
            withenv("JULIA_LOAD_PATH" => "@:@stdlib") do
                BenchmarkCI.runall()
            end
        end
    end
end
