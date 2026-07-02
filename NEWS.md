# ClimaViz.jl Release Notes

## Unreleased

### New Features

#### Atmos monthly benchmarks: `pr`, `evspsbl`, `prw`
- New built-in observation loaders: GPCP monthly precipitation for `pr`
  (new `precipitation_obs` artifact, ~20 MB), ERA5 mean evaporation rate for
  `evspsbl` (from the already-shipped surface single-level artifact), and
  ERA5 total column water for `prw` (new
  `era5_monthly_averages_atmos_single_level` artifact, ~137 MB)
- Water mass fluxes (`kg m^-2 s^-1`) are now displayed in `mm day^-1`,
  mirroring the carbon-flux display conversion; the negative-downward
  ClimaAtmos precipitation fluxes (`pr`, `prra`, `prsn`) are sign-flipped so
  precipitation shows positive
- The run-title caption wraps long tokens (e.g. commit hashes) and renders
  newlines as line breaks

#### ClimaCoupler (multi-component) outputs
- `dashboard(path; coupled = true)` reads ClimaCoupler output directories
  (`clima_atmos/`, `clima_land/`, `clima_ocean/`, `clima_seaice/` subfolders)
  and adds a "Component:" menu to switch between them at runtime; empty or
  missing components are skipped
- The atmos component is restricted to its monthly (`_1M_`) native-grid
  diagnostics; land files missing a `start_date` attribute inherit the atmos
  start date
- ERA5 surface-flux benchmarks registered under the ClimaAtmos/CMIP names
  (`hfls`, `hfss`, `rlus`, `rsus`) in addition to the ClimaLand ones
- "Global" statistics (global time series, metrics table, model summary)
  follow the component's spatial mask: land mean (ocean-masked) for land and
  plain ClimaLand runs as before, full globe for atmos, ocean mean
  (land-masked) for ocean/seaice — menu labels and summary captions adapt

#### Model performance summary
- New "Model summary" button opens an overlay with the global ocean-masked
  RMSE (and bias) of every benchmarked variable vs. observations over the
  whole simulation period, per season (All-time / DJF / MAM / JJA / SON),
  color-coded green→red by RMSE relative to the observed mean
- Computed once per component and persisted in the `.climaviz_cache`, so
  reopening is instant; `dashboard(...; precompute = true)` also warms it

### Performance Improvements

- Benchmark session caches (regridded obs slices, bias limits, per-frame
  metrics) are now keyed by (variable, reduction, period, level) and kept for
  the whole session instead of being discarded on every variable switch —
  returning to an already-visited variable repaints instantly
- Map colorbar limits (a full-field quantile scan) are cached per
  (variable, reduction, period, level, height)
- Scrubbing the time slider on un-precomputed data no longer blocks ~2 s per
  tick: the per-frame metrics computation runs asynchronously and only the
  newest result is applied (latest-wins), with results cached for revisits

### Bug Fixes

- Coupled-mode discovery now reads each component's `SimDir` from its
  current-run output folder (`output_active` / highest `output_NNNN`) when one
  exists, instead of the component root. A component folder that also held stale
  loose `.nc` files from an earlier run made `SimDir` (which walks the whole
  tree) pick up each variable twice and fail to stitch the overlapping time axes
  ("Time dimension is not in non-decreasing order"); those leftover files are
  now ignored. The `.climaviz_cache` location is unchanged

## v0.1.4 - 2025-11-11

### New Features

#### Gradient Transparency Mode
- Added gradient-based transparency visualization mode for data analysis
- Allows transparent rendering of regions with low gradients to highlight areas of interest
- Useful for identifying boundaries, fronts, and regions of rapid change in climate data

#### UI Improvements
- Added slider control for adjusting gradient threshold in transparency mode
- Provides real-time adjustment of transparency sensitivity
- Enhances user control over visualization appearance

### Performance Improvements

#### 3D and 2D View Optimization
- Both 2D and 3D views now always remain rendered in DOM for instant switching
- Reduced 3D globe resolution to 0.5 px_per_unit for improved performance
- Optimized Earth background image quality for faster loading and rendering
- Streamlined codebase with 77 fewer lines while maintaining functionality

## v0.1.1 - 2025-11-05

### Performance Improvements

#### Fast 3D Globe Switching
- Optimized 3D globe view switching to be nearly instantaneous
- Both 2D and 3D figures now remain in DOM, toggling visibility via CSS
- Eliminates WebGL context re-initialization when switching views
- Previous implementation destroyed and recreated DOM elements, causing multi-second delays
- Same optimization applied to profile figure switching for consistency

### New Features

#### 3D Globe Visualization
- Added 3D globe view option with checkbox toggle to switch between 2D equirectangular and 3D globe projections
- Integrated realistic Earth background image with topography and bathymetry from Wikimedia Commons
- Climate data surfaces rendered at elevated z-level (20,000m) above Earth surface for clear visibility
- Continent coastlines displayed on 3D globe (black in normal mode, white in dark mode)
- Dual-figure architecture allows seamless switching between 2D and 3D views

#### Dark Mode
- Added dark mode toggle with system-wide theme switching
- Coordinated color updates across all UI components:
  - Background colors (black/white)
  - Text colors (white/black)
  - Axis labels and tick labels
  - Plot line colors
  - Coastline colors
  - Colorbar labels
- JavaScript-based CSS updates for DOM elements
- Makie-based updates for plot components

#### UI Improvements
- Replaced dropdown menu with `ChoicesBox` for variable selection with improved visual styling
- Enhanced layout with better spacing and organization
- Time series and vertical profile plots rearranged (time series now above profile)
- Vertical profile figure now conditionally displayed only when variables have height dimension
- Dynamic visibility using Observable pattern prevents layout gaps
- Improved figure sizing (50% larger profile and time series plots: 600×525)

#### Documentation
- Added comprehensive documentation using DocumenterVitepress
- API documentation for main functions
- Usage examples and guides
- Extension system documentation
- Deployment instructions
- GitHub Actions workflow for automatic documentation deployment

#### Package Architecture
- Converted CliCal and ParamViz to Julia package extensions
- Cleaner separation of core functionality from optional features
- Added extension migration guide
- Improved dependency management with weakdeps

#### Cloud Animations
- Added support for 3D cloud animations
- Example animation scripts in `animations/clouds/` directory

### Dependencies
- Added `FileIO` for image loading support
- Updated Project.toml with extension infrastructure

### Bug Fixes
- Fixed reduction and period menu synchronization when changing variables
- Improved error handling for variable switching
- Fixed profile limits calculation across all time steps
- Resolved layout issues when toggling between variables with/without height dimensions

### Known Limitations
- Title visibility in 3D globe mode needs improvement
- Mouse click location selection not yet implemented for 3D globe mode
- Automatic zoom in 3D mode not working (manual scroll zoom available)

## v0.1.0

Initial release with core dashboard functionality:
- Interactive web-based dashboard for climate simulation visualization
- Support for 2D spatial maps with time series
- Vertical profile analysis for 3D data
- Variable, reduction, and period selection
- Time and height sliders
- Animation controls
- Location selection via map clicking
- Integration with ClimaAnalysis.jl for data loading
