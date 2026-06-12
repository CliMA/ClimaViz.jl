using Serialization

# ─── Persistent benchmark cache ───────────────────────────────────────────────
#
# The expensive, recurring work in the dashboard is the obs↔sim benchmark:
# regridding ERA5 observations onto the simulation grid (`resampled_as`) and the
# ocean-masked metrics (`global_rmse`, `global_bias`, weighted means). These are
# fully deterministic given (short_name, reduction, period, aggregation level)
# and the source file's contents — so we compute them once and persist them next
# to the simulation output. The raw simulation fields are NOT cached; the map /
# time-series / profile views keep reading them lazily.
#
# This file holds the storage layer (entry struct, fingerprinting, read/write)
# and the batch `precompute_dashboard_cache`. Wiring into the live dashboard is
# in events.jl (`_try_cached_benchmark!`).

const _CACHE_FORMAT_VERSION = 1
const _CACHE_SUBDIR = ".climaviz_cache"

"""
    BenchmarkCacheEntry

One cached benchmark product for a given (variable, reduction, period, level).
Holds only small, sim-grid-aligned derived data — never the raw simulation field.

- `obs_resampled`: ERA5 obs regridded onto the sim grid, `[lon, lat, n]`, where
  `n = min(length(sim_times), length(obs_times))` (the comparison window).
- `bias_limits`: symmetric colorbar limits for the full time-mean bias map.
- `metrics_per_t`: the `:selected`-scope metric values for each time index
  `1:n` (stored as the raw `MetricsTable.values` dict, rebuilt on load).
- `fingerprint`: source-file signature used for invalidation.
"""
struct BenchmarkCacheEntry
    version::Int
    fingerprint::String
    lon::Vector{Float64}
    lat::Vector{Float64}
    n::Int
    bias_limits::Tuple{Float64, Float64}
    obs_resampled::Array{Float64, 3}
    metrics_per_t::Vector{Dict{Tuple{Symbol, Symbol}, Float64}}
    units::String
end

"""
    BenchmarkCache(simulation_path; enabled = true)

Controller for the persistent benchmark cache. Resolves (and tests writability
of) `<simulation_path>/.climaviz_cache`. If the directory can't be created or
written, persistence is disabled but the in-memory layer (`mem`) still serves
hits within a session. `enabled = false` turns the disk layer off entirely.
"""
mutable struct BenchmarkCache
    dir::Union{String, Nothing}
    mem::Dict{Tuple{String, String, String, Symbol}, BenchmarkCacheEntry}
    enabled::Bool
end

function BenchmarkCache(simulation_path::AbstractString; enabled::Bool = true)
    dir = enabled ? _resolve_cache_dir(simulation_path) : nothing
    return BenchmarkCache(
        dir,
        Dict{Tuple{String, String, String, Symbol}, BenchmarkCacheEntry}(),
        enabled,
    )
end

function _resolve_cache_dir(simulation_path::AbstractString)
    dir = joinpath(simulation_path, _CACHE_SUBDIR)
    try
        isdir(dir) || mkpath(dir)
        probe = joinpath(dir, ".write_test")
        open(probe, "w") do io
            write(io, "ok")
        end
        rm(probe; force = true)
        return dir
    catch e
        @warn "ClimaViz: benchmark cache dir not writable; disk persistence off" dir exception = e
        return nothing
    end
end

# ─── Source fingerprint (invalidation) ────────────────────────────────────────

_sanitize(s) = replace(string(s), r"[^A-Za-z0-9_.-]" => "_")

function _entry_filename(key::Tuple)
    short_name, reduction, period, level = key
    return string(
        _sanitize(short_name), "__", _sanitize(reduction), "__",
        _sanitize(period), "__", _sanitize(level), ".jls",
    )
end

