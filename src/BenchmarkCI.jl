module BenchmarkCI

import CpuId
import Dates
import GitHub
import JSON
import LinearAlgebra
import Markdown
using Base64: base64decode
using Logging: ConsoleLogger
using PkgBenchmark:
    BenchmarkConfig,
    BenchmarkJudgement,
    BenchmarkResults,
    PkgBenchmark,
    baseline_result,
    export_markdown,
    target_result
using Setfield: @set
using Tar_jll: tar
using Zstd_jll: zstdmt

if VERSION < v"1.2-"
    mktempdir(f; _...) = Base.mktempdir(f)
end

include("runtimeinfo.jl")
include("gitutils.jl")

Base.@kwdef struct CIResult
    judgement::BenchmarkJudgement
    title::String = "Benchmark result"
end

const DEFAULT_WORKSPACE = ".benchmarkci"

is_in_ci(ENV = ENV) =
    lowercase(get(ENV, "CI", "false")) == "true" || haskey(ENV, "GITHUB_EVENT_PATH")

function find_manifest(project)
    dir = isdir(project) ? project : dirname(project)
    candidates = joinpath.(dir, ("JuliaManifest.toml", "Manifest.toml"))
    i = findfirst(isfile, candidates)
    i === nothing && return nothing
    return candidates[i]
end

function generate_script(default_script, project, should_resolve)
    default_script = abspath(default_script)
    project = abspath(project)
    """
    let Pkg = Base.require(Base.PkgId(
            Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"),
            "Pkg",
        ))
        Pkg.activate($(repr(project)))
        $(repr(should_resolve)) && Pkg.resolve()
        Pkg.instantiate()
    end
    include($(repr(default_script)))
    """
end

ensure_origin(::Nothing) = nothing
ensure_origin(config::BenchmarkConfig) = ensure_origin(config.id)
function ensure_origin(committish)
    if startswith(committish, "origin/")
        _, remote_branch = split(committish, "/"; limit = 2)
        cmd = `git fetch origin "+refs/heads/$remote_branch:refs/remotes/origin/$remote_branch"`
        @debug "Fetching $committish..." cmd
        run(cmd)
    end
end

function maybe_with_merged_project(f, project, pkgdir)
    project = abspath(project)
    if find_manifest(project) !== nothing
        @info "Using existing manifest file."
        return f(project, false)  # should_resolve = false
    else
        if isfile(project)
            file = project
        else
            candidates = joinpath.(project, ("JuliaProject.toml", "Project.toml"))
            i = findfirst(isfile, candidates)
            if i === nothing
                error("One of the following files must exist:\n", join(candidates, "\n"))
            end
            file = candidates[i]
        end
        return mktempdir(prefix = "BenchmarkCI_jl_") do tmp
            tmpproject = joinpath(tmp, "Project.toml")
            cp(file, tmpproject)
            code = """
            using Pkg
            Pkg.develop(Pkg.PackageSpec(path = $(repr(pkgdir))))
            """
            run(setenv(
                `$(Base.julia_cmd()) --startup-file=no --project=$tmpproject -e $code`,
                "JULIA_LOAD_PATH" => "@:@stdlib",
            ))
            @info "Using temporary project `$tmp`."
            f(tmpproject, true)  # should_resolve = true
        end
    end
end

function format_period(seconds::Real)
    seconds < 60 && return string(floor(Int, seconds), " seconds")
    minutes = floor(Int, seconds / 60)
    return string(minutes, " minutes ", floor(Int, seconds - 60 * minutes), " seconds")
end

