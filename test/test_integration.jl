module TestIntegration

import JSON
using BenchmarkCI
using BenchmarkCI: mktempdir, versionof
using Dates: DateTime
using Test

function check_workspace(workspace = BenchmarkCI.DEFAULT_WORKSPACE)
    @test isfile(joinpath(workspace, "Project.toml"))
    @test isfile(joinpath(workspace, "Manifest.toml"))
    metadata = JSON.parsefile(joinpath(workspace, "metadata.json"))
    run_info = JSON.parsefile(joinpath(workspace, "run_info.json"))
    @test metadata["BenchmarkCI"]["versions"]["BenchmarkCI"] ==
          string(versionof(BenchmarkCI))
    @test metadata["BenchmarkCI"]["format_version"]::Int < 0
    @test VersionNumber(metadata["target_julia_info"]["VERSION"]) == VERSION
    @test metadata["target_julia_info"]["Sys"]["WORD_SIZE"] == Sys.WORD_SIZE
    @test metadata["cpu_info"]["cpubrand"] isa AbstractString
    @testset for side in ["target", "baseline"]
        d = run_info[side]
        @test DateTime(d["start_date"]) isa Any
        @test DateTime(d["end_date"]) isa Any
        @test d["elapsed_time"]::Real > 0
        @test length(d["git_tree_sha1"]::AbstractString) == 40
        @test length(d["git_commit_sha1"]::AbstractString) == 40
        @test length(d["git_tree_sha1_benchmark"]::AbstractString) == 40
        @test length(d["git_tree_sha1_src"]::AbstractString) == 40
    end
end

@testset "BenchmarkCI.jl" begin
    function flushall()
        flush(stderr)
        flush(stdout)
    end

    function printlns(n)
        flushall()
        for _ in 1:n
            println()
        end
        flushall()
    end

    mktempdir(prefix = "BenchmarkCI_jl_test_") do dir
        cd(dir) do
            run(`git clone https://github.com/tkf/BenchmarkCIExample.jl`)
            cd("BenchmarkCIExample.jl")

            # Run a test without $GITHUB_TOKEN
            function runtests(target)
                printlns(2)
                @info "Testing with target = $target"
                flushall()

                @testset "$target" begin
                    run(`git checkout $target`)
                    run(`git clean --force -xd`)
                    withenv("CI" => "true", "GITHUB_EVENT_PATH" => nothing) do
                        @testset "default" begin
                            BenchmarkCI.runall()
                            check_workspace()
                        end
                        @testset "project = benchmark/Project.toml" begin
                            BenchmarkCI.runall(project = "benchmark/Project.toml")
                            check_workspace()
                        end
                    end
                end
            end

            runtests("testcase/0000-with-manifest")
            runtests("testcase/0001-without-manifest")
            printlns(2)

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

            @testset "kwargs pass-through" begin
                @info "Testing with `BenchmarkCI.judge(retune = true)`"
                @test BenchmarkCI.judge(retune = true) isa Any
                printlns(2)
            end
        end
    end
end

end  # module
