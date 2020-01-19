"""
    runtimeinfo()

Gather information about runtime.  It returns an object that can be
`show`n using `text/plain` and `text/markdown` MIMEs.
"""
runtimeinfo() = RunTimeInfo()

Base.@kwdef struct RunTimeInfo
    blas_num_threads::Union{Int,Nothing} = blas_num_threads()
    blas_vendor::Symbol = LinearAlgebra.BLAS.vendor()
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
    println(io, "| `Threads.nthreads()` | ", Threads.nthreads(), " |")
end


"""
    blas_num_threads() :: Union{Int, Nothing}

Get the number of threads BLAS is using.

Taken from:
https://github.com/JuliaLang/julia/blob/v1.3.0/stdlib/Distributed/test/distributed_exec.jl#L999-L1019

See also: https://stackoverflow.com/a/37516335
"""
function blas_num_threads()
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
