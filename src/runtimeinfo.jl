"""
    runtimeinfo()

Gather information about runtime.  It returns an object that can be
`show`n using `text/plain` and `text/markdown` MIMEs.
"""
runtimeinfo() = RunTimeInfo()

function safe_lscpu()
    try
        return read(`lscpu`, String)
    catch
        return nothing
    end
end

Base.@kwdef struct RunTimeInfo
    blas_num_threads::Union{Int,Nothing} = blas_num_threads()
    blas_vendor::Symbol = blas_vendor()
    lscpu::Union{String,Nothing} = safe_lscpu()
end

function Base.show(io::IO, ::MIME"text/plain", info::RunTimeInfo)
    buffer = IOBuffer()
    show(buffer, MIME"text/markdown"(), info)
    seekstart(buffer)
    show(io, MIME"text/plain"(), Markdown.parse(buffer))
end

function Base.show(io::IO, ::MIME"text/markdown", info::RunTimeInfo)
    println(io, "| Runtime Info | |")
    println(io, "|:--|:--|")
    println(io, "| BLAS #threads | ", something(info.blas_num_threads, "unknown"), " |")
    println(io, "| `BLAS.vendor()` | `", info.blas_vendor, "` |")
    println(io, "| `Sys.CPU_THREADS` | ", Sys.CPU_THREADS, " |")
    # Hiding `nthreads` ATM as it can be misleading when it is set via
    # `BenchmarkConfig`:
    # println(io, "| `Threads.nthreads()` | ", Threads.nthreads(), " |")
    if info.lscpu !== nothing
        println(io)
        println(io, "`lscpu` output:")
        println(io)
        for line in split(info.lscpu, "\n")
            println(io, "    ", line)
        end
    end
end


if isdefined(LinearAlgebra.BLAS, :get_config)
    blas_vendor() = :libblastrampoline  # TODO:
else
    blas_vendor() = LinearAlgebra.BLAS.vendor()
end


"""
    blas_num_threads() :: Union{Int, Nothing}

Get the number of threads BLAS is using.

Taken from:
https://github.com/JuliaLang/julia/blob/v1.3.0/stdlib/Distributed/test/distributed_exec.jl#L999-L1019

See also: https://stackoverflow.com/a/37516335
"""
blas_num_threads() =
    VERSION < v"1.6" ? blas_num_threads_jl10() : LinearAlgebra.BLAS.get_num_threads()

function blas_num_threads_jl10()
    blas = LinearAlgebra.BLAS.vendor()
    # Wrap in a try to catch unsupported blas versions
    try
        if blas == :openblas
            return ccall((:openblas_get_num_threads, Base.libblas_name), Cint, ())
        elseif blas == :openblas64
            return ccall((:openblas_get_num_threads64_, Base.libblas_name), Cint, ())
        elseif blas == :mkl
            return ccall((:MKL_Get_Max_Num_Threads, Base.libblas_name), Cint, ())
        end

        # OSX BLAS looks at an environment variable
        if Sys.isapple()
            return tryparse(Cint, get(ENV, "VECLIB_MAXIMUM_THREADS", "1"))
        end
    catch
    end

    return nothing
end
