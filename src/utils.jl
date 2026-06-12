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
    metrics_scope::Observable  # Symbol: which scope column to display

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
    timeseries_obs::Observable      # parallel obs series (NaN where missing)
    show_obs_line::Observable       # mirrors show_bias for the obs line
    timeseries_mode::Observable     # Symbol: :local (clicked point) or :global (land mean)
    obs_name::Observable            # display name of the obs product ("ERA5", …)
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
    is_playing::Observable          # gates expensive updates during animation
    is_loading::Observable          # drives the top progress bar
    loading_status::Observable      # short status text shown next to the bar

    # Axes and visual elements
    ax::Any
    ax_bias::Any
    ax_profile::Any
    ax_timeseries::Any
    profile_lines::Any
    profile_hlines::Any
    timeseries_lines::Any
    timeseries_obs_lines::Any
    timeseries_legend::Any
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

    # Session caches keyed by (short_name, reduction, period, level[, …]).
    # Keys are fully qualified, so entries stay valid for the whole session and
    # are kept across variable switches — flipping back to an already-visited
    # variable is then instant instead of redoing regridding/quantiles/metrics.
    bias_limits_cache::Dict{Tuple{String, String, String, Symbol}, Tuple{Float64, Float64}}
    obs_resampled_cache::Dict{Tuple{String, String, String, Symbol}, Any}
    # Per-(…, time index) :selected MetricsTable, prefilled from the persistent
    # cache so time-slider scrubbing is instant.
    metrics_cache::Dict{Tuple{String, String, String, Symbol, Int}, Any}
    # Map colorbar limits per (…, height index) — a full-field quantile scan
    # otherwise repeated on every variable/aggregation/height switch.
    limits_cache::Dict{Tuple{String, String, String, Symbol, Int}, Tuple{Float64, Float64}}

    # Persistent benchmark cache controller (BenchmarkCache) or nothing.
    bench_cache::Any
    # Active reduction / period — half of the persistent cache key (the other
    # half, short_name + level, is read off `var` / `aggregation_level`).
    current_reduction::String
    current_period::String
    # start_date (ISO string) substituted into variables whose files lack the
    # attribute — the atmos start_date in coupled mode, `nothing` otherwise.
    fallback_start_date::Any
    # Spatial mask for "global" statistics, keyed into MASK_SPECS — :land
    # (ocean-masked), :globe (atmos, no mask) or :ocean (land-masked).
    mask_kind::Symbol

    # Misc
    n_ticks::Int
    updating::Bool
end

# Variable short names of a SimDir in stable (alphabetical) order.
_sorted_vars(simdir) = sort!(collect(String, keys(simdir.vars)))

# ─── Per-component spatial masking ───────────────────────────────────────────
# The dashboard's "global" statistics — global time series, the metrics table
# (Sim/Obs mean, Bias, RMSE) and the model summary — restrict the area-weighted
# mean to where the component's fields are meaningful: land for ClimaLand
# output (the ocean-masked convention this dashboard always used), the full
# globe for atmos, ocean for the ocean/seaice components. `cache_tag` is
# appended to persistent-cache fingerprints so mask changes invalidate stale
# entries; it is empty for `:land` to keep pre-existing caches valid.
const MASK_SPECS = (
    land = (mask = ClimaAnalysis.apply_oceanmask, global_label = "Global (land mean)",
            summary_note = "land-only (ocean-masked)", cache_tag = ""),
    globe = (mask = nothing, global_label = "Global",
             summary_note = "full-globe", cache_tag = "|mask=globe"),
    ocean = (mask = ClimaAnalysis.apply_landmask, global_label = "Global (ocean mean)",
             summary_note = "ocean-only (land-masked)", cache_tag = "|mask=ocean"),
)

mask_spec(kind::Symbol) = getproperty(MASK_SPECS, kind)

component_mask_kind(label) =
    label == "atmos" ? :globe :
    label in ("ocean", "seaice") ? :ocean : :land

# Load a simulation variable in display units. If the source file lacks the
# `start_date` attribute (seen on ClimaLand output inside coupler runs, and
# required by `ClimaAnalysis.dates`), substitute `fallback_start_date` (the
# atmos one in coupled mode). The patch mutates the SimDir-cached OutputVar,
# so it sticks for later loads of the same variable.
function load_sim_var(simdir, short_name, reduction, period; fallback_start_date = nothing)
    var = get(simdir; short_name = short_name, reduction = reduction, period = period)
    if !haskey(var.attributes, "start_date") && !isnothing(fallback_start_date)
        var.attributes["start_date"] = string(fallback_start_date)
    end
    return to_display_units(var)
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

# Get obs time series at lon/lat; returns NaN-filled vector matching sim length if no obs.
function get_obs_timeseries(obs_var, lon, lat, sim_length)
    isnothing(obs_var) && return fill(NaN, sim_length)
    data = ClimaAnalysis.slice(obs_var; lon = lon, lat = lat).data
    return _pad_series(data, sim_length)
