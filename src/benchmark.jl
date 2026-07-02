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

function _era5_atmos_monthly_nc_path()
    try
        dir = artifact"era5_monthly_averages_atmos_single_level_1979_2024"
        return joinpath(dir, "era5_monthly_averages_atmos_single_level_197901-202410.nc")
    catch e
        @warn "ClimaViz: ERA5 atmos monthly artifact not available; prw benchmark disabled" exception=(e, catch_backtrace())
        return nothing
    end
end

function _gpcp_monthly_nc_path()
    try
        dir = artifact"precipitation_obs"
        return joinpath(dir, "precip.mon.mean.nc")
    catch e
        @warn "ClimaViz: GPCP precipitation artifact not available; pr benchmark disabled" exception=(e, catch_backtrace())
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
        obs_var.attributes["obs_source"] = "ERA5"
        return obs_var
    end
end

"""
    obs_source_name(obs)

Display name of the observation product behind `obs` (an `OutputVar` or
`nothing`), read from its `"obs_source"` attribute. The built-in loaders set it
("ERA5", "CarbonTracker", "GOSIF", …); custom loaders without the attribute
fall back to the generic `"obs"`.
"""
obs_source_name(obs) = isnothing(obs) ? "obs" : get(obs.attributes, "obs_source", "obs")

# ERA5 `mer` (mean evaporation rate) uses the ECMWF sign convention — negative
# for evaporation — while ClimaAtmos `evspsbl` is positive for evaporation, so
# the conversion flips the sign while rescaling kg m⁻² s⁻¹ (≡ mm s⁻¹ of liquid
# water) to the dashboard's water-flux display unit (see `to_display_units`).
function _era5_evap_loader()
    return function (_start_date)
        path = _era5_monthly_nc_path()
        isnothing(path) && return nothing
        obs_var = ClimaAnalysis.OutputVar(path, "mer")
        obs_var = ClimaAnalysis.convert_units(
            obs_var,
            _DISPLAY_WATER_UNITS;
            conversion_function = u -> u * -_SECONDS_PER_DAY,
        )
        obs_var.attributes["short_name"] = "evspsbl"
        obs_var.attributes["obs_source"] = "ERA5"
        return obs_var
    end
end

# ERA5 `tcw` is total column water (vapour + cloud condensate) whereas the sim
# `prw` is water-vapour path only; condensate is ~1 % of the column, so tcw is
# still a fair reference. The ERA5 monthly artifacts carry no tcwv field.
function _era5_prw_loader()
    return function (_start_date)
        path = _era5_atmos_monthly_nc_path()
        isnothing(path) && return nothing
        obs_var = ClimaAnalysis.OutputVar(path, "tcw")
        (ClimaAnalysis.units(obs_var) == "kg m**-2") &&
            (obs_var = ClimaAnalysis.set_units(obs_var, "kg m^-2"))
        obs_var.attributes["short_name"] = "prw"
        obs_var.attributes["obs_source"] = "ERA5"
        return obs_var
    end
end

"""
    default_era5_obs()

Built-in `Dict{String, Function}` mapping simulation short names to ERA5
monthly observation loaders. Each loader takes a `start_date` and returns a
`ClimaAnalysis.OutputVar` aligned to that origin.

Covers the surface fluxes (W m⁻², monthly, 1°×1°) under both the ClimaLand
names (`lhf`, `shf`, `lwu`, `swu`) and the ClimaAtmos/CMIP names (`hfls`,
`hfss`, `rlus`, `rsus`) — the same ERA5 fields and sign conventions either
way — plus evaporation (`evspsbl`, from `mer`, in the mm day⁻¹ display unit)
and water-vapour path (`prw`, from `tcw`, kg m⁻²). Returns an empty Dict if
the underlying artifacts are unavailable.
"""
function default_era5_obs()
    obs = Dict{String, Function}()
    if !isnothing(_era5_monthly_nc_path())
        merge!(
            obs,
            Dict{String, Function}(
                "lhf" => _era5_loader("mslhf", "lhf"; flip_sign = true),
                "shf" => _era5_loader("msshf", "shf"; flip_sign = true),
                "lwu" => _era5_loader("msuwlwrf", "lwu"; flip_sign = false),
                "swu" => _era5_loader("msuwswrf", "swu"; flip_sign = false),
                "hfls" => _era5_loader("mslhf", "hfls"; flip_sign = true),
                "hfss" => _era5_loader("msshf", "hfss"; flip_sign = true),
                "rlus" => _era5_loader("msuwlwrf", "rlus"; flip_sign = false),
                "rsus" => _era5_loader("msuwswrf", "rsus"; flip_sign = false),
                "evspsbl" => _era5_evap_loader(),
            ),
        )
    end
    isnothing(_era5_atmos_monthly_nc_path()) ||
        (obs["prw"] = _era5_prw_loader())
    return obs
