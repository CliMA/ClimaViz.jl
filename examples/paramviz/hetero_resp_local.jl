# Launch the heterotrophic respiration (DAMM) dashboard on localhost
# Run with: julia --project=examples examples/paramviz/hetero_resp_local.jl

using ClimaViz
using Bonito
using Unitful, UnitfulMoles

include("hetero_resp.jl")

Rh_app = Rh_app_f()
Rh_app = Rh_app_f() # need to run twice for unicode character... (bug)

server = Server("127.0.0.1", 9384)
route!(server, "/" => Rh_app)

println("Heterotrophic respiration dashboard running at http://127.0.0.1:9384")

wait()
