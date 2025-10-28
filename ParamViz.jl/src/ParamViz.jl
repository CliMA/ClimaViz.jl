module ParamViz

using WGLMakie
using Bonito
using SparseArrays
using Statistics
using Unitful: R, L, mol, K, kJ, °C, m, g, cm, hr, mg, s, μmol
using UnitfulMoles: molC
using Unitful, UnitfulMoles
@compound CO₂

include("struct_and_functions.jl")
include("generate_fig.jl")

function __init__()
    Unitful.register(ParamViz)
end

end 
