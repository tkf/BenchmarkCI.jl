module TestUpdating

using Test
using BenchmarkCI: GitUtils

function setup_dummy_user()
    run(`git config user.email "DUMMY@users.noreply.github.com"`)
    run(`git config user.name DUMMY`)
end

function init_random_repo(dir, branch)
    mkpath(dir)
    cd(dir) do
        run(`git init .`)
        setup_dummy_user()

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

@testset "_push_with_retry" begin
    mktempdir() do dir
        branch = "somebranch"
        origin = joinpath(dir, "origin")
        init_random_repo(origin, branch)
        url = "file://" * abspath(origin)

        workdir = joinpath(dir, "workdir")
        run(`git clone $url $workdir`)
        cd(workdir) do
            setup_dummy_user()
        end

        # Advance `origin`
        cd(origin) do
            run(`git checkout $branch`)
            write("file-1", "hello")
            run(`git add .`)
            run(`git commit --message "Add file-1"`)
            run(`git checkout -`)
        end

        cd(workdir) do
            # Advance local `workdir`:
            write("file-2", "hello")
            run(`git add .`)
            run(`git commit --message "Add file-2"`)

            logs, = Test.collect_test_logs() do
                GitUtils._push_with_retry(args -> `git $args`, branch)
            end
            all_messages = join((l.message for l in logs), "\n")
            @test occursin("retrying", all_messages)
        end
    end
end

end  # module