end

"""
    default_gpcp_obs()

Built-in `Dict{String, Function}` mapping `pr` to a GPCP monthly precipitation
loader (2.5°×2.5°, 1979–present, from the `precipitation_obs` artifact). GPCP
stores mm/day — the dashboard's water-flux display unit, into which the sim
`pr` is converted by [`to_display_units`](@ref) — so only the unit string is
normalized. Returns an empty Dict if the underlying artifact is unavailable.
"""
function default_gpcp_obs()
    isnothing(_gpcp_monthly_nc_path()) && return Dict{String, Function}()
    return Dict{String, Function}(
        "pr" => function (_start_date)
            path = _gpcp_monthly_nc_path()
            isnothing(path) && return nothing
            obs_var = ClimaAnalysis.OutputVar(path, "precip")
            obs_var = ClimaAnalysis.replace(obs_var, missing => NaN)
            obs_var = ClimaAnalysis.set_units(obs_var, _DISPLAY_WATER_UNITS)
            obs_var.attributes["short_name"] = "pr"
            obs_var.attributes["obs_source"] = "GPCP"
            return obs_var
        end,
    )
end

# ─── Inversion-derived carbon observations ────────────────────────────────────
#
# Monthly 1°×1° carbon fluxes from the ClimaLand `inversion_nee` artifact
# (`derived_nee_gpp_er_rh_2002_2020.nc`, 2002–2020): CarbonTracker CT2022 NEE,
# GOSIF-GPP v2, residual ER (= NEE + GPP), and Hashimoto-2015 Rh. See ClimaLand's
# `get_inversion_obs_var_dict` — this mirrors its loading, minus the calibration
# unit string. The inversion products are natively g C m^-2 day^-1, which is also
# the dashboard's display unit for carbon (see `to_display_units`), so the loaders
# keep that unit and the sim side is converted to match. Sign conventions already
# match the model (positive = source for nee/er/hr, positive = uptake for gpp), so
# no flip is applied.

# mol CO2 (1:1 with mol C) → g C, per molar mass of carbon, then per day.
const _G_C_PER_MOL = 12.011
const _SECONDS_PER_DAY = 86400.0

# ─── Display-unit conversion ──────────────────────────────────────────────────
#
# ClimaLand stores carbon fluxes in mol CO2 m^-2 s^-1 and the atmos/land models
# store water fluxes in kg m^-2 s^-1, where values are ~1e-6 and the metrics
# table would render every cell as 0.00. For display we rescale them — and only
# them — to the more legible g C m^-2 day^-1 and mm day^-1. Detection is by unit
# string so every such flux (with or without an observation) is caught while
# energy fluxes (W m^-2) pass through.

const _CARBON_FLUX_UNITS = ("mol CO2 m^-2 s^-1", "mol CO2 m**-2 s**-1")
const _DISPLAY_CARBON_UNITS = "g C m^-2 day^-1"

is_carbon_flux(var) = ClimaAnalysis.units(var) in _CARBON_FLUX_UNITS

const _WATER_FLUX_UNITS = ("kg m^-2 s^-1", "kg m**-2 s**-1")
const _DISPLAY_WATER_UNITS = "mm day^-1"

# ClimaAtmos reports precipitation-type fluxes as negative downward mass
# fluxes; flip them for display so precipitation is positive, matching GPCP
# and everyday convention (same flip as ClimaCoupler's leaderboard).
const _NEGATIVE_DOWN_WATER_FLUXES = ("pr", "prra", "prsn")

