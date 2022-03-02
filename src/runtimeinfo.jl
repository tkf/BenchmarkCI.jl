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
    blas_vendor::Symbol = LinearAlgebra.BLAS.vendor()
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


"""
    blas_num_threads() :: Union{Int, Nothing}

Get the number of threads BLAS is using.

Taken from:
https://github.com/JuliaLang/julia/blob/v1.3.0/stdlib/Distributed/test/distributed_exec.jl#L999-L1019

See also: https://stackoverflow.com/a/37516335
"""
blas_num_threads() = LinearAlgebra.BLAS.get_num_threads()
