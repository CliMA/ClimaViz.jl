# AppState struct to bundle all related observables and data
mutable struct AppState
    # Data
    simdir::Any
    var::Observable
    obs_bundle::Any  # ObsBundle from benchmark.jl
    dates_array::Vector
    heights::Vector{Float64}
    times::Any

    # Aggregation
    aggregation_level::Observable  # Symbol: :native, :seasonal, :annual
    sim_agg::Observable  # Aggregated sim OutputVar (or same as var if :native)
    obs_agg::Observable  # Aggregated obs OutputVar or nothing

    # Observables for main figure (2D map)
    var_sliced::Observable
    limits::Observable
    title::Observable

    # Observables for bias figure
    show_bias::Observable
    bias_sliced::Observable
    bias_limits::Observable
    bias_title::Observable

    # Observables for metrics table
    metrics::Observable

    # Observables for profile
    lon_profile::Observable
    lat_profile::Observable
    profile::Observable
    profile_limits::Observable
    current_height::Observable
    profile_title::Observable
    profile_xlabel::Observable
    heights_obs::Observable

    # Observables for timeseries
    timeseries::Observable
    timeseries_title::Observable
    timeseries_ylabel::Observable
    current_time_index::Observable

    # UI observables
    time_selected::Observable
    height_selected::Observable
    speed_selected::Observable
    time_value_text::Observable
    height_value_text::Observable
    speed_value_text::Observable
    dark_mode::Observable
    show_height::Observable
    is_playing::Observable  # to gate expensive updates during animation

    # Axes and visual elements
    ax::Any
    ax_bias::Any
    ax_profile::Any
    ax_timeseries::Any
    profile_lines::Any
    profile_hlines::Any
    timeseries_lines::Any
    coastlines_plot::Any
    coastlines_plot_bias::Any
    colorbar::Any
    colorbar_bias::Any
    colorbar_label::Observable
    colorbar_label_bias::Observable
    profile_box::Any
    surface_plot_colormap::Any
    surface_plot_bias::Any
    earth_surface::Any
    earth_img::Any
    lon::Vector{Float64}
    lat::Vector{Float64}

    # Figures
    fig::Any
    fig_bias::Any
    fig_profile::Any
    fig_timeseries::Any

    # Misc
    n_ticks::Int
    updating::Bool
end

# Check if variable has height dimension
has_height(var) = haskey(var.dims, "z") || haskey(var.dims, "z_reference")

# Get the height dimension name (either "z" or "z_reference")
function get_height_dim_name(var)
    if haskey(var.dims, "z")
        return "z"
    elseif haskey(var.dims, "z_reference")
        return "z_reference"
    else
        error("Variable has no height dimension (neither 'z' nor 'z_reference')")
    end
end

# Slice variable at time and optionally height. Returns the underlying 2D array.
function var_slice(var, time_selected; height_selected = 1)
    if has_height(var)
        z_dim = get_height_dim_name(var)
        kwargs = Dict(
            :time => var.dims["time"][time_selected],
            Symbol(z_dim) => var.dims[z_dim][height_selected],
        )
        return ClimaAnalysis.slice(var; kwargs...).data
    else
        return ClimaAnalysis.slice(var; time = var.dims["time"][time_selected]).data
    end
end

# Get color limits based on quantiles (across all times at selected height).
function get_limits(var, time_selected; height_selected = 1, low_q = 0.02, high_q = 0.98)
    if has_height(var)
        z_dim = get_height_dim_name(var)
        var_allt = ClimaAnalysis.slice(var; Symbol(z_dim) => var.dims[z_dim][height_selected])
    else
        var_allt = var  # 3D var, all times already
    end
    data = filter(!isnan, vec(var_allt.data))
    isempty(data) && return (0.0, 1.0)
    lim_low = Statistics.quantile(data, low_q)
    lim_high = Statistics.quantile(data, high_q)
    if lim_low == lim_high
        center = lim_low
        buffer = abs(center) * 0.1 + 0.1
        return (center - buffer, center + buffer)
    end
    return (lim_low, lim_high)
end

# Symmetric quantile-based limits around 0 for diverging colorbars (bias maps).
function get_bias_limits(bias_var; q = 0.98)
    isnothing(bias_var) && return (-1.0, 1.0)
    data = filter(!isnan, vec(bias_var.data))
    isempty(data) && return (-1.0, 1.0)
    lim = Statistics.quantile(abs.(data), q)
    lim == 0 && return (-1.0, 1.0)
    return (-lim, lim)