"""
    judge()

Run `benchmarkpkg` on `target` and `baseline`.

# Keyword Arguments
- `target :: Union{Nothing, AbstractString, BenchmarkConfig} = nothing`:
  Benchmark target configuration.  Default to the checked out working tree.  A
  git commitish can be passed as a string.  `PkgBenchmark.BenchmarkConfig`
  can be used for more detailed control (see PkgBenchmark.jl manual).
- `baseline :: Union{AbstractString, BenchmarkConfig} = "origin/master"`:
  Benchmark baseline configuration.  See `target.`
- `pkgdir :: AbstractString = pwd()`: Package root directory.
- `script :: AbstractString = "\$pkgdir/benchmark/benchmarks.jl"`: The script
  that defines the `SUITE` global variable/constant.
- `project :: AbstractString = dirname(script)`: The project used to define
  and run benchmarks.
- `postprocess`, `retune`, `verbose`, `logger_factory`: Passed to
  `PkgBenchmark.benchmarkpkg`.
"""
judge(; target = nothing, baseline = "origin/master", kwargs...) =
    judge(target, baseline; kwargs...)

function judge(
    target,
    baseline = "origin/master";
    workspace = DEFAULT_WORKSPACE,
    pkgdir = pwd(),
    script = joinpath(pkgdir, "benchmark", "benchmarks.jl"),
    project = dirname(script),
    logger_factory = is_in_ci() ? ConsoleLogger : nothing,
    kwargs...,
)
    target = BenchmarkConfig(target)
    if !(baseline isa BenchmarkConfig)
        baseline = @set target.id = baseline
    end

    # Make sure `origin/master` etc. exists:
    ensure_origin(target)
    ensure_origin(baseline)

    mkpath(workspace)
    script_wrapper = abspath(joinpath(workspace, "benchmarks_wrapper.jl"))

    let metadata = Dict(
            :target => target,
            :baseline => baseline,
            :pkgdir => pkgdir,
            :script => script,
            :project => project,
        )
        open(joinpath(workspace, "metadata.json"); write = true) do io
            JSON.print(io, metadata)
        end
    end

    maybe_with_merged_project(project, pkgdir) do tmpproject, should_resolve
        cp(tmpproject, joinpath(workspace, "Project.toml"); force = true)
        tmpmanifest = something(find_manifest(tmpproject))
        cp(tmpmanifest , joinpath(workspace, "Manifest.toml"); force = true)
        write(script_wrapper, generate_script(script, tmpproject, should_resolve))
        _judge(;
            target = target,
            baseline = baseline,
            workspace = workspace,
            pkgdir = pkgdir,
            benchmarkpkg_kwargs = (;
                kwargs...,
                logger_factory = logger_factory,
                script = script_wrapper,
            ),
        )
    end
end

function noisily(f, yes::Bool = is_in_ci(); interval = 60 * 5)
    if yes
        t0 = time_ns()
        timer = Timer(interval; interval = interval) do _
            tstr = format_period(floor(Int, (time_ns() - t0) / 1e9))
            @info "$tstr passed.  Still running `judge`..."
        end
        try
            f()
        finally
            close(timer)
        end
    else
        f()
    end
end

function _judge(; target, baseline, workspace, pkgdir, benchmarkpkg_kwargs)

    noisily() do
        time_target = @elapsed group_target = PkgBenchmark.benchmarkpkg(
            pkgdir,
            target;
            resultfile = joinpath(workspace, "result-target.json"),
            benchmarkpkg_kwargs...,
        )
        @debug("`git status`", output = Text(read(`git status`, String)))
        @debug("`git diff`", output = Text(read(`git diff`, String)))
        time_baseline = @elapsed group_baseline = PkgBenchmark.benchmarkpkg(
            pkgdir,
            baseline;
            resultfile = joinpath(workspace, "result-baseline.json"),
            benchmarkpkg_kwargs...,
        )
        @info """
        Finish running benchmarks.
        * Target: $(format_period(time_target))
        * Baseline: $(format_period(time_baseline))
        """
        judgement = PkgBenchmark.judge(group_target, group_baseline)
        if is_in_ci()
            display(judgement)
        end
        return judgement
    end
end

function _loadjudge(workspace)
    group_target = PkgBenchmark.readresults(joinpath(workspace, "result-target.json"))
    group_baseline = PkgBenchmark.readresults(joinpath(workspace, "result-baseline.json"))
    return PkgBenchmark.judge(group_target, group_baseline)
