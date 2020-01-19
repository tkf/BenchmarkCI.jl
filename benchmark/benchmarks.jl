using BenchmarkTools

SUITE = BenchmarkGroup()
SUITE["sum"] = @benchmarkable sum($(randn(10_000)))