end

# Pad with NaN (or truncate) a series to exactly `n` entries.
function _pad_series(data, n)
    out = fill(NaN, n)
    m = min(length(data), n)
    out[1:m] .= data[1:m]
    return out
end

# Area-weighted global mean per time step (NaN-aware) under `mask` — the same
# convention as the "Sim mean" / "Obs mean" metrics rows. The default mask is
# the land-only (ocean-masked) one; pass `mask = nothing` for the full globe
# (atmos). For variables with a height dimension, the mean is taken at the
# selected height.
function get_global_timeseries(var; height_selected = 1, mask = ClimaAnalysis.apply_oceanmask)
    if has_height(var)
        z_dim = get_height_dim_name(var)
        var = ClimaAnalysis.slice(var; Symbol(z_dim) => var.dims[z_dim][height_selected])
    end
    masked = isnothing(mask) ? var :
        try
            mask(var)
        catch
            var
        end
    return collect(Float64, vec(ClimaAnalysis.weighted_average_lonlat(masked).data))
end

# Global obs series under the same mask, padded/truncated to the sim length.
function get_obs_global_timeseries(obs_var, sim_length; mask = ClimaAnalysis.apply_oceanmask)
    isnothing(obs_var) && return fill(NaN, sim_length)
    return _pad_series(get_global_timeseries(obs_var; mask), sim_length)
end

const _MONTH_TO_SEASON = Dict(
    12 => "DJF", 1 => "DJF", 2 => "DJF",
    3 => "MAM", 4 => "MAM", 5 => "MAM",
    6 => "JJA", 7 => "JJA", 8 => "JJA",
    9 => "SON", 10 => "SON", 11 => "SON",
)

_as_datetime(d) = d isa Dates.Date ? Dates.DateTime(d) : d

# Format a date for the given aggregation level (used in titles + slider value text).
function format_date_for_level(date, level::Symbol)
    if level === :annual
        return string(Dates.year(date))
    elseif level === :seasonal
        return string(_MONTH_TO_SEASON[Dates.month(date)], " ", Dates.year(date))
    elseif level === :daily
        return Dates.format(date, "U d, yyyy")
    elseif level === :hourly
        return Dates.format(_as_datetime(date), "U d yyyy HH:00")
    else  # :native (typically monthly) or unknown
        return Dates.format(date, "U yyyy")
    end
end

# Shorter variant for axis tick labels where space is tight.
function format_date_short(date, level::Symbol)
    if level === :annual
        return string(Dates.year(date))
    elseif level === :seasonal
        yy = lpad(Dates.year(date) % 100, 2, "0")
        return string(_MONTH_TO_SEASON[Dates.month(date)], " ", yy)
    elseif level === :daily
        return Dates.format(date, "u d yy")
    elseif level === :hourly
        return Dates.format(_as_datetime(date), "u d HH:00")
    else
        return Dates.format(date, "u yyyy")
    end
end

# Title update functions
function update_title(state::AppState, time_idx)
    var = state.var[]
    state.title[] = string(
        ClimaAnalysis.long_name(var), "\n[",
        ClimaAnalysis.units(var), "]\n",
        format_date_for_level(state.dates_array[time_idx], state.aggregation_level[]),
    )
end

function update_title_with_height(state::AppState, time_idx, height_value)
    var = state.var[]
    state.title[] = string(
        ClimaAnalysis.long_name(var), "\n[",
        ClimaAnalysis.units(var), "]\n",
        format_date_for_level(state.dates_array[time_idx], state.aggregation_level[]), "\n",
        "Height: ", round(height_value, digits = 1), " [m]",
    )
end

function profile_title_string(var, dates_array, time_idx, lon_val, lat_val, level::Symbol = :native)
    return string(
        ClimaAnalysis.short_name(var), " - Vertical Profile\n",
        format_date_for_level(dates_array[time_idx], level), ", ",
        "Lon: ", round(lon_val, digits = 2), "°, Lat: ", round(lat_val, digits = 2), "°",
    )
end

function timeseries_title_string(var, heights, height_idx, lon_val, lat_val, mode::Symbol = :local, global_label = "Global (land mean)")
    where_str = mode === :global ? global_label :
        string("Lon: ", round(lon_val, digits = 2), "°, Lat: ", round(lat_val, digits = 2), "°")
    if has_height(var)
        return string(
            ClimaAnalysis.short_name(var), " - Time Series\n",
            "Height: ", round(heights[height_idx], digits = 1), " m, ", where_str,
        )
    else
        return string(ClimaAnalysis.short_name(var), " - Time Series\n", where_str)
    end
end

function bias_title_string(var, dates_array, time_idx, level::Symbol = :native, obs_name = "Obs")
    return string(
        "Sim − ", obs_name, ": ", ClimaAnalysis.short_name(var), " [",
        ClimaAnalysis.units(var), "]\n",
        format_date_for_level(dates_array[time_idx], level),
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
