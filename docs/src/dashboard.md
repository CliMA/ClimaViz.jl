# The Dashboard

```@meta
CurrentModule = ClimaViz
```

`dashboard(path)` launches an interactive web dashboard for exploring climate
simulation outputs (anything readable by `ClimaAnalysis.SimDir`) and
benchmarking them against gridded observations.

## Quick start

```julia
using ClimaViz

# A single output folder (e.g. a ClimaLand or ClimaAtmos run):
dashboard("path/to/output/")

# A ClimaCoupler run (clima_atmos/, clima_land/, … subfolders):
dashboard("path/to/coupler_output/"; coupled = true)

# On HPC, serve on 0.0.0.0:8080 for SSH port forwarding:
dashboard("path/to/output/"; HPC = true)
```

Then open `http://localhost:8080/` in your browser (see
[Using from HPC](@ref) for port forwarding).

## What you see

The dashboard is a single page with a menu column and four linked panels:

- **2D map** of the selected variable. Click anywhere to select a location —
  the time series and vertical profile follow.
- **Bias map** (simulation − observation), shown whenever the selected
  variable has a registered observation. The observation is regridded onto
  the simulation grid; the colorbar is symmetric and stable across time.
- **Time series** at the selected location (or a global mean, see below),
  with the observation overlaid when available.
- **Vertical profile** for variables with a height dimension; for 2D
  variables this panel is replaced by a **benchmark metrics table**
  (Sim mean, Obs mean, Bias, RMSE for the selected time frame).

## The menus

| Menu | What it does |
|---|---|
| **Component** | (coupled mode only) Switch between `atmos`, `land`, `ocean`, `seaice`. Components with no output are hidden. |
| **Variable** | Searchable list of every variable found in the output. |
| **Aggregation** | Re-bin the time axis on the fly: native resolution (e.g. Monthly), Seasonal, or Annual. |
| **Time series** | `Local (click map)` — the clicked location — or a global mean. Clicking a map switches back to Local. |
| **Time** | Slider through the (aggregated) time axis. The ▶ button animates it; the speed slider sets the frame delay. |
| **Height** | Level selection for 3D variables. |
| **Model summary** | Opens the model performance summary overlay (see below). |
| **Dark Mode** | Toggles the page theme. |

### Global means and spatial masks

"Global" statistics — the global time series, the metrics table and the model
summary — use an area-weighted mean restricted to where the component's
fields are meaningful:

| Component | Mask | Menu label |
|---|---|---|
| land (and plain single-folder runs) | ocean-masked (land only) | `Global (land mean)` |
| atmos | none (full globe) | `Global` |
| ocean / seaice | land-masked (ocean only) | `Global (ocean mean)` |

## Benchmarks

Variables with a registered observation get the bias map, the metrics table,
an observation line in the time series, and a row in the model summary. The
built-in registry ([`default_obs`](@ref)) covers:

| Simulation variable | Observation product | Notes |
|---|---|---|
| `lhf`, `shf`, `lwu`, `swu` | ERA5 monthly surface fluxes | ClimaLand names |
| `hfls`, `hfss`, `rlus`, `rsus` | ERA5 monthly surface fluxes | same fields, ClimaAtmos/CMIP names |
| `nee` | CarbonTracker CT2022 | inversion-derived, 2002–2020 |
| `gpp` | GOSIF-GPP v2 | |
| `er` | CarbonTracker + GOSIF residual | |
| `hr` | Hashimoto 2015 | |

Carbon fluxes are displayed in `g C m^-2 day^-1` (converted from the model's
`mol CO2 m^-2 s^-1`). All observation data ships as lazy artifacts — nothing
to download manually.

### Custom observations

Pass your own registry via the `obs` keyword: a
`Dict{String, Function}` mapping a simulation short name to a loader. Each
loader receives the simulation's start date and returns a
`ClimaAnalysis.OutputVar` (units must match the displayed simulation units).
Set `attributes["obs_source"]` on the returned variable to control the
product name shown in the legend, bias title and metrics table:

```julia
my_obs = Dict{String, Function}(
    "ts" => start_date -> begin
        var = ClimaAnalysis.OutputVar("my_obs_ts.nc", "ts")
        var.attributes["obs_source"] = "MyProduct"
        var
    end,
)
dashboard(path; obs = merge(default_obs(), my_obs))
```

## Model summary

The **Model summary** button opens an overlay with one row per benchmarked
variable and one column per season (All-time / DJF / MAM / JJA / SON). Each
cell shows the global RMSE (and bias) against the observation over the whole
simulation period, color-coded by RMSE relative to the observed mean (green
≤ 25 %, red ≥ 125 %) — the whole model's performance in one image.

The summary is computed once per component and persisted in the cache;
reopening it is instant. Start the server with `precompute = true` to warm it
up front.

## ClimaCoupler outputs (`coupled = true`)

A ClimaCoupler run writes one diagnostics folder per component:

```
coupler_output/
├── clima_atmos/    # *_1M_*.nc monthly diagnostics (+ restarts, configs)
├── clima_land/
├── clima_ocean/
└── clima_seaice/
```

With `coupled = true` the dashboard discovers these folders and adds the
Component menu. Details handled for you:

- The atmos component is restricted to its monthly (`_1M_`) native-grid
  diagnostics (instantaneous fields and pressure-level variants are skipped).
- Components whose files lack a `start_date` attribute (possible for land)
  inherit the atmos start date.
- Each component gets its own benchmark cache and spatial mask.
- All components are assumed to share the diagnostic lon/lat grid (which is
  how ClimaCoupler writes them).

## Performance and caching

The slow part of benchmarking — regridding observations onto the simulation
grid and computing ocean-masked metrics — is cached persistently in
`<output>/.climaviz_cache/` (one per component in coupled mode). Raw
simulation fields are always read lazily and are never cached.

- First visit to a variable computes its benchmark in the background (a
  progress bar shows the status); everything after that is instant, including
  switching back to previously viewed variables within a session.
- [`precompute_dashboard_cache`](@ref) warms every cacheable entry up front;
  `dashboard(path; precompute = true)` does this (plus the model summary)
  before serving. Recommended for long-lived deployments:

```julia
dashboard("path/to/output/"; HPC = true, precompute = true)
```

The cache is fingerprinted against the source NetCDF files (size + mtime), so
regenerating the simulation output invalidates it automatically. It is safe
to delete `.climaviz_cache/` at any time. If the output folder is a git
repository, add `.climaviz_cache/` to its `.gitignore`.
