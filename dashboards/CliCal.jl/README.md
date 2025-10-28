# Visualize interactively a ClimaCalibrate output file (`eki_file.jld2`)

## Install CliCal.jl

```julia
julia> ]
julia> add https://github.com/AlexisRenchon/clical.jl
```

## Use CliCal.jl

```julia
julia> using CliCal
julia> makeapp("path/to/eki_file.jld2")
```

CliCal should automatically open in your browser (URL: http://localhost:9384/browser-display)

![image](https://github.com/user-attachments/assets/156df308-ea98-460b-9044-92e2a00603ab)

### Notes

This package will be moved to ClimaCalibrate.jl as an extension when ready.
It currently works only for ClimaLand.jl calibration.

Once we have common flattening and reconstruction of diagnostics, this package
will be refactored (change to `src/fun_and_slice.jl`) to work with
ClimaLand, ClimaAtmos, and ClimaOcean.

See [PR](https://github.com/CliMA/ClimaAnalysis.jl/pull/269)