# Signature of the NetCDF file(s) backing (short_name, reduction, period):
# basename + byte size + mtime for each. Any change re-bakes the entry.
function _source_fingerprint(simdir, short_name, reduction, period)
    paths = String[]
    try
        by_coord = simdir.variable_paths[short_name][reduction][period]
        for (_, v) in by_coord
            append!(paths, v)
        end
    catch
        return ""
    end
    sort!(paths)
    parts = String[]
    for p in paths
        st = try
            stat(p)
        catch
            nothing
        end
        push!(parts, isnothing(st) ? "$(basename(p)):missing" :
                     "$(basename(p)):$(st.size):$(st.mtime)")
    end
    return join(parts, "|")
end

# ─── Read / write ─────────────────────────────────────────────────────────────

"""
    get_cached_entry(cache, key, fingerprint) -> BenchmarkCacheEntry | nothing

Return a valid cached entry for `key = (short_name, reduction, period, level)`,
checking the in-memory layer first, then disk. Returns `nothing` on any miss,
format/version mismatch, or fingerprint mismatch (stale source). A corrupt or
unreadable file is treated as a miss — the cache is always regenerable.
"""
function get_cached_entry(cache::BenchmarkCache, key, fingerprint::AbstractString)
    if haskey(cache.mem, key)
        entry = cache.mem[key]
        entry.fingerprint == fingerprint && return entry
    end
    isnothing(cache.dir) && return nothing
    file = joinpath(cache.dir, _entry_filename(key))
    isfile(file) || return nothing
    entry = try
        deserialize(file)
    catch e
        @debug "ClimaViz: unreadable cache entry; will recompute" file exception = e
        return nothing
    end
    (entry isa BenchmarkCacheEntry) || return nothing
    entry.version == _CACHE_FORMAT_VERSION || return nothing
    entry.fingerprint == fingerprint || return nothing
    cache.mem[key] = entry
    return entry
end

"""
    put_cached_entry!(cache, key, entry)

Store `entry` in the in-memory layer and (best-effort, atomically) on disk.
Write failures are warned and swallowed — the session keeps working from memory.
"""
function put_cached_entry!(cache::BenchmarkCache, key, entry::BenchmarkCacheEntry)
    cache.mem[key] = entry
    isnothing(cache.dir) && return entry
    file = joinpath(cache.dir, _entry_filename(key))
    try
        tmp = file * ".tmp"
        serialize(tmp, entry)
        mv(tmp, file; force = true)
    catch e
        @warn "ClimaViz: failed to write cache entry" file exception = e
    end
    return entry
end

# ─── Compute one entry ────────────────────────────────────────────────────────

function _start_date_of(var)
    try
        return Dates.DateTime(var.attributes["start_date"])
    catch
        d = ClimaAnalysis.dates(var)
        return isempty(d) ? nothing : d[1]
    end
end

"""
    compute_benchmark_entry(sim_agg, obs_agg, fingerprint; mask = apply_oceanmask) -> BenchmarkCacheEntry

Do the heavy benchmark work for one already-aggregated (sim, obs) pair: regrid
every obs slice onto the sim grid, derive the bias-map colorbar limits, and
compute the `:selected`-scope metrics for each time index. `obs_agg` must be the
obs windowed/aligned to `sim_agg` (see `aggregate_obs`). `mask` is the spatial
mask used for the metrics (see `MASK_SPECS`); the caller must bake the matching
`cache_tag` into `fingerprint` so mask changes invalidate the entry.
"""
function compute_benchmark_entry(sim_agg, obs_agg, fingerprint::AbstractString; mask = ClimaAnalysis.apply_oceanmask)
    sim_dates = ClimaAnalysis.dates(sim_agg)
    obs_dates = ClimaAnalysis.dates(obs_agg)
    n = min(length(sim_dates), length(obs_dates))
    sim_trunc = _select_time_indices(sim_agg, collect(1:n))
    obs_trunc = _select_time_indices(obs_agg, collect(1:n))

    lon = collect(Float64.(sim_trunc.dims["lon"]))
    lat = collect(Float64.(sim_trunc.dims["lat"]))

    obs_resampled = Array{Float64, 3}(undef, length(lon), length(lat), n)
    for t in 1:n
        sim_t = ClimaAnalysis.slice(sim_trunc; time = sim_trunc.dims["time"][t])
        obs_t = ClimaAnalysis.slice(obs_trunc; time = obs_trunc.dims["time"][t])
        obs_resampled[:, :, t] .= ClimaAnalysis.resampled_as(obs_t, sim_t).data
    end

    sim_tmean = ClimaAnalysis.average_time(sim_trunc)
    obs_tmean = ClimaAnalysis.average_time(obs_trunc)
    obs_tmean_re = ClimaAnalysis.resampled_as(obs_tmean, sim_tmean)
    bias_limits = _symmetric_limits(filter(!isnan, vec(sim_tmean.data .- obs_tmean_re.data)))

    metrics_per_t = Vector{Dict{Tuple{Symbol, Symbol}, Float64}}(undef, n)
    for t in 1:n
        mt = compute_metrics(
            sim_trunc, obs_trunc;
            selected_idx = t, mask = mask, scopes = (:selected,),
            compute_seasonal_diagnostics = false,
        )
        metrics_per_t[t] = copy(mt.values)
    end

    return BenchmarkCacheEntry(
        _CACHE_FORMAT_VERSION, fingerprint, lon, lat, n,
        bias_limits, obs_resampled, metrics_per_t,
        ClimaAnalysis.units(sim_agg),
    )
