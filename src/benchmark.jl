using LazyArtifacts

const _AGG_LEVELS_ORDER =
    (:hourly => 1, :daily => 2, :monthly => 3, :seasonal => 4, :annual => 5)

const _SEASON_OF_MONTH = Dict(
    12 => "DJF", 1 => "DJF", 2 => "DJF",
    3 => "MAM", 4 => "MAM", 5 => "MAM",
    6 => "JJA", 7 => "JJA", 8 => "JJA",
    9 => "SON", 10 => "SON", 11 => "SON",
)

function _era5_monthly_nc_path()
    try
        dir = artifact"era5_monthly_averages_surface_single_level_1979_2024"
        return joinpath(dir, "era5_monthly_averages_surface_single_level_197901-202410.nc")
    catch e
        @warn "ClimaViz: ERA5 monthly artifact not available; benchmark disabled" exception=(e, catch_backtrace())
        return nothing
    end
end

function _era5_loader(varname_era5, varname_sim; flip_sign = false)
    return function (_start_date)
        path = _era5_monthly_nc_path()
        isnothing(path) && return nothing
        obs_var = ClimaAnalysis.OutputVar(path, varname_era5)
        if ClimaAnalysis.units(obs_var) == "W m**-2"
            if flip_sign
                obs_var = ClimaAnalysis.convert_units(
                    obs_var,
                    "W m^-2";
                    conversion_function = u -> u * -1.0,
                )
            else
                obs_var = ClimaAnalysis.set_units(obs_var, "W m^-2")
            end
        end
        obs_var.attributes["short_name"] = varname_sim
        return obs_var
    end
end

"""
    default_era5_obs()

Built-in `Dict{String, Function}` mapping ClimaLand simulation short names to
ERA5 monthly observation loaders. Each loader takes a `start_date` and returns
a `ClimaAnalysis.OutputVar` aligned to that origin.

Covers: `lhf`, `shf`, `lwu`, `swu` (W m⁻², surface monthly, 1°×1°). Returns an
empty Dict if the underlying artifact is unavailable.
"""
function default_era5_obs()
    isnothing(_era5_monthly_nc_path()) && return Dict{String, Function}()
    return Dict{String, Function}(
        "lhf" => _era5_loader("mslhf", "lhf"; flip_sign = true),
        "shf" => _era5_loader("msshf", "shf"; flip_sign = true),
        "lwu" => _era5_loader("msuwlwrf", "lwu"; flip_sign = false),
        "swu" => _era5_loader("msuwswrf", "swu"; flip_sign = false),
    )
end

mutable struct ObsBundle
    loaders::Dict{String, Function}
    cache::Dict{String, Any}
    start_date::Any
end

function ObsBundle(loaders::Dict{String, Function}; start_date)
    return ObsBundle(loaders, Dict{String, Any}(), start_date)
end

has_obs(bundle::ObsBundle, short_name::AbstractString) = haskey(bundle.loaders, short_name)

function get_obs(bundle::ObsBundle, short_name::AbstractString)
    haskey(bundle.cache, short_name) && return bundle.cache[short_name]
    haskey(bundle.loaders, short_name) || return nothing
    obs = try
        bundle.loaders[short_name](bundle.start_date)
    catch e
        @warn "ClimaViz: obs loader failed for $short_name" exception=(e, catch_backtrace())
        nothing
    end
    bundle.cache[short_name] = obs
    return obs
end

function _detect_native_period(var)
    dates = ClimaAnalysis.dates(var)
    length(dates) < 2 && return :monthly
    delta = dates[2] - dates[1]
    if delta >= Day(28) && delta <= Day(31)
        return :monthly
    elseif delta >= Day(1) && delta < Day(28)
        return :daily
    elseif delta < Day(1)
        return :hourly
    else
        return :annual
    end
end

"""
    available_levels(var)

Return the list of aggregation levels that are at least as coarse as the
variable's native temporal resolution. Always contains `:native`. For monthly
data the result is `[:native, :seasonal, :annual]`.
"""
function available_levels(var)
    native = _detect_native_period(var)
    native_pair_idx = findfirst(p -> p.first == native, _AGG_LEVELS_ORDER)
    native_order = isnothing(native_pair_idx) ? 3 : _AGG_LEVELS_ORDER[native_pair_idx].second
    levels = Symbol[:native]
    for (k, v) in _AGG_LEVELS_ORDER
        v > native_order && push!(levels, k)
    end
    return levels
end

"""
    aggregation_label(var, level)

Human-readable name for an aggregation level given the native period of `var`.
"""
function aggregation_label(var, level)
    if level == :native
        native = _detect_native_period(var)
        return native == :monthly ? "Monthly" :
               native == :daily ? "Daily" :
               native == :hourly ? "Hourly" : string(native)
    elseif level == :seasonal
        return "Seasonal"
    elseif level == :annual
        return "Annual"
    else
        return string(level)
    end
