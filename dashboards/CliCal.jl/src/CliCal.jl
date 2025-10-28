module CliCal

import EnsembleKalmanProcesses as EKP
import GeoMakie as GM
using WGLMakie
using Bonito
using JLD2

using Statistics
using Printf
using LinearAlgebra

include("fun_and_slice.jl")
include("update_fig.jl")
include("layout.jl")
include("make_app.jl")

end # module CliCal