end

# Used only for testing:
_loadciresult(workspace::AbstractString = DEFAULT_WORKSPACE) =
    CIResult(judgement = _loadjudge(workspace))

"""
    postjudge(; title = "Benchmark result")

Post judgement as comment.
"""
postjudge(workspace::AbstractString = DEFAULT_WORKSPACE; kwargs...) =
    postjudge(_loadjudge(workspace); kwargs...)

function postjudge(judgement::BenchmarkJudgement; title = "Benchmark result")
    event_path = get(ENV, "GITHUB_EVENT_PATH", nothing)
    if event_path !== nothing
        post_judge_github(event_path, CIResult(judgement = judgement, title = title))
        return
    end
    displayjudgement(judgement)
end

function printcommentmd(io, ciresult)
    println(io, "<details>")
    println(io, "<summary>", ciresult.title, "</summary>")
    println(io)
    printresultmd(io, ciresult)
    println(io)
    println(io)
    println(io, "</details>")
end

function printresultmd(io, ciresult)
    judgement = ciresult.judgement
    println(io, "# Judge result")
    export_markdown(io, judgement)
    println(io)
    println(io)
    println(io, "---")
    println(io, "# Target result")
    export_markdown(io, target_result(judgement))
    println(io)
    println(io)
    println(io, "---")
    println(io, "# Baseline result")
    export_markdown(io, baseline_result(judgement))
    println(io)
    println(io)
    println(io, "---")
    println(io, "# Runtime information")
    show(io, MIME"text/markdown"(), runtimeinfo())
    println(io)
    md = try
        sprint() do buffer
            show(buffer, MIME"text/markdown"(), CpuId.cpuinfo())
        end
    catch err
        @error(
            """`show(_, "text/markdown", CpuId.cpuinfo())` failed""",
            exception = (err, catch_backtrace())
        )
        nothing
    end
    md === nothing || println(io, md)
end

function printcommentjson(io, ciresult)
    comment = sprint() do io
        printcommentmd(io, ciresult)
    end
    # https://developer.github.com/v3/issues/comments/#create-a-comment
    JSON.print(io, Dict("body" => comment::AbstractString))
end

function error_on_missing_github_token()
    error("""
    Environment variable `GITHUB_TOKEN` is not set.  The workflow file
    must contain configuration such as:

        - name: Post result
          run: julia -e "using BenchmarkCI; BenchmarkCI.postjudge()"
          env:
            GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
    """)
end

function post_judge_github(event_path, ciresult)
    event = JSON.parsefile(event_path)
    url = event["pull_request"]["comments_url"]
    # https://developer.github.com/v3/activity/events/types/#pullrequestevent
    @debug "Posting to: $url"

    GITHUB_TOKEN = get(ENV, "GITHUB_TOKEN", nothing)
    GITHUB_TOKEN === nothing && error_on_missing_github_token()

    cmd = ```
    curl
    --include
    --request POST
    $url
    -H "Content-Type: application/json"
    -H "Authorization: token $GITHUB_TOKEN"
    --data @-
    ```

    response = sprint() do stdout
        open(pipeline(cmd, stdout = stdout, stderr = stderr), write = true) do io
            printcommentjson(io, ciresult)
        end
    end
    @debug "Response from GitHub" Text(response)
    @info "Comment posted."
end

