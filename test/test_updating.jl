module TestUpdating

using Test
using BenchmarkCI: GitUtils

function init_random_repo(dir, branch)
    mkpath(dir)
    cd(dir) do
        run(`git init .`)

        run(`git config user.email "DUMMY@users.noreply.github.com"`)
        run(`git config user.name DUMMY`)

        run(`git checkout -b $branch`)
        write("README.txt", "hello")
        run(`git add .`)
        run(`git commit --message "First commit"`)
        run(`git checkout -b $branch.0`)
    end
end

@testset "updating" begin
    mktempdir() do dir
        branch = "somebranch"
        origin = joinpath(dir, "origin")
        init_random_repo(origin, branch)
        url = "file://" * abspath(origin)

        GitUtils.updating(url, branch) do ctx
            write("spam.txt", "hello")
        end
        cd(origin) do
            run(`git checkout $branch`)
            @test read("spam.txt", String) == "hello"
            run(`git checkout -`)
        end

        GitUtils.updating(url, branch) do ctx
            write("spam.txt", "hello hello")
        end
        cd(origin) do
            run(`git checkout $branch`)
            @test read("spam.txt", String) == "hello hello"
            run(`git checkout -`)
        end
    end
end

@testset "prepare_ssh_command" begin
    mktempdir() do dir
        @test occursin(dir, GitUtils.prepare_ssh_command(dir, "dummy key"))
    end
end

end  # module
