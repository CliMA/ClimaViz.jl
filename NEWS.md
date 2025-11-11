# ClimaViz.jl Release Notes

## Unreleased

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
