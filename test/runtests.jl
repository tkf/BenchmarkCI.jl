import JSON
using BenchmarkCI
using Test

@testset "BenchmarkCI.jl" begin
    @test BenchmarkCI.format_period(3) == "3 seconds"
    @test BenchmarkCI.format_period(125) == "2 minutes 5 seconds"

    mktempdir(prefix = "BenchmarkCI_jl_test_") do dir
        cd(dir) do
            run(`git clone https://github.com/tkf/BenchmarkCIExample.jl`)
            cd("BenchmarkCIExample.jl")

            # Run a test without $GITHUB_TOKEN
            function runtests(target)
                @testset "$target" begin
                    withenv("CI" => "true", "GITHUB_EVENT_PATH" => nothing) do
                        BenchmarkCI.runall(target = target)
                        BenchmarkCI.runall(target = target, project = "benchmark/Project.toml")
                    end
                end
            end

            runtests("testcase/0000-with-manifest")
            runtests("testcase/0001-without-manifest")

            err = nothing
            @test try
                BenchmarkCI.judge(script = joinpath(dir, "nonexisting", "script.jl"))
                false
            catch err
                true
            end
            @test occursin("One of the following files must exist:", sprint(showerror, err))

            ciresult = BenchmarkCI._loadciresult()

            io = IOBuffer()
            BenchmarkCI.printcommentjson(io, ciresult)
            seekstart(io)
            dict = JSON.parse(io)
            @test dict["body"] isa String
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