end

# ─── Batch precompute ─────────────────────────────────────────────────────────

"""
    precompute_dashboard_cache(path; obs = default_era5_obs(), verbose = true, mask_kind = :land)

Warm the persistent benchmark cache for every (variable, reduction, period,
aggregation level) in `path` that has a registered observation. Already-cached,
up-to-date entries are skipped (cheap fingerprint check), so this is safe to
re-run — e.g. after regenerating the longrun, or on each server restart.

`mask_kind` selects the spatial mask for the metrics (see `MASK_SPECS`):
`:land` (ocean-masked, the default), `:globe` (atmos components of coupled
runs) or `:ocean`. It must match what the dashboard will use for this output.

Run this once after producing the simulation output (or in CI). The dashboard
reads whatever is present and falls back to live computation on a miss, so
precomputing is purely a responsiveness optimization.

Returns the `BenchmarkCache`.
"""
function precompute_dashboard_cache(path; obs = default_obs(), verbose = true, mask_kind::Symbol = :land)
    simdir = ClimaAnalysis.SimDir(path)
    cache = BenchmarkCache(path; enabled = true)
    if isnothing(cache.dir)
        @warn "ClimaViz: cache directory unavailable; nothing precomputed" path
        return cache
    end
    n_done = 0
    n_skip = 0
    for short_name in sort(collect(keys(simdir.vars)))
        haskey(obs, short_name) || continue
        for reduction in keys(simdir.vars[short_name])
            for period in keys(simdir.vars[short_name][reduction])
                var = try
                    to_display_units(get(simdir; short_name = short_name, reduction = reduction, period = period))
                catch e
                    @warn "ClimaViz: skip $short_name/$reduction/$period (load failed)" exception = e
                    continue
                end
                _has_lonlat_only(var) || continue  # obs are 2D surface fields
                bundle = ObsBundle(obs; start_date = _start_date_of(var))
                o = get_obs(bundle, short_name)
                isnothing(o) && continue
                fingerprint = _source_fingerprint(simdir, short_name, reduction, period) *
                    mask_spec(mask_kind).cache_tag
                for level in available_levels(var)
                    key = (short_name, reduction, period, level)
                    if !isnothing(get_cached_entry(cache, key, fingerprint))
                        n_skip += 1
                        verbose && @info "  skip (up-to-date)" var = short_name reduction period level
                        continue
                    end
                    obs_agg = aggregate_obs(o, var, level)
                    isnothing(obs_agg) && continue
                    sim_agg = aggregate_var(var, level)
                    entry = compute_benchmark_entry(sim_agg, obs_agg, fingerprint; mask = mask_spec(mask_kind).mask)
                    put_cached_entry!(cache, key, entry)
                    n_done += 1
                    verbose && @info "  cached" var = short_name reduction period level n = entry.n
                end
            end
        end
    end
    verbose && @info "ClimaViz: precompute complete" computed = n_done skipped = n_skip dir = cache.dir
    return cache
end
