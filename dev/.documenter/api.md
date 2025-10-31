
# API Reference {#API-Reference}



## Main Functions {#Main-Functions}
<details class='jldocstring custom-block' open>
<summary><a id='ClimaViz.dashboard' href='#ClimaViz.dashboard'><span class="jlbinding">ClimaViz.dashboard</span></a> <Badge type="info" class="jlObjectType jlFunction" text="Function" /></summary>



```julia
dashboard(path::String)
```


Launch an interactive web dashboard for visualizing climate simulation outputs.

The dashboard provides an interactive interface for exploring simulation data including:
- Variable selection and visualization
  
- Time series analysis
  
- Spatial mapping with GeoMakie
  
- Vertical profile analysis (when height dimension is available)
  
- Interactive controls for time, height, and animation
  

**Arguments**
- `path::String`: Path to the simulation output directory. Should contain output files that can be read by ClimaAnalysis.SimDir.
  

**Usage**

```julia
using ClimaViz

# Launch dashboard with simulation outputs
dashboard("path/to/output/")
```


After launching, open your browser to `http://localhost:8080/` to view the dashboard.

For HPC usage, set up SSH port forwarding first:

```bash
ssh -L 8080:localhost:8080 user@hpc.example.com
```


Then run the dashboard command and access it on your local browser.

**Notes**
- The dashboard runs on port 8080 by default
  
- If a previous server is running, it will be closed automatically
  
- Supports both 2D and 3D (with height) data
  
- Uses WGLMakie for web-based interactive plotting
  

**See Also**
- [`ClimaAnalysis.SimDir`](https://clima.github.io/ClimaAnalysis.jl/): For loading simulation data
  


<Badge type="info" class="source-link" text="source"><a href="https://github.com/CliMA/ClimaViz.jl/blob/5085ff050734811d760c717798eebd1dec982688/src/dashboard.jl#L1-L44" target="_blank" rel="noreferrer">source</a></Badge>

</details>


## Index {#Index}
- [`ClimaViz.dashboard`](#ClimaViz.dashboard)