"""
    pushresult(; url, branch, sshkey, title)

Push benchmark result to `branch` in `url`.

# Keyword Arguments
- `url::Union{AbstractString,Nothing} = nothing`: Repository URL.
- `branch::AbstractString = "benchmark-results"`: Branch where the
  results are pushed.
- `sshkey::Union{AbstractString,Nothing} = nothing`: Documenter.jl-style
  SSH private key (base64-encoded private key).
- `title::AbstractString = "Benchmark result"`: The title to be used in
  benchmark report.
"""
function pushresult(;
    url::Union{AbstractString,Nothing} = nothing,
    branch::AbstractString = "benchmark-results",
    sshkey::Union{AbstractString,Nothing} = nothing,
    workspace::AbstractString = DEFAULT_WORKSPACE,
    title::AbstractString = "Benchmark result",
)
    workspace = abspath(workspace)
    default_url = nothing
    repo = nothing
    if haskey(ENV, "GITHUB_TOKEN")
        sha = github_sha()
        auth = GitHub.authenticate(ENV["GITHUB_TOKEN"])
        repo = GitHub.repo(ENV["GITHUB_REPOSITORY"]; auth = auth)
        default_url = "git@github.com:$(repo.full_name).git"
    end
    if url === nothing
        default_url === nothing && error("cannot auto detect url")
        url = default_url
    end
    if sshkey === nothing
        sshkey = String(base64decode(ENV["SSH_KEY"]))
    end
    judgement = _loadjudge(workspace)
    local datadir
    GitUtils.updating(
        url,
        branch;
        sshkey = sshkey,
        commit_message = "Add: $title",
    ) do ctx
        datadir = Dates.format(Dates.now(), joinpath("yyyy", "mm", "dd", "HHMMSS"))
        mkpath(datadir)
        compress_tar(joinpath(datadir, "result.tar.zst"), workspace)
        open(joinpath(datadir, "result.md"); write = true) do io
            println(io, "# ", title)
            println(io)
            printresultmd(io, CIResult(title = title, judgement = judgement))
        end
    end
    if repo !== nothing
        status_params = Dict(
            "state" => "success",
            "context" => "benchmarkci/pushresult",
            "description" => "Benchmarks complete!",
            "target_url" =>
                "https://github.com/$(repo.full_name)/bolb/$branch/src/$datadir/result.md",
        )
        @info "Creating status" sha params = status_params
        GitHub.create_status(repo, sha; auth = auth, params = status_params)
    end
    return
end

# From `post_status` in Documenter.jl
function github_sha()
    if get(ENV, "GITHUB_EVENT_NAME", nothing) == "pull_request"
        event_path = get(ENV, "GITHUB_EVENT_PATH", nothing)
        event_path === nothing && return
        event = JSON.parsefile(event_path)
        if haskey(event, "pull_request") &&
            haskey(event["pull_request"], "head") &&
            haskey(event["pull_request"]["head"], "sha")
            return event["pull_request"]["head"]["sha"]
        end
    elseif get(ENV, "GITHUB_EVENT_NAME", nothing) == "push"
        return ENV["GITHUB_SHA"]
    end
end

function compress_tar(dest, src)
    zstdmt() do zstdmt_cmd
        tar() do tar_cmd
            proc = open(`$zstdmt_cmd -f - -o $dest`; write = true)
            try
                run(pipeline(setenv(`$tar_cmd cf - .`; dir = src); stdout = proc))
            finally
                close(proc)
                wait(proc)
            end
        end
    end
end

function decompress_tar(dest, src)
    mkpath(dest)
    zstdmt() do zstdmt_cmd
        tar() do tar_cmd
            proc = open(pipeline(`$zstdmt_cmd -d`; stdin = src); read = true)
            try
                run(pipeline(setenv(`$tar_cmd xf -`; dir = dest); stdin = proc))
            finally
                close(proc)
                wait(proc)
            end
        end
    end
end

"""
    displayjudgement()

Print result of `BenchmarkCI.judge`.
"""
displayjudgement(workspace::AbstractString = DEFAULT_WORKSPACE) =
    displayjudgement(_loadjudge(workspace))

function displayjudgement(judgement::BenchmarkJudgement)
    io = IOBuffer()
    printresultmd(io, CIResult(judgement = judgement))
    seekstart(io)
    display(Markdown.parse(io))
    display(Text("\n"))
end

runall(args...; kwargs...) = postjudge(judge(args...; kwargs...))

end # module
