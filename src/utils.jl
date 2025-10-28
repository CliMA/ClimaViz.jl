# Type aliases for cleaner code
const OutputVar3D = Union{
    ClimaAnalysis.Var.OutputVar{Vector{Float64}, Array{Float64, 3}, String, Dict{Union{AbstractString, Symbol}, Any}},
    ClimaAnalysis.Var.OutputVar{Vector, Array{Float32, 3}, String, Dict{Union{AbstractString, Symbol}, Any}}
}

const OutputVar4D = Union{
    ClimaAnalysis.Var.OutputVar{Vector{Float64}, Array{Float64, 4}, String, Dict{Union{AbstractString, Symbol}, Any}},
    ClimaAnalysis.Var.OutputVar{Vector, Array{Float32, 4}, String, Dict{Union{AbstractString, Symbol}, Any}}
}

const OutputVarAny = Union{OutputVar3D, OutputVar4D}

# Calculate profile limits from profile data with padding
function get_profile_limits(profile_data; padding_fraction = 0.05)
    profile_min = minimum(profile_data)
    profile_max = maximum(profile_data)
    # Add some padding (5% on each side by default)
    padding = (profile_max - profile_min) * padding_fraction
    return (profile_min - padding, profile_max + padding)
end

# Calculate profile limits across all times at a given location
function get_profile_limits_all_times(var::OutputVar4D, lon, lat; padding_fraction = 0.05)
    z_dim = get_height_dim_name(var)
    # Slice at location only (keep all times and heights)
    var_profile_all_times = ClimaAnalysis.slice(var, lon = lon, lat = lat)
    # Get min/max across all the data
    profile_min = minimum(var_profile_all_times.data)
    profile_max = maximum(var_profile_all_times.data)
    # Add padding
    padding = (profile_max - profile_min) * padding_fraction
    return (profile_min - padding, profile_max + padding)
end

# AppState struct to bundle all related observables and data
mutable struct AppState
    # Data
    simdir::Any
    var::Observable
    dates_array::Vector
    heights::Vector{Float64}
    times::Any

    # Observables for main figure
    var_sliced::Observable
    limits::Observable
    title::Observable

    # Observables for profile
    lon_profile::Observable
    lat_profile::Observable
    profile::Observable
    profile_limits::Observable
    current_height::Observable
    profile_title::Observable
    profile_xlabel::Observable

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

    # Axes and visual elements
    ax::Any
    ax_profile::Any
    ax_timeseries::Any
    profile_lines::Any
    profile_hlines::Any

    # Other
    n_ticks::Int

    # Flag to prevent recursive updates
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

# Slice variable at time and optionally height
function var_slice(var::OutputVar4D, time_selected; height_selected = 1)
    # Extra safety: verify height dimension exists
    if !has_height(var)
        error("Variable claims to be 4D but has no height dimension")
    end
    z_dim = get_height_dim_name(var)
    if z_dim == "z"
        var_t = ClimaAnalysis.slice(
            var,
            time = var.dims["time"][time_selected],
            z = var.dims["z"][height_selected]
        )
    else # z_reference
        var_t = ClimaAnalysis.slice(
            var,
            time = var.dims["time"][time_selected],
            z_reference = var.dims["z_reference"][height_selected]
        )
    end
    return var_t.data
end

function var_slice(var::OutputVar3D, time_selected; height_selected = 1)
    var_t = ClimaAnalysis.slice(var, time = var.dims["time"][time_selected])
    return var_t.data
end

# Generic fallback that uses has_height check
function var_slice(var, time_selected; height_selected = 1)
    if has_height(var)
        z_dim = get_height_dim_name(var)
        if z_dim == "z"
            var_t = ClimaAnalysis.slice(
                var,
                time = var.dims["time"][time_selected],
                z = var.dims["z"][height_selected]
            )
        else # z_reference
            var_t = ClimaAnalysis.slice(
                var,
                time = var.dims["time"][time_selected],
                z_reference = var.dims["z_reference"][height_selected]
            )
        end
    else
        var_t = ClimaAnalysis.slice(var, time = var.dims["time"][time_selected])
    end
    return var_t.data
end

# Get color limits based on quantiles
function get_limits(var::OutputVar4D, time_selected; height_selected = 1, low_q = 0.02, high_q = 0.98)
    # Extra safety: verify height dimension exists
    if !has_height(var)
        error("Variable claims to be 4D but has no height dimension")
    end
    z_dim = get_height_dim_name(var)
    if z_dim == "z"
        var_allt = ClimaAnalysis.slice(var, z = var.dims["z"][height_selected])
    else # z_reference
        var_allt = ClimaAnalysis.slice(var, z_reference = var.dims["z_reference"][height_selected])
    end
    data = filter(!isnan, vec(var_allt.data))
    return (Statistics.quantile(data, low_q), Statistics.quantile(data, high_q))