end

function _nanmean_along(a::AbstractArray, dim_idx::Integer)
    s = sum(z -> isnan(z) ? zero(z) : z, a; dims = dim_idx)
    n = sum(z -> isnan(z) ? 0 : 1, a; dims = dim_idx)
    result = s ./ n
    result[n .== 0] .= NaN
    return result
end

function _aggregate_by_groups(var, groups::Vector{Vector{Int}}, new_times::Vector)
    time_dim = "time"
    time_idx = var.dim2index[time_dim]
    data = var.data
    sz = collect(size(data))
    sz[time_idx] = length(groups)
    new_data = similar(data, Tuple(sz))
    for (j, idxs) in enumerate(groups)
        sub = selectdim(data, time_idx, idxs)
        avg = _nanmean_along(sub, time_idx)
        out_slice = selectdim(new_data, time_idx, j)
        out_slice .= dropdims(avg; dims = time_idx)
    end
    new_dims = deepcopy(var.dims)
    new_dims[time_dim] = new_times
    return ClimaAnalysis.remake(var; dims = new_dims, data = new_data)
end

"""
    aggregate_var(var, level::Symbol)

Return a new `OutputVar` whose time axis has been re-binned at `level`. Per-cell
averaging is NaN-aware. `level == :native` returns `var` unchanged.

- `:annual`: one frame per calendar year (median time of the year used as the
  new time coordinate).
- `:seasonal`: one frame per (year, season) bin, in chronological order. Season
  is defined by month: DJF, MAM, JJA, SON. DJF is keyed to the year of January.
"""
function aggregate_var(var, level::Symbol)
    level == :native && return var
    dates = ClimaAnalysis.dates(var)
    times = var.dims["time"]
    if level == :annual
        years = sort(unique(Dates.year.(dates)))
        groups = [findall(d -> Dates.year(d) == y, dates) for y in years]
        new_times = [times[g[(length(g)+1)÷2]] for g in groups]
        return _aggregate_by_groups(var, groups, new_times)
    elseif level == :seasonal
        keys_per_date = map(dates) do d
            m = Dates.month(d)
            yr = m == 12 ? Dates.year(d) + 1 : Dates.year(d)
            (yr, _SEASON_OF_MONTH[m])
        end
        unique_keys = unique(keys_per_date)
        season_order = Dict("DJF" => 1, "MAM" => 2, "JJA" => 3, "SON" => 4)
        sort!(unique_keys; by = k -> (k[1], season_order[k[2]]))
        groups = [findall(==(k), keys_per_date) for k in unique_keys]
        new_times = [times[g[(length(g)+1)÷2]] for g in groups]
        return _aggregate_by_groups(var, groups, new_times)
    else
        error("Unknown aggregation level: $level")
    end
end

"""
    aggregate_obs(obs, sim, level::Symbol)

Window `obs` to the date range of the *raw* sim variable, then aggregate at
`level`. Pass the unaggregated sim — using an already-aggregated sim shrinks
the window because the mid-bin dates are interior to the actual coverage.
Returns `nothing` if there's no overlap.
"""
function aggregate_obs(obs, sim, level::Symbol)
    isnothing(obs) && return nothing
    obs_dates = ClimaAnalysis.dates(obs)
    sim_dates = ClimaAnalysis.dates(sim)
    isempty(sim_dates) && return nothing
    d0, d1 = sim_dates[1], sim_dates[end]
    if obs_dates[1] > d1 || obs_dates[end] < d0
        return nothing
    end
    i_first = findfirst(d -> d >= d0, obs_dates)
    i_last = findlast(d -> d <= d1, obs_dates)
    (isnothing(i_first) || isnothing(i_last) || i_first > i_last) && return nothing
    obs_windowed = ClimaAnalysis.window(
        obs,
        "time";
        left = obs.dims["time"][i_first],
        right = obs.dims["time"][i_last],
    )
    return aggregate_var(obs_windowed, level)
end

# ─── Metrics ────────────────────────────────────────────────────────────────

const METRIC_ROWS = (
    :sim_mean, :obs_mean, :bias, :rmse, :spatial_r, :amplitude_ratio, :phase_shift,
)
const METRIC_LABELS = Dict(
    :sim_mean => "Sim mean",
    :obs_mean => "Obs mean",
    :bias => "Bias",
    :rmse => "RMSE",
    :spatial_r => "Spatial r",
    :amplitude_ratio => "Amp ratio (sim/obs)",
    :phase_shift => "Phase shift (months)",
)
const METRIC_SCOPES = (:all_time, :selected, :DJF, :MAM, :JJA, :SON)
const SCOPE_LABELS = Dict(
    :all_time => "All-time",
    :selected => "Selected",
    :DJF => "DJF", :MAM => "MAM", :JJA => "JJA", :SON => "SON",
)

