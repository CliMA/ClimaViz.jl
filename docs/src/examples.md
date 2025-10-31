# Examples

## Cloud Animations

ClimaViz includes tools for generating animations of cloud fields from ClimaAtmos outputs.

### 3D Cloud Animation

Located in `animations/clouds/cloud_animation_3d.jl`, this script generates 3D visualizations of cloud fields.

### 2D Cloud Animation

Located in `animations/clouds/cloud_animation_2d.jl`, this script generates 2D cross-sections and animations.

### Example Output

![Cloud Animation](https://github.com/user-attachments/assets/778b0c14-a5d7-4907-82db-6d1f8a0c5b07)

## Working with Simulation Outputs

### Basic Dashboard

```julia
using ClimaViz

# Point to your simulation output directory
output_dir = "path/to/simulation/output"

# Launch the dashboard
dashboard(output_dir)
```

The dashboard will automatically detect available variables and create interactive visualizations.

### Customizing Visualizations

The dashboard provides:
- Variable selection dropdowns
- Time slider for temporal analysis
- Spatial plotting with GeoMakie
- Statistical summaries

## Tips and Best Practices

1. **HPC Workflows**: When working on HPC, set up port forwarding before launching Julia to avoid connection issues.

2. **Large Datasets**: For large simulation outputs, consider subsetting your data before visualization to improve performance.

3. **Browser Compatibility**: The dashboard works best with modern browsers (Chrome, Firefox, Safari).

4. **Parallel Processing**: The dashboard can handle multiple simultaneous connections for collaborative analysis.