is_water_flux(var) = ClimaAnalysis.units(var) in _WATER_FLUX_UNITS

"""
    to_display_units(var)

Convert a freshly-loaded simulation `OutputVar` to the units the dashboard
displays. Carbon fluxes are rescaled from `mol CO2 m^-2 s^-1` to
`g C m^-2 day^-1` (× molar mass of C × seconds/day); water fluxes from
`kg m^-2 s^-1` (≡ mm s⁻¹ of liquid water) to `mm day^-1` (× seconds/day, with
a sign flip for the negative-downward precipitation fluxes `pr`/`prra`/`prsn`);
all other variables are returned unchanged. Apply this once, at each point a
sim variable is loaded, so the map, bias panel, time series, and metrics all
share one consistent unit.
"""
function to_display_units(var)
    if is_carbon_flux(var)
        return ClimaAnalysis.convert_units(
            var, _DISPLAY_CARBON_UNITS;
            conversion_function = u -> u * _G_C_PER_MOL * _SECONDS_PER_DAY,
        )
    elseif is_water_flux(var)
        sign = get(var.attributes, "short_name", "") in _NEGATIVE_DOWN_WATER_FLUXES ? -1.0 : 1.0
        return ClimaAnalysis.convert_units(
            var, _DISPLAY_WATER_UNITS;
            conversion_function = u -> u * sign * _SECONDS_PER_DAY,
        )
    end
    return var
end

function _inversion_nc_path()
    try
        dir = artifact"inversion_nee"
        return joinpath(dir, "derived_nee_gpp_er_rh_2002_2020.nc")
    catch e
        @warn "ClimaViz: inversion_nee artifact not available; carbon benchmark disabled" exception=(e, catch_backtrace())
        return nothing
    end
end

# Scale every time slice in place by `1 / daysinmonth(date)`, converting a
# monthly *total* (… month⁻¹) to a daily *rate* (… day⁻¹). Mirrors ClimaLand's
# `_monthly_total_to_daily_rate!`; uses actual days-in-month to avoid the ±5%
# spurious seasonality a constant 30.44 would introduce.
function _monthly_total_to_daily_rate!(var)
    dates = ClimaAnalysis.dates(var)
    factors = 1.0 ./ Float64.(Dates.daysinmonth.(dates))
    t_idx = var.dim2index["time"]
    shape = ntuple(d -> d == t_idx ? length(factors) : 1, ndims(var.data))
    var.data .*= reshape(factors, shape)
    return var
end

# Build a loader for one inversion carbon variable. `varname_obs` is the name in
# the NetCDF file (`nee`/`gpp`/`er`/`rh`); `varname_sim` is the matching sim
# short_name (`nee`/`gpp`/`er`/`hr`). `monthly_total = true` first rescales a
# monthly total to a daily rate (nee/gpp/er); `rh` is already a daily rate.
# `source` is the product display name shown in the UI (legend, bias title, …).
function _inversion_loader(varname_obs, varname_sim; monthly_total::Bool, source::String)
    return function (_start_date)
        path = _inversion_nc_path()
        isnothing(path) && return nothing
        obs_var = ClimaAnalysis.OutputVar(path, varname_obs)
        obs_var = ClimaAnalysis.replace(obs_var, missing => NaN)
        # → g C m⁻² day⁻¹ (the dashboard display unit; sim is converted to match)
        monthly_total && _monthly_total_to_daily_rate!(obs_var)
        obs_var = ClimaAnalysis.set_units(obs_var, _DISPLAY_CARBON_UNITS)
        obs_var.attributes["short_name"] = varname_sim
        obs_var.attributes["obs_source"] = source
        return obs_var
    end
end

