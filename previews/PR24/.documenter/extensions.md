
# Extensions {#Extensions}

ClimaViz provides several extensions for specialized visualization tasks.

## ParamViz Extension {#ParamViz-Extension}

ParamViz allows you to visualize climate parameterizations. This extension is loaded when you have both `Unitful` and `UnitfulMoles` packages available.

### Usage {#Usage}

The ParamViz extension provides interactive visualization of parameterization functions.

<img src="https://github.com/CliMA/ParamViz.jl/assets/22160257/832adffe-5a5b-4d46-9d15-a088bcb4b460" alt="ParamViz Screenshot">


## CliCal Extension {#CliCal-Extension}

CliCal generates dashboards for calibration EKI objects from ClimaCalibrate.jl. This extension is loaded when you have both `EnsembleKalmanProcesses` and `JLD2` packages available.

### Usage {#Usage-2}

CliCal provides visualization of calibration results including:
- Parameter evolution
  
- Loss function tracking
  
- Ensemble distributions
  
- Convergence diagnostics
  

<img src="https://github.com/user-attachments/assets/156df308-ea98-460b-9044-92e2a00603ab" alt="CliCal Screenshot">


## Extension Activation {#Extension-Activation}

Extensions are automatically activated when their weak dependencies are loaded:

```julia
# For ParamViz
using Unitful, UnitfulMoles

# For CliCal
using EnsembleKalmanProcesses, JLD2
```

