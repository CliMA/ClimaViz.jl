# ─── Model performance summary ───────────────────────────────────────────────
#
# One-glance benchmark overview: a modal overlay (opened by the "Model summary"
# menu button) showing, for every variable of the active SimDir that has a
# registered observation, the global ocean-masked RMSE (and bias) against the
# benchmark over the whole simulation period, per season (All-time / DJF / MAM /
# JJA / SON). Cells are colored by RMSE relative to the observed all-time mean,
# green → red, so model performance reads as one image.
#
# The table is plain DOM (no WebGL), so it renders fine inside an initially
# hidden overlay. Results are cached per component for the session and, when
# the benchmark cache is enabled, persisted to `.climaviz_cache/summary.jls`
# (fingerprinted like the per-variable benchmark entries).

const _SUMMARY_SCOPES = (:all_time, :DJF, :MAM, :JJA, :SON)
const _SUMMARY_SCOPE_TITLES = ("All-time", "DJF", "MAM", "JJA", "SON")
const _SUMMARY_CACHE_FILE = "summary.jls"

# ─── Data ─────────────────────────────────────────────────────────────────────

# Candidate (short_name, reduction, period) triples: variables of `simdir` with
# a registered obs loader, taking the first reduction/period like the menus do.
function _summary_candidates(simdir, obs_bundle)
    candidates = Tuple{String, String, Any}[]
    for short_name in _sorted_vars(simdir)
        has_obs(obs_bundle, short_name) || continue
        reduction = first(keys(simdir.vars[short_name]))
        period = first(keys(simdir.vars[short_name][reduction]))
        push!(candidates, (short_name, reduction, period))
    end
    return candidates
end

_summary_fingerprint(simdir, candidates) = join(
    (string(sn, "/", red, "/", per, "=", _source_fingerprint(simdir, sn, red, per))
     for (sn, red, per) in candidates),
    "||",
)

"""
    compute_summary_rows(simdir, obs_bundle; fallback_start_date, mask, on_progress)

Compute the model-summary benchmark rows for `simdir`: one NamedTuple per
variable with a registered observation, holding the per-scope global RMSE and
bias (`Dict{Symbol, Float64}` keyed by `_SUMMARY_SCOPES`) over the full
overlapping sim/obs period, plus units, the obs product name and the observed
all-time mean (used to normalize the cell colors). `mask` is the component's
spatial mask (see `MASK_SPECS`). `on_progress` is called with each short_name
before its (slow) metrics computation.
"""
function compute_summary_rows(
    simdir, obs_bundle;
    fallback_start_date = nothing, mask = ClimaAnalysis.apply_oceanmask, on_progress = nothing,
)
    rows = NamedTuple[]
    for (short_name, reduction, period) in _summary_candidates(simdir, obs_bundle)
        var = try
            load_sim_var(simdir, short_name, reduction, period; fallback_start_date)
        catch e
            @warn "ClimaViz summary: failed to load $short_name" exception = e
            continue
        end
        _has_lonlat_only(var) || continue
        obs = get_obs(obs_bundle, short_name)
        isnothing(obs) && continue
        obs_agg = aggregate_obs(obs, var, :native)
        isnothing(obs_agg) && continue
        isnothing(on_progress) || on_progress(short_name)
        n = min(length(ClimaAnalysis.dates(var)), length(ClimaAnalysis.dates(obs_agg)))
        sim_trunc = _select_time_indices(var, collect(1:n))
        obs_trunc = _select_time_indices(obs_agg, collect(1:n))
        t = compute_metrics(
            sim_trunc, obs_trunc;
            mask = mask, scopes = _SUMMARY_SCOPES, compute_seasonal_diagnostics = false,
        )
        push!(rows, (
            short_name = short_name,
            units = ClimaAnalysis.units(var),
            obs_name = obs_source_name(obs_agg),
            rmse = Dict(s => t[:rmse, s] for s in _SUMMARY_SCOPES),
            bias = Dict(s => t[:bias, s] for s in _SUMMARY_SCOPES),
            obs_mean = t[:obs_mean, :all_time],
        ))
    end
    return rows
end

# ─── Persistence (piggybacks on the benchmark cache directory) ────────────────

function _cached_summary_rows(bench_cache, fingerprint)
    (isnothing(bench_cache) || isnothing(bench_cache.dir)) && return nothing
    file = joinpath(bench_cache.dir, _SUMMARY_CACHE_FILE)
    isfile(file) || return nothing
    payload = try
        deserialize(file)
    catch e
        @debug "ClimaViz: unreadable summary cache; will recompute" file exception = e
        return nothing
    end
    payload isa NamedTuple || return nothing
    Base.get(payload, :version, 0) == _CACHE_FORMAT_VERSION || return nothing
    Base.get(payload, :fingerprint, "") == fingerprint || return nothing
    return payload.rows