"""
    default_inversion_obs()

Built-in `Dict{String, Function}` mapping ClimaLand carbon short names to
inversion-derived observation loaders from the `inversion_nee` artifact. Each
loader returns a `ClimaAnalysis.OutputVar` in `g C m⁻² day⁻¹` (the dashboard's
carbon display unit), monthly 1°×1°, 2002–2020.

Covers: `nee` (CarbonTracker CT2022), `gpp` (GOSIF-GPP v2), `er` (residual
NEE + GPP), `hr` (Hashimoto-2015 Rh). Returns an empty Dict if the underlying
artifact is unavailable.
"""
function default_inversion_obs()
    isnothing(_inversion_nc_path()) && return Dict{String, Function}()
    return Dict{String, Function}(
        "nee" => _inversion_loader("nee", "nee"; monthly_total = true, source = "CarbonTracker"),
        "gpp" => _inversion_loader("gpp", "gpp"; monthly_total = true, source = "GOSIF"),
        "er"  => _inversion_loader("er", "er"; monthly_total = true, source = "CarbonTracker+GOSIF"),
        "hr"  => _inversion_loader("rh", "hr"; monthly_total = false, source = "Hashimoto2015"),
    )
end

"""
    default_obs()

Combined built-in observation set: ERA5 monthly energy/water fluxes and
water-vapour path ([`default_era5_obs`](@ref): `lhf`, `shf`, `lwu`, `swu` and
their CMIP aliases, `evspsbl`, `prw`), the inversion-derived carbon fluxes
([`default_inversion_obs`](@ref): `nee`, `gpp`, `er`, `hr`), and GPCP
precipitation ([`default_gpcp_obs`](@ref): `pr`). This is the default
observation registry for [`dashboard`](@ref) and
[`precompute_dashboard_cache`](@ref).
"""
default_obs() =
    merge(default_era5_obs(), default_inversion_obs(), default_gpcp_obs())

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
    elseif level == :monthly
        return "Monthly"
    elseif level == :daily
        return "Daily"
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
- `:monthly`: one frame per (year, month) bin (for daily/hourly-native data).
- `:daily`: one frame per calendar day (for hourly-native data).
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
    elseif level == :monthly
        keys_per_date = map(d -> (Dates.year(d), Dates.month(d)), dates)
        unique_keys = sort!(unique(keys_per_date))
        groups = [findall(==(k), keys_per_date) for k in unique_keys]
        new_times = [times[g[(length(g)+1)÷2]] for g in groups]
        return _aggregate_by_groups(var, groups, new_times)
    elseif level == :daily
        keys_per_date = map(d -> Dates.Date(d), dates)
        unique_keys = sort!(unique(keys_per_date))
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
    return aggregate_var(_align_longitude(obs_windowed, sim), level)
end

# Wrap obs longitudes into sim's convention (e.g. ERA5 [0, 360] → sim [-180, 180])
# so that timeseries lookups by sim-clicked lon hit the right cells. `resampled_as`
# already handles either convention, so the bias map is unaffected.
function _align_longitude(obs, sim)
    (ClimaAnalysis.has_longitude(obs) && ClimaAnalysis.has_longitude(sim)) || return obs
    sim_lon = sim.dims[ClimaAnalysis.longitude_name(sim)]
    obs_lon = obs.dims[ClimaAnalysis.longitude_name(obs)]
    lo = minimum(sim_lon)
    omin, omax = extrema(obs_lon)
    omin >= lo && omax < lo + 360 && return obs
    return ClimaAnalysis.shift_longitude(obs, lo, lo + 360)
end

# ─── Metrics ────────────────────────────────────────────────────────────────

const METRIC_ROWS = (
    :sim_mean, :obs_mean, :bias, :rmse,
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

const _LABEL_TO_SCOPE = Dict(v => k for (k, v) in SCOPE_LABELS)

label_to_scope(label::AbstractString) = get(_LABEL_TO_SCOPE, String(label), :all_time)

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
    if m === :phase_shift
        return string(round(Int, v))
    elseif m === :spatial_r || m === :amplitude_ratio
        return string(round(v; digits = 2))
    elseif v == 0 || abs(v) >= 0.1
        return string(round(v; digits = 2))
    else
        # Small magnitudes (e.g. a near-zero NEE bias) would round to 0.00 at two
        # decimals; fall back to significant figures so they stay legible.
        return string(round(v; sigdigits = 3))
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
