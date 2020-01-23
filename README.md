# BenchmarkCI.jl

![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
[![CI Status][ci-img]][ci-url]
[![codecov.io][codecov-img]][codecov-url]

BenchmarkCI.jl provides an easy way to run benchmark suite via GitHub
Actions.  It only needs a minimal setup if there is a benchmark suite
declared by
[BenchmarkTools.jl](https://github.com/JuliaCI/BenchmarkTools.jl) /
[PkgBenchmark.jl](https://github.com/JuliaCI/PkgBenchmark.jl) API.

## Setup

BenchmarkCI.jl requires PkgBenchmark.jl to work.  See
[Defining a benchmark suite · PkgBenchmark.jl](https://juliaci.github.io/PkgBenchmark.jl/stable/define_benchmarks/)
for more information.  BenchmarkCI.jl also requires a Julia project
`benchmark/Project.toml` that is used for running the benchmark.

### Setup with `benchmark/Manifest.toml`

Create (say) `.github/workflows/benchmark.yml` with the following
configuration if `benchmark/Manifest.toml` is checked in to the
project git repository:

```yaml
name: Run benchmarks

on:
  pull_request:

jobs:
  Benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: julia-actions/setup-julia@latest
        with:
          version: 1.3
      - name: Install dependencies
        run: julia -e 'using Pkg; pkg"add PkgBenchmark https://github.com/tkf/BenchmarkCI.jl"'
      - name: Run benchmarks
        run: julia -e "using BenchmarkCI; BenchmarkCI.judge()"
      - name: Post results
        run: julia -e "using BenchmarkCI; BenchmarkCI.postjudge()"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Note that `benchmark/Project.toml` must include parent project as
well.  Run `dev ..` in `benchmark/` directory to add it:

```
shell> cd ~/.julia/dev/MyProject/

shell> cd benchmark/

(@v1.x) pkg> activate .
Activating environment at `~/.julia/dev/MyProject/benchmark/Project.toml`

(benchmark) pkg> dev ..
```

### Setup without `benchmark/Manifest.toml`

Create (say) `.github/workflows/benchmark.yml` with the following
configuration if `benchmark/Manifest.toml` is _not_ checked in to the
project git repository:

```yaml
name: Run benchmarks

on:
  pull_request:

jobs:
  Benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: julia-actions/setup-julia@latest
        with:
          version: 1.3
      - name: Install dependencies
        run: julia -e 'using Pkg; pkg"add PkgBenchmark https://github.com/tkf/BenchmarkCI.jl"'
      - name: Run benchmarks
        run: julia -e "using BenchmarkCI; BenchmarkCI.judge()"
      - name: Post results
        run: julia -e "using BenchmarkCI; BenchmarkCI.postjudge()"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Additional setup (recommended)

It is recommended to add following two lines in `.gitignore`:

```
/.benchmarkci
/benchmark/*.json
```

This is useful for running BenchmarkCI locally (see below).

## Running BenchmarkCI interactively

```
shell> cd ~/.julia/dev/MyProject/

julia> using BenchmarkCI

julia> BenchmarkCI.judge()
...

julia> BenchmarkCI.displayjudgement()
...
```

[ci-img]: https://github.com/tkf/BenchmarkCI.jl/workflows/Run%20tests/badge.svg
[ci-url]: https://github.com/tkf/BenchmarkCI.jl/actions?query=workflow%3A%22Run+tests%22
[codecov-img]: http://codecov.io/github/tkf/BenchmarkCI.jl/coverage.svg?branch=master
[codecov-url]: http://codecov.io/github/tkf/BenchmarkCI.jl?branch=master