end

function _store_summary_rows!(bench_cache, fingerprint, rows)
    (isnothing(bench_cache) || isnothing(bench_cache.dir)) && return rows
    file = joinpath(bench_cache.dir, _SUMMARY_CACHE_FILE)
    try
        tmp = file * ".tmp"
        serialize(tmp, (version = _CACHE_FORMAT_VERSION, fingerprint = fingerprint, rows = rows))
        mv(tmp, file; force = true)
    catch e
        @warn "ClimaViz: failed to write summary cache" file exception = e
    end
    return rows
end

"""
    precompute_summary!(simdir, bench_cache, obs; fallback_start_date = nothing, mask_kind = :land)

Warm the persistent model-summary cache for `simdir` (skipped if already up to
date), so the first "Model summary" click is instant. Called by
[`dashboard`](@ref) when `precompute = true`.
"""
function precompute_summary!(simdir, bench_cache, obs; fallback_start_date = nothing, mask_kind::Symbol = :land)
    spec = mask_spec(mask_kind)
    bundle = ObsBundle(obs; start_date = fallback_start_date)
    fingerprint = _summary_fingerprint(simdir, _summary_candidates(simdir, bundle)) * spec.cache_tag
    isnothing(_cached_summary_rows(bench_cache, fingerprint)) || return nothing
    rows = compute_summary_rows(simdir, bundle; fallback_start_date, mask = spec.mask)
    _store_summary_rows!(bench_cache, fingerprint, rows)
    return nothing
end

# ─── Rendering ────────────────────────────────────────────────────────────────

# Compact number formatting matching `format_cell`'s magnitude rules.
function _summary_format(v)
    isnan(v) && return "—"
    return (v == 0 || abs(v) >= 0.1) ? string(round(v; digits = 2)) :
           string(round(v; sigdigits = 3))
end

_hex2(x) = string(round(Int, clamp(x, 0, 255)); base = 16, pad = 2)
_lerp_rgb(a, b, t) = string("#", _hex2(a[1] + (b[1] - a[1]) * t),
    _hex2(a[2] + (b[2] - a[2]) * t), _hex2(a[3] + (b[3] - a[3]) * t))

# Cell color from RMSE relative to |obs mean|: green (≤25 %) through yellow
# (~75 %) to red (≥125 %); gray when the ratio is undefined. RGB components as
# Ints — UInt8 differences would wrap around in the lerp.
function _rmse_cell_color(rmse, obs_mean)
    (isnan(rmse) || isnan(obs_mean) || obs_mean == 0) && return "#555555"
    green, yellow, red = (46, 125, 50), (196, 143, 16), (198, 40, 40)
    rel = rmse / abs(obs_mean)
    rel <= 0.25 && return _lerp_rgb(green, green, 0.0)
    rel <= 0.75 && return _lerp_rgb(green, yellow, (rel - 0.25) / 0.5)
    rel <= 1.25 && return _lerp_rgb(yellow, red, (rel - 0.75) / 0.5)
    return _lerp_rgb(red, red, 0.0)
end

function _summary_table_node(rows; mask_note = "land-only (ocean-masked)")
    isempty(rows) && return Bonito.DOM.div(
        "No benchmark observations are registered for this component's variables.";
        style = "padding: 16px; font-size: 1.0rem;",
    )
    header_style = "font-weight: 700; font-size: 0.95rem; padding: 6px 10px; text-align: center;"
    label_style = "font-size: 0.95rem; padding: 8px 10px; text-align: left; white-space: nowrap;"
    cell_style(color) = string(
        "background: ", color, "; color: white; border-radius: 4px;",
        "padding: 6px 10px; text-align: center; min-width: 92px;",
        "font-variant-numeric: tabular-nums;",
    )
    cells = Any[Bonito.DOM.div(""; style = header_style)]
    for title in _SUMMARY_SCOPE_TITLES
        push!(cells, Bonito.DOM.div(title; style = header_style))
    end
    for r in rows
        push!(cells, Bonito.DOM.div(
            Bonito.DOM.div(string(r.short_name, " [", r.units, "]"); style = "font-weight: 700;"),
            Bonito.DOM.div(string("vs ", r.obs_name); style = "font-size: 0.8rem; opacity: 0.8;");
            style = label_style,
        ))
        for s in _SUMMARY_SCOPES
            push!(cells, Bonito.DOM.div(
                Bonito.DOM.div(_summary_format(r.rmse[s]); style = "font-weight: 700;"),
                Bonito.DOM.div(string("bias ", _summary_format(r.bias[s])); style = "font-size: 0.8rem; opacity: 0.85;");
                style = cell_style(_rmse_cell_color(r.rmse[s], r.obs_mean)),
            ))
        end
    end
    caption = Bonito.DOM.div(
        string(
            "Global ", mask_note, " RMSE (and bias) vs. observation, full simulation period. ",
            "Color: RMSE relative to the observed all-time mean (green ≤ 25 %, red ≥ 125 %).",
        );
        style = "font-size: 0.85rem; opacity: 0.8; margin-top: 10px; max-width: 640px;",
    )
    grid = Bonito.DOM.div(
        cells...;
        style = string(
            "display: grid; grid-template-columns: max-content repeat(",
            length(_SUMMARY_SCOPES), ", auto); gap: 3px; align-items: stretch;",
        ),
    )
    return Bonito.DOM.div(grid, caption)