"""
    MetricsTable

Row-by-scope matrix of benchmark metrics. Access via `table[metric, scope]`,
e.g. `table[:rmse, :DJF]`. Use `format_cell` to render a cell as a string.
"""
struct MetricsTable
    values::Dict{Tuple{Symbol, Symbol}, Float64}
    units::String
end

MetricsTable(units::AbstractString) =
    MetricsTable(Dict{Tuple{Symbol, Symbol}, Float64}(), String(units))

Base.getindex(t::MetricsTable, m::Symbol, s::Symbol) =
    get(t.values, (m, s), NaN)

Base.setindex!(t::MetricsTable, v, m::Symbol, s::Symbol) =
    (t.values[(m, s)] = isnothing(v) ? NaN : Float64(v))

function format_cell(t::MetricsTable, m::Symbol, s::Symbol)
    v = t[m, s]
    isnan(v) && return "—"
    if m === :spatial_r || m === :amplitude_ratio
        return string(round(v; digits = 2))
    elseif m === :phase_shift
        return string(round(Int, v))
    else
        return string(round(v; digits = 2))
    end
end

function _empty_metrics(units)
    t = MetricsTable(units)
    for m in METRIC_ROWS, s in METRIC_SCOPES
        t[m, s] = NaN
    end
    return t
end

function _select_time_indices(var, idxs)
    time_idx = var.dim2index["time"]
    new_data = Array(selectdim(var.data, time_idx, idxs))
    new_dims = deepcopy(var.dims)
    new_dims["time"] = var.dims["time"][idxs]
    return ClimaAnalysis.remake(var; dims = new_dims, data = new_data)
end

function _filter_scope(sim_agg, obs_agg, scope::Symbol)
    if scope === :all_time || scope === :selected
        return sim_agg, obs_agg
    end
    season_str = String(scope)
    sim_dates = ClimaAnalysis.dates(sim_agg)
    sim_idxs = findall(d -> _SEASON_OF_MONTH[Dates.month(d)] == season_str, sim_dates)
    isempty(sim_idxs) && return nothing, nothing
    obs_dates = ClimaAnalysis.dates(obs_agg)
    obs_idxs = findall(d -> _SEASON_OF_MONTH[Dates.month(d)] == season_str, obs_dates)
    isempty(obs_idxs) && return nothing, nothing
    return _select_time_indices(sim_agg, sim_idxs),
           _select_time_indices(obs_agg, obs_idxs)
end

function _spatial_pearson(sim_2d, obs_resampled_2d)
    a = vec(sim_2d.data)
    b = vec(obs_resampled_2d.data)
    keep = .!isnan.(a) .& .!isnan.(b)
    n = count(keep)
    n < 2 && return NaN
    av, bv = a[keep], b[keep]
    ma, mb = sum(av) / n, sum(bv) / n
    num = sum((av .- ma) .* (bv .- mb))
    den = sqrt(sum((av .- ma) .^ 2) * sum((bv .- mb) .^ 2))
    den == 0 && return NaN
    return num / den
end

function _global_mean(var; mask)
    masked = isnothing(mask) ? var : mask(var)
    return ClimaAnalysis.weighted_average_lonlat(masked).data[]
end

function _time_mean(var)
    return ClimaAnalysis.average_time(var)
end

function _monthly_climatology(var)
    dates = ClimaAnalysis.dates(var)
    months = Dates.month.(dates)
    groups = [findall(==(m), months) for m in 1:12]
    # Drop missing months.
    keep_months = findall(!isempty, groups)
    isempty(keep_months) && return Float64[]
    means = Float64[]
    for m in keep_months
        sub = selectdim(var.data, var.dim2index["time"], groups[m])
        avg = _nanmean_along(sub, var.dim2index["time"])
        # Weighted spatial mean of avg
        sz = collect(size(var.data))
        sz[var.dim2index["time"]] = 1
        clim_var = ClimaAnalysis.remake(
            var;
            dims = let d = deepcopy(var.dims); d["time"] = [var.dims["time"][groups[m][1]]]; d end,
            data = reshape(avg, Tuple(sz)),
        )
        try
            push!(means, ClimaAnalysis.weighted_average_lonlat(ClimaAnalysis.apply_oceanmask(clim_var)).data[])
        catch
            push!(means, NaN)
        end
    end
    return means
end

