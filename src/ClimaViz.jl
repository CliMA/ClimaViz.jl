module ClimaViz

import ClimaAnalysis
import Bonito
import Statistics
import Dates
import FileIO
import Random
using WGLMakie
using GeoMakie

include("utils.jl")
include("figures.jl")
include("events.jl")
include("layout.jl")
include("dashboard.jl")
include("paramviz.jl")

export dashboard
export Drivers, Parameters, Constants, Inputs, Output
export parameterisation, webapp, param_dashboard, dashboard_paramviz

end # module ClimaViz