end

function get_limits(var::OutputVar3D, time_selected; height_selected = 1, low_q = 0.02, high_q = 0.98)
    var_allt = ClimaAnalysis.slice(var)
    data = filter(!isnan, vec(var_allt.data))
    return (Statistics.quantile(data, low_q), Statistics.quantile(data, high_q))
end

# Generic fallback
function get_limits(var, time_selected; height_selected = 1, low_q = 0.02, high_q = 0.98)
    if has_height(var)
        z_dim = get_height_dim_name(var)
        if z_dim == "z"
            var_allt = ClimaAnalysis.slice(var, z = var.dims["z"][height_selected])
        else # z_reference
            var_allt = ClimaAnalysis.slice(var, z_reference = var.dims["z_reference"][height_selected])
        end
    else
        var_allt = ClimaAnalysis.slice(var)
    end
    data = filter(!isnan, vec(var_allt.data))
    return (Statistics.quantile(data, low_q), Statistics.quantile(data, high_q))
end

# Get vertical profile at location
function get_profile(var::OutputVar4D, lon, lat, time_selected)
    z_dim = get_height_dim_name(var)
    var_profile = ClimaAnalysis.slice(
        var,
        lon = lon,
        lat = lat,
        time = var.dims["time"][time_selected]
    )
    return var_profile.data
end

# Get time series at location (and optionally height)
function get_timeseries(var::OutputVar4D, lon, lat; height_selected = 1)
    z_dim = get_height_dim_name(var)
    if z_dim == "z"
        var_ts = ClimaAnalysis.slice(
            var,
            lon = lon,
            lat = lat,
            z = var.dims["z"][height_selected]
        )
    else # z_reference
        var_ts = ClimaAnalysis.slice(
            var,
            lon = lon,
            lat = lat,
            z_reference = var.dims["z_reference"][height_selected]
        )
    end
    return var_ts.data
end

function get_timeseries(var::OutputVar3D, lon, lat; height_selected = 1)
    var_ts = ClimaAnalysis.slice(
        var,
        lon = lon,
        lat = lat
    )
    return var_ts.data
end

# Title update functions
function update_title(state::AppState, time_idx)
    var = state.var[]
    base_title = string(
        ClimaAnalysis.long_name(var), "\n[",
        ClimaAnalysis.units(var), "]\n",
        Dates.format(ClimaAnalysis.dates(var)[time_idx], "U yyyy")
    )
    state.title[] = base_title
end

function update_title_with_height(state::AppState, time_idx, height_value)
    var = state.var[]
    state.title[] = string(
        ClimaAnalysis.long_name(var), "\n[",
        ClimaAnalysis.units(var), "]\n",
        Dates.format(ClimaAnalysis.dates(var)[time_idx], "U yyyy"), "\n",
        "Height: ", round(height_value, digits=1), " [m]"
    )
end

# Create formatted title strings for profile and timeseries
function profile_title_string(var, dates_array, time_idx, lon_val, lat_val)
    return string(
        ClimaAnalysis.short_name(var), " - Vertical Profile\n",
        Dates.format(dates_array[time_idx], "U yyyy"), ", ",
        "Lon: ", round(lon_val, digits=2), "°, Lat: ", round(lat_val, digits=2), "°"
    )
end

function timeseries_title_string(var, heights, height_idx, lon_val, lat_val)
    if has_height(var)
        return string(
            ClimaAnalysis.short_name(var), " - Time Series\n",
            "Height: ", round(heights[height_idx], digits=1), " m, ",
            "Lon: ", round(lon_val, digits=2), "°, Lat: ", round(lat_val, digits=2), "°"
        )
    else
        return string(
            ClimaAnalysis.short_name(var), " - Time Series\n",
            "Lon: ", round(lon_val, digits=2), "°, Lat: ", round(lat_val, digits=2), "°"
        )
    end
end

# Print startup message
function print_startup_message(port=8080)
    println("\n" * "="^60)
    println("\e[1;36m ClimaViz web app served!\e[0m")
    println("\e[1;32m→ Visit: \e[1;4;32mhttp://localhost:$port/\e[0m")
    println("\e[90mPress Ctrl+C to stop\e[0m")
    println("="^60 * "\n")
end