function _compute_for_scope!(t::MetricsTable, sim_agg, obs_agg, scope::Symbol; mask, selected_idx = nothing)
    sim_sub, obs_sub = if scope === :selected
        isnothing(selected_idx) && return nothing
        sim_one = _select_time_indices(sim_agg, [selected_idx])
        sim_date = ClimaAnalysis.dates(sim_agg)[selected_idx]
        obs_dates = ClimaAnalysis.dates(obs_agg)
        obs_idx = argmin(abs.(Dates.value.(obs_dates .- sim_date)))
        obs_one = _select_time_indices(obs_agg, [obs_idx])
        sim_one, obs_one
    elseif scope === :all_time
        sim_agg, obs_agg
    else
        _filter_scope(sim_agg, obs_agg, scope)
    end
    (isnothing(sim_sub) || isnothing(obs_sub)) && return nothing
    try
        sim_tmean = _time_mean(sim_sub)
        obs_tmean = _time_mean(obs_sub)
        obs_resampled = ClimaAnalysis.resampled_as(obs_tmean, sim_tmean)
        masked_sim = isnothing(mask) ? sim_tmean : mask(sim_tmean)
        masked_obs = isnothing(mask) ? obs_resampled : mask(obs_resampled)
        t[:sim_mean, scope] = _global_mean(sim_tmean; mask)
        t[:obs_mean, scope] = _global_mean(obs_resampled; mask)
        t[:bias, scope] = ClimaAnalysis.global_bias(sim_tmean, obs_tmean; mask)[]
        t[:rmse, scope] = ClimaAnalysis.global_rmse(sim_tmean, obs_tmean; mask)[]
        t[:spatial_r, scope] = _spatial_pearson(masked_sim, masked_obs)
    catch e
        @debug "metrics scope $scope failed" exception = (e, catch_backtrace())
    end
    return nothing
end

"""
    compute_metrics(sim_agg, obs_agg; selected_idx, mask = apply_oceanmask, scopes = METRIC_SCOPES, compute_seasonal_diagnostics = true)

Compute the metrics table for current aggregated `sim_agg` and `obs_agg`. Both
must share comparable units. `selected_idx` is the current time-slider
position (used for the "Selected" scope; pass `nothing` to skip that column).
Pass `scopes = (:all_time, :selected)` to skip the per-season columns (much
faster); `compute_seasonal_diagnostics = false` skips amplitude/phase too.
"""
function compute_metrics(
    sim_agg, obs_agg;
    selected_idx = nothing,
    mask = ClimaAnalysis.apply_oceanmask,
    scopes = METRIC_SCOPES,
    compute_seasonal_diagnostics = true,
)
    units = ClimaAnalysis.units(sim_agg)
    t = _empty_metrics(units)
    isnothing(obs_agg) && return t
    for scope in scopes
        _compute_for_scope!(t, sim_agg, obs_agg, scope; mask, selected_idx)
    end
    if compute_seasonal_diagnostics
        sim_clim = _monthly_climatology(sim_agg)
        obs_clim = _monthly_climatology(obs_agg)
        if !isempty(sim_clim) && !isempty(obs_clim) && length(sim_clim) >= 2 && length(obs_clim) >= 2
            sim_amp = maximum(sim_clim) - minimum(sim_clim)
            obs_amp = maximum(obs_clim) - minimum(obs_clim)
            if obs_amp > 0
                t[:amplitude_ratio, :all_time] = sim_amp / obs_amp
            end
            sim_peak = argmax(sim_clim)
            obs_peak = argmax(obs_clim)
            shift = sim_peak - obs_peak
            shift = mod(shift + 6, 12) - 6
            t[:phase_shift, :all_time] = shift
        end
    end
    return t
end

"""
    update_metrics_scope!(t, sim_agg, obs_agg, scope; mask, selected_idx)

In-place update of a single scope column in an existing `MetricsTable` `t`.
"""
function update_metrics_scope!(
    t::MetricsTable, sim_agg, obs_agg, scope::Symbol;
    mask = ClimaAnalysis.apply_oceanmask, selected_idx = nothing,
)
    isnothing(obs_agg) && return t
    _compute_for_scope!(t, sim_agg, obs_agg, scope; mask, selected_idx)
    return t
end

"""
    compute_bias_map(sim_t, obs_t; mask = apply_oceanmask)

Return a 2D `OutputVar` of `sim - obs` for a single time slice. Both inputs
must be 2D (lon, lat). Returns `nothing` if the computation fails.
"""
function compute_bias_map(sim_t, obs_t; mask = ClimaAnalysis.apply_oceanmask)
    try
        b = ClimaAnalysis.bias(sim_t, obs_t; mask)
        return b
    catch e
        @debug "bias map computation failed" exception = (e, catch_backtrace())
        return nothing
    end
end