end

# ─── UI: button + modal overlay ───────────────────────────────────────────────

"""
    summary_ui(component_label)

Build the "Model summary" button and the (initially hidden) modal overlay.
Returns `(summary_button, overlay, show_summary, summary_content)`; wire the
button with [`setup_summary_handler`](@ref) once the `AppState` exists.
`component_label` is an Observable with the active component name (`""` for
single-component runs).
"""
function summary_ui(component_label)
    show_summary = Observable(false)
    summary_content = Observable{Any}(Bonito.DOM.div("Computing summary…"))

    button_style = Bonito.Styles(
        "padding" => "8px 12px", "font-size" => "0.95rem", "font-weight" => "bold",
        "border-radius" => "4px", "border" => "2px solid #888888",
        "background-color" => "#888888", "color" => "white", "cursor" => "pointer",
    )
    summary_button = Bonito.Button("Model summary"; style = button_style)
    close_button = Bonito.Button("Close"; style = button_style)
    on(close_button) do _
        show_summary[] = false
    end

    overlay_style = map(show_summary) do visible
        string(
            "position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;",
            "z-index: 1000; background: rgba(0, 0, 0, 0.65);",
            "align-items: center; justify-content: center;",
            "display: ", visible ? "flex" : "none", ";",
        )
    end

    subtitle = map(component_label) do label
        isempty(label) ? "" : string("Component: ", label)
    end
    panel = Bonito.DOM.div(
        Bonito.DOM.div(
            Bonito.DOM.h2("Model performance summary";
                style = "margin: 0; font-size: 1.3rem; font-weight: 700;"),
            close_button;
            style = "display: flex; justify-content: space-between; align-items: center; gap: 24px; margin-bottom: 4px;",
        ),
        Bonito.DOM.div(subtitle; style = "font-size: 1.0rem; color: #9ec5fe; margin-bottom: 12px;"),
        summary_content;
        class = "menu-card",
        style = string(
            "background: #1a1a1a; color: white; padding: 20px 24px;",
            "border-radius: 8px; max-height: 90vh; max-width: 90vw; overflow: auto;",
            "box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);",
        ),
    )
    overlay = Bonito.DOM.div(panel; style = overlay_style)
    return summary_button, overlay, show_summary, summary_content
end

"""
    setup_summary_handler(summary_button, show_summary, summary_content, state, component_label)

Wire the "Model summary" button: on click, open the overlay and (once per
component and session) compute the summary rows for the active SimDir — served
from the persistent cache when available, otherwise computed asynchronously
with progress shown in the dashboard loading bar.
"""
function setup_summary_handler(summary_button, show_summary, summary_content, state::AppState, component_label)
    computed = Dict{String, Any}()
    computing = Ref(false)
    on(summary_button) do _
        show_summary[] = true
        label = component_label[]
        spec = mask_spec(state.mask_kind)
        if haskey(computed, label)
            summary_content[] = _summary_table_node(computed[label]; mask_note = spec.summary_note)
            return
        end
        computing[] && return
        computing[] = true
        summary_content[] = Bonito.DOM.div("Computing summary… (first open per component is slow)")
        simdir = state.simdir
        obs_bundle = state.obs_bundle
        bench_cache = state.bench_cache
        fallback_start_date = state.fallback_start_date
        @async try
            state.is_loading[] = true
            fingerprint = _summary_fingerprint(simdir, _summary_candidates(simdir, obs_bundle)) * spec.cache_tag
            rows = _cached_summary_rows(bench_cache, fingerprint)
            if isnothing(rows)
                rows = compute_summary_rows(
                    simdir, obs_bundle;
                    fallback_start_date,
                    mask = spec.mask,
                    on_progress = sn -> (state.loading_status[] = string("Summary: benchmarking ", sn, "…")),
                )
                _store_summary_rows!(bench_cache, fingerprint, rows)
            end
            computed[label] = rows
            summary_content[] = _summary_table_node(rows; mask_note = spec.summary_note)
        catch e
            @warn "ClimaViz: summary computation failed" exception = (e, catch_backtrace())
            summary_content[] = Bonito.DOM.div(string("Summary failed: ", sprint(showerror, e)))
        finally
            computing[] = false
            state.is_loading[] = false
            state.loading_status[] = ""
        end
    end
end
