# ClimaViz.jl

```@meta
CurrentModule = ClimaViz
```

ClimaViz is a Julia package for generating web dashboards from climate simulation outputs directly from HPC or locally. It currently supports ClimaAtmos and ClimaLand.

## Features

- **Interactive web dashboards**: Generate web-based visualizations of your simulation outputs
- **HPC support**: Run directly from HPC environments with SSH port forwarding
- **Local development**: Test and visualize locally before deployment
- **ParamViz**: Visualize climate parameterizations
- **CliCal**: Dashboard for calibration EKI objects (from ClimaCalibrate.jl)
- **Cloud animations**: Generate animations of clouds from ClimaAtmos outputs

## Quick Start

### Installation

```julia
using Pkg
Pkg.add("ClimaViz")
```

### Basic Usage

```julia
using ClimaViz

# Provide the path to your output directory
path = "output/"

# Launch the web dashboard
dashboard(path)
```

Then open `http://localhost:8080/` in your browser.

### Using from HPC

When running from HPC, you need to set up SSH port forwarding:

```shell
ssh -L 8080:localhost:8080 user@ssh.example.com
```

Then run the Julia code as shown above and access the dashboard on your local browser at `http://localhost:8080/`.

## Table of Contents

```@contents
Pages = ["index.md", "api.md", "extensions.md", "examples.md"]
Depth = 2
```

## See Also

- [ClimaAnalysis.jl](https://github.com/CliMA/ClimaAnalysis.jl) - The analysis backend used by ClimaViz
- [ClimaCalibrate.jl](https://github.com/CliMA/ClimaCalibrate.jl) - For calibration workflows
