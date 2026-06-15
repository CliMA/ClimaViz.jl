# ─── ClimaCoupler multi-component outputs ────────────────────────────────────
#
# A ClimaCoupler run writes one diagnostics folder per component instead of a
# single flat output directory:
#
#   <run>/clima_atmos/   <run>/clima_land/   <run>/clima_ocean/   <run>/clima_seaice/
#
# `dashboard(path; coupled = true)` discovers these, builds one `SimDir` per
# non-empty component, and adds a "Component:" menu that swaps the active
# `SimDir` (and its per-component benchmark cache) at runtime. All components
# are assumed to share the same diagnostic lon/lat grid — ClimaCoupler regrids
# every component's diagnostics onto one grid, and the dashboard's figures are
# built against a single grid.

const COUPLER_COMPONENTS = (
    "atmos" => "clima_atmos",
    "land" => "clima_land",
    "ocean" => "clima_ocean",
    "seaice" => "clima_seaice",
)

# Restrict an atmos SimDir to the monthly ("1M") diagnostics on the native
# grid. The atmos folder also holds instantaneous fields (`orog_inst.nc`),
# restart HDF5s, and `*_1M_average_pressure.nc` variants (the same field on
# pressure levels); the latter make `get(simdir; short_name, reduction,
# period)` ambiguous ("Found multiple coordinates"), so only the
# `coord_type === nothing` (native) entries are kept. Mutates and returns
# `simdir`.
function _prune_to_1M!(simdir)
    for store in (simdir.vars, simdir.variable_paths)
        for short_name in collect(keys(store))
            by_reduction = store[short_name]
            for reduction in collect(keys(by_reduction))
                by_period = by_reduction[reduction]
                for period in collect(keys(by_period))
                    if period != "1M"
                        delete!(by_period, period)
                        continue
                    end
                    by_coord = by_period[period]
                    for coord in collect(keys(by_coord))
                        isnothing(coord) || delete!(by_coord, coord)
                    end
                    isempty(by_coord) && delete!(by_period, period)
                end
                isempty(by_period) && delete!(by_reduction, reduction)
            end
            isempty(by_reduction) && delete!(store, short_name)
        end
    end
    return simdir
end

# Directory a component's `SimDir` should read. `SimDir` walks the tree with
# `walkdir`, so if a component folder holds both the current run's
# `output_active`/`output_NNNN` subfolder *and* stale loose `.nc` files left at
# the top level from an earlier run, it picks up each variable twice and tries
# to stitch their overlapping time axes ("Time dimension is not in
# non-decreasing order"). When an `output_active` symlink (or, failing that, the
# highest-numbered `output_NNNN`) exists, read from it so only the current run's
# files are seen; otherwise read the folder itself (components like land/ocean
# write their diagnostics as loose files with no `output_*` subdir).
function _resolve_sim_path(component_path)
    active = joinpath(component_path, "output_active")
    isdir(active) && return active
    numbered = filter(readdir(component_path)) do entry
        startswith(entry, "output_") &&
            !isnothing(tryparse(Int, last(split(entry, "_")))) &&
            isdir(joinpath(component_path, entry))
    end
    isempty(numbered) && return component_path
    return joinpath(component_path, maximum(numbered))
end

"""
    discover_components(path)

Scan a ClimaCoupler output directory for component subfolders
(`clima_atmos`, `clima_land`, `clima_ocean`, `clima_seaice`) and return a
`Vector` of `(label = "atmos", path = …, simdir = SimDir(…))` NamedTuples for
every component that contains at least one readable variable. Each `SimDir` is
read from the component's current-run output folder (`output_active` /
`output_NNNN`) when present, ignoring stale loose `.nc` files left at the
component root (see `_resolve_sim_path`); `path` stays the component root so the
`.climaviz_cache` location is stable across runs. The atmos component is pruned
to its monthly (`_1M_`) native-grid diagnostics (see `_prune_to_1M!`); empty
folders (e.g. an inactive ocean) are skipped.
"""
function discover_components(path)
    components = NamedTuple{(:label, :path, :simdir), Tuple{String, String, Any}}[]
    for (label, subdir) in COUPLER_COMPONENTS
        component_path = joinpath(path, subdir)
        isdir(component_path) || continue
        simdir = try
            ClimaAnalysis.SimDir(_resolve_sim_path(component_path))
        catch e
            @warn "ClimaViz: failed to read coupler component" component_path exception = e
            continue
        end
        label == "atmos" && _prune_to_1M!(simdir)
        isempty(simdir.vars) && continue
        push!(components, (label = label, path = component_path, simdir = simdir))
    end
    return components
end

# The run's start_date as an ISO string, read from the first variable of
# `simdir` (atmos in practice). Used to patch components whose NetCDF files
# lack the attribute (possible for land). Returns `nothing` if unavailable.
function _component_start_date(simdir)
    isempty(simdir.vars) && return nothing
    short_name = first(_sorted_vars(simdir))
    var = try
        get(simdir; short_name = short_name)
    catch e
        @warn "ClimaViz: could not load $short_name to read start_date" exception = e
        return nothing
    end
    return Base.get(var.attributes, "start_date", nothing)
end
