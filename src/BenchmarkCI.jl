module BenchmarkCI

import CpuId
import JSON
import LinearAlgebra
import Markdown
using PkgBenchmark:
    BenchmarkConfig,
    BenchmarkJudgement,
    BenchmarkResults,
    PkgBenchmark,
    baseline_result,
    export_markdown,
    target_result
using Setfield: @set

include("runtimeinfo.jl")

Base.@kwdef struct CIResult
    judgement::BenchmarkJudgement
    title::String = "Benchmark result"
end

const DEFAULT_WORKSPACE = ".benchmarkci"

is_in_ci(ENV = ENV) =
    lowercase(get(ENV, "CI", "false")) == "true" || haskey(ENV, "GITHUB_EVENT_PATH")

function generate_script(default_script, project)
    default_script = abspath(default_script)
    project = abspath(project)
    """
    let Pkg = Base.require(Base.PkgId(
            Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"),
            "Pkg",
        ))
        Pkg.activate($(repr(project)))
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

judge(; target = nothing, baseline = "origin/master", kwargs...) =
    judge(target, baseline; kwargs...)

function judge(
    target,
    baseline = "origin/master";
    workspace = DEFAULT_WORKSPACE,
    pkg = pwd(),
    script = joinpath(pkg, "benchmark", "benchmarks.jl"),
    project = dirname(script),
    progressoptions = is_in_ci() ? (dt = 60 * 9.0,) : NamedTuple(),
)
    target = BenchmarkConfig(target)
    if !(baseline isa BenchmarkConfig)
        baseline = @set target.id = baseline
    end

    mkpath(workspace)
    script_wrapper = abspath(joinpath(workspace, "benchmarks_wrapper.jl"))
    write(script_wrapper, generate_script(script, project))

    # Make sure `origin/master` etc. exists:
    ensure_origin(target)
    ensure_origin(baseline)

    group_target = PkgBenchmark.benchmarkpkg(
        pkg,
        target,
        progressoptions = progressoptions,
        resultfile = joinpath(workspace, "result-target.json"),
        script = script_wrapper,
    )
    @debug("`git status`", output = Text(read(`git status`, String)))
    group_baseline = PkgBenchmark.benchmarkpkg(
        pkg,
        baseline,
        progressoptions = progressoptions,
        resultfile = joinpath(workspace, "result-baseline.json"),
        script = script_wrapper,
    )
    judgement = PkgBenchmark.judge(group_target, group_baseline)
    if is_in_ci()
        display(judgement)
    end
    return judgement
end

function _loadjudge(workspace)
    group_target = PkgBenchmark.readresults(joinpath(workspace, "result-target.json"))
    group_baseline = PkgBenchmark.readresults(joinpath(workspace, "result-baseline.json"))
    return PkgBenchmark.judge(group_target, group_baseline)
end

"""
    postjudge()

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
    @debug "Response from GitHub" response
    @info "Comment posted."
end

displayjudgement(workspace::AbstractString = DEFAULT_WORKSPACE) =
    displayjudgement(_loadjudge(workspace))

function displayjudgement(judgement::BenchmarkJudgement)
    io = IOBuffer()
    printresultmd(io, CIResult(judgement = judgement))
    seekstart(io)
    display(Markdown.parse(io))
end

runall(args...; kwargs...) = postjudge(judge(args...; kwargs...))

end # module
