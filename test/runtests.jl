using Test
using ClimaViz
import ClimaAnalysis

@testset "ClimaViz.jl" begin
    include("test_utils.jl")
    include("test_cache.jl")
    include("test_coupler.jl")
end