end

# Calculate profile limits from profile data with padding
function get_profile_limits(profile_data; padding_fraction = 0.05)
    profile_min = minimum(profile_data)
    profile_max = maximum(profile_data)
    padding = (profile_max - profile_min) * padding_fraction
    if profile_min == profile_max
        center = profile_min
        buffer = abs(center) * 0.1 + 0.1
        return (center - buffer, center + buffer)
    end
    return (profile_min - padding, profile_max + padding)
end

# Profile limits across all times at a given location (stable y-range for animation)
function get_profile_limits_all_times(var, lon, lat; padding_fraction = 0.05)
    var_profile_all_times = ClimaAnalysis.slice(var; lon = lon, lat = lat)
    profile_min = minimum(var_profile_all_times.data)
    profile_max = maximum(var_profile_all_times.data)
    padding = (profile_max - profile_min) * padding_fraction
    if profile_min == profile_max
        center = profile_min
        buffer = abs(center) * 0.1 + 0.1
        return (center - buffer, center + buffer)
    end
    return (profile_min - padding, profile_max + padding)
end

# Get vertical profile at location
function get_profile(var, lon, lat, time_selected)
    var_profile = ClimaAnalysis.slice(
        var;
        lon = lon, lat = lat, time = var.dims["time"][time_selected],
    )
    return var_profile.data
end

# Get time series at location (and optionally height)
function get_timeseries(var, lon, lat; height_selected = 1)
    if has_height(var)
        z_dim = get_height_dim_name(var)
        kwargs = Dict(:lon => lon, :lat => lat, Symbol(z_dim) => var.dims[z_dim][height_selected])
        return ClimaAnalysis.slice(var; kwargs...).data
    else
        return ClimaAnalysis.slice(var; lon = lon, lat = lat).data
    end
end

# Title update functions
function update_title(state::AppState, time_idx)
    var = state.var[]
    state.title[] = string(
        ClimaAnalysis.long_name(var), "\n[",
        ClimaAnalysis.units(var), "]\n",
        Dates.format(state.dates_array[time_idx], "U yyyy"),
    )
end

function update_title_with_height(state::AppState, time_idx, height_value)
    var = state.var[]
    state.title[] = string(
        ClimaAnalysis.long_name(var), "\n[",
        ClimaAnalysis.units(var), "]\n",
        Dates.format(state.dates_array[time_idx], "U yyyy"), "\n",
        "Height: ", round(height_value, digits = 1), " [m]",
    )
end

function profile_title_string(var, dates_array, time_idx, lon_val, lat_val)
    return string(
        ClimaAnalysis.short_name(var), " - Vertical Profile\n",
        Dates.format(dates_array[time_idx], "U yyyy"), ", ",
        "Lon: ", round(lon_val, digits = 2), "°, Lat: ", round(lat_val, digits = 2), "°",
    )
end

function timeseries_title_string(var, heights, height_idx, lon_val, lat_val)
    if has_height(var)
        return string(
            ClimaAnalysis.short_name(var), " - Time Series\n",
            "Height: ", round(heights[height_idx], digits = 1), " m, ",
            "Lon: ", round(lon_val, digits = 2), "°, Lat: ", round(lat_val, digits = 2), "°",
        )
    else
        return string(
            ClimaAnalysis.short_name(var), " - Time Series\n",
            "Lon: ", round(lon_val, digits = 2), "°, Lat: ", round(lat_val, digits = 2), "°",
        )
    end
end

function bias_title_string(var, dates_array, time_idx)
    return string(
        "Sim − Obs: ", ClimaAnalysis.short_name(var), " [",
        ClimaAnalysis.units(var), "]\n",
        Dates.format(dates_array[time_idx], "U yyyy"),
    )
end

# Print startup message
function print_startup_message(port = 8080)
    println("\n" * "="^60)
    println("\e[1;36m ClimaViz web app served!\e[0m")
    println("\e[1;32m→ Visit: \e[1;4;32mhttp://localhost:$port/\e[0m")
    println("\e[90mPress Ctrl+C to stop\e[0m")
    println("="^60 * "\n")
end
