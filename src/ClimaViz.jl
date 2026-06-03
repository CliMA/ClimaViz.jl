module ClimaViz

import ClimaAnalysis
import Bonito
import Statistics
import Dates
using Dates: Day, Hour
import FileIO
import Random
using WGLMakie
using GeoMakie

include("utils.jl")
include("benchmark.jl")
include("cache.jl")
include("figures.jl")
include("events.jl")
include("layout.jl")
include("dashboard.jl")
include("paramviz.jl")

export dashboard
export precompute_dashboard_cache
export Drivers, Parameters, Constants, Inputs, Output
export parameterisation, webapp, param_dashboard, dashboard_paramviz

end # module ClimaViz
