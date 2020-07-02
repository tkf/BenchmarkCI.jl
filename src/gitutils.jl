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
                _push_with_retry(git, branch)
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
            _push_with_retry(git, branch)
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

printable(cmd::Cmd) = Cmd(cmd.exec::Vector{String})

function saferun(cmd::Cmd; log = true)
    @info "Executing $(printable(cmd))..."
    try
        return run(cmd)
    catch err
        log && @info "Failed to run: $(printable(cmd))"
        @debug("Failed to run: $(printable(cmd))", exception = (err, catch_backtrace()),)
        return nothing
    end
end

function _push_with_retry(git, branch; timeout = 5 * 60, tries = 10)
    t0 = time_ns()

    push_cmd = git(`push origin "HEAD:refs/heads/$branch"`)
    for i in 1:tries
        if  saferun(push_cmd; log = false) !== nothing
            @info "Successfully pushed branch `$branch` to remote."
            return
        end

        if (time_ns() - t0) / 1e9 > timeout
            @info "Timeout ($timeout seconds) reached."
            break
        end
        @info "$i-th $(printable(push_cmd)) failed; retrying...."

        saferun(git(`fetch origin $branch`)) == nothing && break
        saferun(git(`merge --no-edit "origin/$branch"`)) == nothing && break
    end
    error("Failed to: $(printable(push_cmd))")
end

end  # module
