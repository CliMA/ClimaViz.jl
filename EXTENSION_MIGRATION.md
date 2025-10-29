# Extension Migration Summary

## Overview

This document summarizes the conversion of CliCal.jl and ParamViz.jl from standalone modules in `dashboards/` to Julia package extensions in `ext/`.

## What Changed

### Directory Structure

**Before:**
```
ClimaViz.jl/
├── dashboards/
│   ├── CliCal.jl/
│   │   ├── Project.toml
│   │   └── src/
│   │       └── *.jl files
│   └── ParamViz.jl/
│       ├── Project.toml
│       └── src/
│           └── *.jl files
└── Project.toml (main package)
```

**After:**
```
ClimaViz.jl/
├── dashboards/          # Preserved for backwards compatibility
│   ├── CliCal.jl/
│   └── ParamViz.jl/
├── ext/                 # New extensions directory
│   ├── CliCalExt/
│   │   ├── CliCalExt.jl
│   │   └── *.jl files (copied from dashboards/CliCal.jl/src/)
│   ├── ParamVizExt/
│   │   ├── ParamVizExt.jl
│   │   └── *.jl files (copied from dashboards/ParamViz.jl/src/)
│   └── README.md
└── Project.toml (updated with extensions config)
```

### Project.toml Changes

Added to the main ClimaViz Project.toml:

1. **[weakdeps]** section:
   - `EnsembleKalmanProcesses` (for CliCalExt)
   - `JLD2` (for CliCalExt)
   - `Unitful` (for ParamVizExt)
   - `UnitfulMoles` (for ParamVizExt)

2. **[extensions]** section:
   - `CliCalExt = ["EnsembleKalmanProcesses", "JLD2"]`
   - `ParamVizExt = ["Unitful", "UnitfulMoles"]`

3. **[compat]** section:
   - Added `EnsembleKalmanProcesses = "2.5.0"`

### Code Changes

Minimal changes were made to the source code:

1. **CliCal.jl → CliCalExt.jl**:
   - Changed `module CliCal` to `module CliCalExt`
   - Changed `end # module CliCal` to `end # module CliCalExt`

2. **ParamViz.jl → ParamVizExt.jl**:
   - Changed `module ParamViz` to `module ParamVizExt`
   - Changed `Unitful.register(ParamViz)` to `Unitful.register(ParamVizExt)`

All other code remains unchanged, preserving the original functionality.

## How Extensions Work

Julia package extensions (introduced in Julia 1.9) allow packages to provide optional functionality that is only loaded when specific dependencies are available.

### For CliCalExt:
- The extension is **NOT** loaded by default
- It loads automatically when a user runs:
  ```julia
  using ClimaViz
  using EnsembleKalmanProcesses, JLD2
  ```
- After loading, the extension is available as `ClimaViz.CliCalExt`

### For ParamVizExt:
- The extension is **NOT** loaded by default
- It loads automatically when a user runs:
  ```julia
  using ClimaViz
  using Unitful, UnitfulMoles
  ```
- After loading, the extension is available as `ClimaViz.ParamVizExt`

## Benefits

1. **Reduced dependencies**: ClimaViz users don't need to install EnsembleKalmanProcesses, JLD2, Unitful, or UnitfulMoles unless they specifically need those features

2. **Cleaner package structure**: Extensions are part of the main package, not separate packages

3. **Automatic loading**: Extensions load automatically when their trigger packages are imported

4. **Backwards compatible**: The original modules in `dashboards/` are preserved

## Testing

The extension structure has been validated with automated tests that verify:
- Project.toml syntax is correct
- Extension modules syntax is correct
- Weak dependencies are properly configured
- Extension triggers are correctly defined
- Module declarations have been updated correctly

You can run the validation tests with:
```julia
# From the repository root
include("path/to/test_extensions.jl")
```

## Migration Guide for Users

### Old Usage (with standalone modules):
```julia
# Option 1: Use CliCal directly
using Pkg
Pkg.activate("path/to/ClimaViz.jl/dashboards/CliCal.jl")
using CliCal

# Option 2: Use ParamViz directly
Pkg.activate("path/to/ClimaViz.jl/dashboards/ParamViz.jl")
using ParamViz
```

### New Usage (with extensions):
```julia
# For CliCal functionality:
using ClimaViz
using EnsembleKalmanProcesses, JLD2  # Triggers CliCalExt
# Extension is now available

# For ParamViz functionality:
using ClimaViz
using Unitful, UnitfulMoles  # Triggers ParamVizExt
# Extension is now available
```

## Notes

- The original modules in `dashboards/` have been preserved and are still functional
- Users can continue using the standalone modules if preferred
- The extensions provide the same functionality with better integration into ClimaViz
