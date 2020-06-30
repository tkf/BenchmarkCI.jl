module GitUtils

"""
    updating(f, url, branch; [sshkey, commit_message])

Checkout `branch` from `url` run `f(ctx)` while `cd`ing into the local
clone and then push any changes made.
"""
function updating(
    f,
    url::AbstractString,
    branch::AbstractString;
    sshkey::Union{AbstractString,Nothing} = nothing,
    commit_message::AbstractString = "",
)
    mktempdir() do tmpd
        repodir = joinpath(tmpd, "repo")
        if sshkey !== nothing
            sshdir = joinpath(tmpd, "ssh")
            GIT_SSH_COMMAND = prepare_ssh_command(sshdir, sshkey)
            git = function git_with_ssh(c)
                env = copy(ENV)
                env["GIT_SSH_COMMAND"] = GIT_SSH_COMMAND
                setenv(`git $c`, env)
            end
        else
            git = c -> `git $c`
        end

        try
            run(git(`clone --branch=$branch --depth=1 $url $repodir`))
            cd(repodir) do
                setup_git_user()
            end
        catch
            run(git(`init $repodir`))
            cd(repodir) do
                setup_git_user()
                run(git(`remote add origin $url`))
                run(git(`checkout -b $branch`))
                run(git(`commit --allow-empty --allow-empty-message --message=""`))
                run(git(`push origin $branch`))
            end
        end
        cd(repodir) do
            f((git = git,))
        end
        cd(repodir) do
            if !isempty(read(`git status --porcelain=v1`))
                @info(
                    "Committing uncommitted files.",
                    var"git status --short" = Text(read(`git status --short`, String)),
                )
                run(git(`add --all`))
                run(git(`commit --allow-empty-message --message $commit_message`))
            end
            run(git(`push origin $branch`))
        end
    end
end

function prepare_ssh_command(sshdir::AbstractString, sshkey::AbstractString)
    mkpath(sshdir)
    chmod(sshdir, 0o700)

    keyfile = joinpath(sshdir, "key")
    write(keyfile, "")
    chmod(keyfile, 0o600)
    write(keyfile, sshkey)

    return "ssh -i $keyfile"
end

function setup_git_user()
    GITHUB_ACTOR = get(ENV, "GITHUB_ACTOR", nothing)
    GITHUB_ACTOR === nothing && return
    # WARNING: This function is run via tests. Do NOT use `--global`.
    run(`git config user.email "$GITHUB_ACTOR@users.noreply.github.com"`)
    run(`git config user.name $GITHUB_ACTOR`)
end

end  # module
