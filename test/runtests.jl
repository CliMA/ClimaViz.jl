using Test
using ClimaViz

@testset "ClimaViz.jl" begin
    include("test_utils.jl")
    include("test_cache.jl")
end
