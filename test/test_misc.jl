module TestMisc

using BenchmarkCI
using Test

@testset "format_period" begin
    @test BenchmarkCI.format_period(3) == "3 seconds"
    @test BenchmarkCI.format_period(125) == "2 minutes 5 seconds"
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
