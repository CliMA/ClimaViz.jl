# Launch the heterotrophic respiration (DAMM) dashboard on localhost
# Run with: julia --project=examples examples/paramviz/hetero_resp_local.jl

using ClimaViz
using Bonito
using Unitful, UnitfulMoles

dashboard_paramviz("damm_model")

wait()
