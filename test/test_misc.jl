module TestMisc

import LinearAlgebra
using BenchmarkCI
using BenchmarkCI: as_https, as_target_url
using Test

@testset "versionof" begin
    @test (@test_logs (:error,) BenchmarkCI.versionof(Base)) === nothing
    @test (@test_logs (:error,) BenchmarkCI.versionof(LinearAlgebra)) === nothing
    @test (@test_logs (:error,) BenchmarkCI.versionof(LinearAlgebra.BLAS)) === nothing
end

@testset "format_period" begin
    @test BenchmarkCI.format_period(3) == "3 seconds"
    @test BenchmarkCI.format_period(125) == "2 minutes 5 seconds"
end

@testset "as_https" begin
    @test as_https("git@github.com:USER/REPO.git") === "https://github.com/USER/REPO"
    @test as_https("git@github.com:USER/REPO") === "https://github.com/USER/REPO"
    @test as_https("git@github.com:USER/REPO.jl.git") === "https://github.com/USER/REPO.jl"
    @test as_https("git@github.com:USER/REPO.jl") === "https://github.com/USER/REPO.jl"
    @test as_https("spam") === nothing
end

@testset "as_target_url" begin
    @test as_target_url(
        "git@github.com:USER/REPO.git",
        "benchmark-results",
        "2020/07/27/023806",
    ) === "https://github.com/USER/REPO/blob/benchmark-results/2020/07/27/023806/result.md"
    @test as_target_url("spam", "benchmark-results", "2020/07/27/023806") === nothing
end

@testset "error_on_missing_github_token" begin
    err = nothing
    @test try
        BenchmarkCI.error_on_missing_github_token()
        false
    catch err
        true
    end
    @test occursin("`GITHUB_TOKEN` is not set", sprint(showerror, err))
end

@testset "compress_tar" begin
    mktempdir() do dir
        srcdir = joinpath(dir, "src")
        mkdir(srcdir)
        write(joinpath(srcdir, "README.md"), "hello")

        tarfile = joinpath(dir, "dest.tar.zst")
        BenchmarkCI.compress_tar(tarfile, srcdir)

        @test isfile(tarfile)

        destdir = joinpath(dir, "dest")
        BenchmarkCI.decompress_tar(destdir, tarfile)
        @test read(joinpath(destdir, "README.md"), String) == "hello"
    end
end

end  # module
