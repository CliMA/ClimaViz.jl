module ParamVizExt

import ClimaViz
using ClimaViz: Drivers, Parameters, Constants, Inputs, Output
import ClimaViz: parameterisation, webapp, param_dashboard, dashboard_paramviz

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
include("builtin_models.jl")

function __init__()
    Unitful.register(ParamVizExt)
end

end
