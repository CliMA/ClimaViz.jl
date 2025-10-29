# ClimaViz Extensions

This directory contains Julia package extensions for ClimaViz.jl. Extensions are conditionally loaded only when their required dependencies are available.

## CliCalExt

The CliCal extension provides a dashboard for visualizing calibration results from EnsembleKalmanProcesses (EKI).

**Trigger packages:**
- `EnsembleKalmanProcesses`
- `JLD2`

**Usage:**
```julia
using ClimaViz
using EnsembleKalmanProcesses, JLD2  # This triggers the CliCalExt extension

# The extension is now loaded automatically
using ClimaViz.CliCalExt  # Access extension functionality
```

**Exported functions:**
- `makeapp(path_to_eki_file)` - Create the calibration dashboard app
- `layout(...)` - Layout function for the dashboard
- `update_fig(...)` - Update figure function
- `RMSE(x, z)` - Root mean square error calculation

## ParamVizExt

The ParamViz extension provides tools for visualizing parameterizations.

**Trigger packages:**
- `Unitful`
- `UnitfulMoles`

**Usage:**
```julia
using ClimaViz
using Unitful, UnitfulMoles  # This triggers the ParamVizExt extension

# The extension is now loaded automatically
using ClimaViz.ParamVizExt  # Access extension functionality
```

**Exported functions:**
- `webapp(parameterisation, inputs, output)` - Create the parameter visualization web app
- `param_dashboard(...)` - Create the parameter dashboard
- Various helper functions for parameter visualization

## Migration from Standalone Modules

Previously, CliCal.jl and ParamViz.jl were standalone modules in the `dashboards/` directory. They have been converted to Julia package extensions without changing their core functionality.

The main difference is that instead of being separate packages, they are now extensions of ClimaViz that load automatically when their dependencies are available.
