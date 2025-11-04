module ClimaViz

import ClimaAnalysis
import Bonito
import Statistics
import Dates
import FileIO
using WGLMakie
using GeoMakie

include("utils.jl")
include("figures.jl")
include("events.jl")
include("layout.jl")
include("dashboard.jl")

export dashboard

end # module ClimaViz
