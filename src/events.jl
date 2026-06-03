# ─── Mouse click on map: select profile location ──────────────────────────
# Clicking either the main map or the bias map picks the profile/time-series
# location. Both axes are GeoAxis with the same projection, so the click→lonlat
# transform is identical; only the (figure, axis) pair differs.
function setup_mouse_click_handler(fig, state::AppState)
    _register_location_click!(fig, state.ax, state)
    _register_location_click!(state.fig_bias, state.ax_bias, state)
end

function _register_location_click!(fig, ax, state::AppState)
    on(events(fig).mousebutton) do event
        if event.button == Mouse.left && event.action == Mouse.press
            mp = mouseposition(ax)
            trans = Proj.Transformation(ax.dest[], ax.source[]; always_xy = true)
            lonlat = trans(mp)
            _select_location!(state, lonlat[1], lonlat[2])
        end
    end
end

function _select_location!(state::AppState, lon, lat)
    state.lon_profile[] = lon
    state.lat_profile[] = lat

    if has_height(state.var[])
        state.profile[] = get_profile(state.sim_agg[], state.lon_profile[], state.lat_profile[], state.time_selected[])
        notify(state.profile)
        notify(state.heights_obs)
        state.profile_limits[] = get_profile_limits_all_times(state.sim_agg[], state.lon_profile[], state.lat_profile[])
        xlims!(state.ax_profile, state.profile_limits[])
    end

    state.profile_title[] = profile_title_string(state.var[], state.dates_array, state.time_selected[], state.lon_profile[], state.lat_profile[], state.aggregation_level[])
    state.timeseries_title[] = timeseries_title_string(state.var[], state.heights, state.height_selected[], state.lon_profile[], state.lat_profile[])

    state.timeseries[] = get_timeseries(state.sim_agg[], state.lon_profile[], state.lat_profile[]; height_selected = state.height_selected[])
    state.timeseries_obs[] = get_obs_timeseries(state.obs_agg[], state.lon_profile[], state.lat_profile[], length(state.timeseries[]))
    autolimits!(state.ax_timeseries)
end

# ─── Variable / reduction / period: switch active OutputVar ────────────────
function setup_variable_handler(var_menu, reduction_menu, period_menu, height_slider, time_slider, aggregation_menu, state::AppState)
    on(var_menu.value) do v
        state.updating = true
        try
            available_reductions = collect(keys(state.simdir.vars[v]))
            reduction_menu.option_index[] = 1
            reduction_menu.value[] = first(available_reductions)
            reduction_menu.options[] = available_reductions

            available_periods = collect(keys(state.simdir.vars[v][first(available_reductions)]))
            period_menu.option_index[] = 1
            period_menu.value[] = first(available_periods)
            period_menu.options[] = available_periods

            state.current_reduction = first(available_reductions)
            state.current_period = first(available_periods)
            new_var = get(state.simdir; short_name = v, reduction = state.current_reduction, period = state.current_period)
            heights_new = has_height(new_var) ? new_var.dims[get_height_dim_name(new_var)] : Float64[]

            height_slider.index[] = 1
            new_values = collect(1:max(1, length(heights_new)))
            height_slider.values[] = new_values
            new_height_idx = has_height(new_var) ? length(heights_new) : 1
            height_slider.index[] = new_height_idx

            _update_aggregation_options!(aggregation_menu, new_var, state)
            update_for_new_variable(state, new_var, heights_new, time_slider)
        finally
            state.updating = false
        end
    end
end

function setup_reduction_handler(reduction_menu, period_menu, time_slider, aggregation_menu, state::AppState)
    on(reduction_menu.value) do reduction
        state.updating && return
        state.updating = true
        try
            var_name = ClimaAnalysis.short_name(state.var[])
            available_periods = collect(keys(state.simdir.vars[var_name][reduction]))
            period_menu.option_index[] = 1
            period_menu.value[] = first(available_periods)
            period_menu.options[] = available_periods

            state.current_reduction = reduction
            state.current_period = first(available_periods)
            new_var = get(state.simdir; short_name = var_name, reduction = reduction, period = first(available_periods))
            heights_new = has_height(new_var) ? new_var.dims[get_height_dim_name(new_var)] : Float64[]
            _update_aggregation_options!(aggregation_menu, new_var, state)
            update_for_new_variable(state, new_var, heights_new, time_slider)
        finally
            state.updating = false
        end
    end
end

function setup_period_handler(period_menu, reduction_menu, time_slider, aggregation_menu, state::AppState)
    on(period_menu.value) do period
        state.updating && return
        state.updating = true
        try
            var_name = ClimaAnalysis.short_name(state.var[])
            reduction = reduction_menu.value[]
            state.current_reduction = reduction
            state.current_period = period
            new_var = get(state.simdir; short_name = var_name, reduction = reduction, period = period)
            heights_new = has_height(new_var) ? new_var.dims[get_height_dim_name(new_var)] : Float64[]
            _update_aggregation_options!(aggregation_menu, new_var, state)
            update_for_new_variable(state, new_var, heights_new, time_slider)
        finally
            state.updating = false
        end
    end
end

function _update_aggregation_options!(aggregation_menu, new_var, state::AppState)
    levels = available_levels(new_var)
    labels = [aggregation_label(new_var, l) for l in levels]
    aggregation_menu.option_index[] = 1
    aggregation_menu.value[] = first(labels)
    aggregation_menu.options[] = labels
    state.aggregation_level[] = :native
end

# Re-bind the time slider to a new length. `slider.value` is a derived
# `map(getindex, values, index)`, so swapping `values` to a shorter vector while
# `index` still points past the new end throws a BoundsError (this is the bug
# that hits when the slider is at an advanced tick and the aggregation level is
# made coarser). Clamp `index` into the new range *before* swapping `values`.
# Returns the new (clamped) index.
function _resize_time_slider!(time_slider, n_times)
    n_times = max(1, n_times)
    new_idx = clamp(time_slider.index[], 1, n_times)
    time_slider.index[] = new_idx
    time_slider.values[] = collect(1:n_times)
    return new_idx
end

# Update everything when the active variable changes
function update_for_new_variable(state::AppState, new_var, heights_new, time_slider)
    state.is_loading[] = true
    state.loading_status[] = string("Loading ", ClimaAnalysis.short_name(new_var), "…")

    # New variable invalidates any cached resampled obs / bias limits / metrics.
    empty!(state.bias_limits_cache)
    empty!(state.obs_resampled_cache)
    empty!(state.metrics_cache)

    state.var[] = new_var
    needs_height_update = has_height(new_var)

    empty!(state.heights)
    append!(state.heights, heights_new)
    state.heights_obs[] = length(heights_new) > 0 ? collect(heights_new) : [0.0]

    # Aggregate at current level (:native if reset)
    sim_agg = aggregate_var(new_var, state.aggregation_level[])
    state.sim_agg[] = sim_agg

    new_dates = ClimaAnalysis.dates(sim_agg)
    empty!(state.dates_array)
    append!(state.dates_array, new_dates)

    # Re-bind time slider to new length (clamps the index into range).
    n_times = length(sim_agg.dims["time"])
    new_idx = _resize_time_slider!(time_slider, n_times)
    state.current_time_index[] = new_idx

    # Obs binding
    obs = get_obs(state.obs_bundle, ClimaAnalysis.short_name(new_var))
    obs_agg = aggregate_obs(obs, new_var, state.aggregation_level[])
    state.obs_agg[] = obs_agg
    state.show_bias[] = !isnothing(obs_agg) && _has_lonlat_only(sim_agg)
    state.show_obs_line[] = !isnothing(obs_agg)

    state.var_sliced[] = var_slice(sim_agg, state.time_selected[]; height_selected = state.height_selected[])
    state.limits[] = get_limits(sim_agg, state.time_selected[]; height_selected = state.height_selected[])

    if has_height(state.var[])
        update_title_with_height(state, state.time_selected[], state.heights[state.height_selected[]])
    else
        update_title(state, state.time_selected[])
    end

    state.profile_xlabel[] = string(ClimaAnalysis.short_name(state.var[]), " [", ClimaAnalysis.units(state.var[]), "]")
    state.timeseries_ylabel[] = string(ClimaAnalysis.short_name(state.var[]), " [", ClimaAnalysis.units(state.var[]), "]")

    tick_indices = round.(Int, range(1, length(state.dates_array), length = min(state.n_ticks, length(state.dates_array))))
    tick_labels = [format_date_short(state.dates_array[i], state.aggregation_level[]) for i in tick_indices]
    state.ax_timeseries.xticks = (tick_indices, tick_labels)

    state.timeseries_title[] = timeseries_title_string(state.var[], state.heights, state.height_selected[], state.lon_profile[], state.lat_profile[])
    state.profile_title[] = profile_title_string(state.var[], state.dates_array, state.time_selected[], state.lon_profile[], state.lat_profile[], state.aggregation_level[])
    state.time_value_text[] = format_date_for_level(state.dates_array[state.time_selected[]], state.aggregation_level[])

    state.height_value_text[] = has_height(state.var[]) ? string(round(state.heights[state.height_selected[]], digits = 1), " m") : "N/A"

    if has_height(state.var[])
        state.profile[] = get_profile(sim_agg, state.lon_profile[], state.lat_profile[], state.time_selected[])
        notify(state.profile)
        notify(state.heights_obs)
        state.profile_limits[] = get_profile_limits_all_times(sim_agg, state.lon_profile[], state.lat_profile[])
        state.current_height[] = state.heights[state.height_selected[]]
        xlims!(state.ax_profile, state.profile_limits[])
        ylims!(state.ax_profile, minimum(state.heights), maximum(state.heights))
    end

    state.timeseries[] = get_timeseries(sim_agg, state.lon_profile[], state.lat_profile[]; height_selected = state.height_selected[])
    state.timeseries_obs[] = get_obs_timeseries(obs_agg, state.lon_profile[], state.lat_profile[], length(state.timeseries[]))
    autolimits!(state.ax_timeseries)

    state.show_height[] = needs_height_update

    recompute_benchmark!(state)
end

_has_lonlat_only(var) = haskey(var.dims, "lon") && haskey(var.dims, "lat") && !has_height(var)

# ─── Benchmark: bias map + metrics ─────────────────────────────────────────
# Try to satisfy the benchmark panel for the current (var, reduction, period,
# level) entirely from the persistent cache. On a hit it prefills the in-session
# caches (bias limits, per-slice resampled obs, per-time metrics) so the bias map
# and metrics become instant lookups, and returns the entry. Returns `nothing`
# (and touches nothing) on any miss.
function _try_cached_benchmark!(state::AppState, var_name, level)
    cache = state.bench_cache
    isnothing(cache) && return nothing
    key = (var_name, state.current_reduction, state.current_period, level)
    fingerprint = _source_fingerprint(state.simdir, var_name, state.current_reduction, state.current_period)
    entry = get_cached_entry(cache, key, fingerprint)
    isnothing(entry) && return nothing
    # Defensive: the cache is grid-specific; bail if the live grid differs.
    (length(entry.lon) == length(state.lon) && length(entry.lat) == length(state.lat)) || return nothing

    base = (var_name, level)
    state.bias_limits_cache[base] = entry.bias_limits
    slot = Dict{Int, Array{Float64, 2}}()
    for t in 1:entry.n
        slot[t] = entry.obs_resampled[:, :, t]
    end
    state.obs_resampled_cache[base] = slot
    for t in 1:entry.n
        state.metrics_cache[(var_name, level, t)] = MetricsTable(copy(entry.metrics_per_t[t]), entry.units)
    end
    return entry
end

function recompute_benchmark!(state::AppState)
    if !state.show_bias[]
        state.bias_sliced[] = fill(NaN, length(state.lon), length(state.lat))
        state.bias_limits[] = (-1.0, 1.0)
        state.bias_title[] = "no observation available"
        state.metrics[] = MetricsTable(ClimaAnalysis.units(state.var[]))
        state.is_loading[] = false
        state.loading_status[] = ""
        return
    end
    sim_agg = state.sim_agg[]
    obs_agg = state.obs_agg[]
    var_name = ClimaAnalysis.short_name(state.var[])
    level = state.aggregation_level[]
    state.is_loading[] = true
    try
        sim_dates = ClimaAnalysis.dates(sim_agg)
        obs_dates = ClimaAnalysis.dates(obs_agg)
        n = min(length(sim_dates), length(obs_dates))
        sim_trunc = _select_time_indices(sim_agg, collect(1:n))
        obs_trunc = _select_time_indices(obs_agg, collect(1:n))

        t = clamp(state.time_selected[], 1, n)

        # Fast path: everything cached on disk. Prefilling the in-session caches
        # makes the bias slice (below) and metrics pure lookups — no regridding,
        # no async, no loading bar.
        entry = _try_cached_benchmark!(state, var_name, level)
        if !isnothing(entry)
            _update_bias_slice!(state, sim_trunc, obs_trunc, t)
            state.bias_title[] = bias_title_string(state.var[], state.dates_array, state.time_selected[], level)
            state.bias_limits[] = entry.bias_limits
            mk = (var_name, level, t)
            haskey(state.metrics_cache, mk) && (state.metrics[] = state.metrics_cache[mk])
            state.is_loading[] = false
            state.loading_status[] = ""
            return
        end

        # Synchronous: cheap bias slice + title, then cached limits if available.
        state.loading_status[] = "Computing bias map…"
        _update_bias_slice!(state, sim_trunc, obs_trunc, t)
        state.bias_title[] = bias_title_string(state.var[], state.dates_array, state.time_selected[], level)

        cache_key = (var_name, level)
        if haskey(state.bias_limits_cache, cache_key)
            state.bias_limits[] = state.bias_limits_cache[cache_key]
            limits_ready = true
        else
            limits_ready = false
        end

        # Async: stable colorbar limits (full time-mean) + all metrics.
        @async _async_benchmark!(state, sim_trunc, obs_trunc, t, cache_key, limits_ready)
    catch e
        @debug "benchmark computation failed" exception = (e, catch_backtrace())
        state.show_bias[] = false
        state.bias_sliced[] = fill(NaN, length(state.lon), length(state.lat))
        state.bias_limits[] = (-1.0, 1.0)
        state.bias_title[] = "observation unavailable"
        state.metrics[] = MetricsTable(ClimaAnalysis.units(state.var[]))
        state.is_loading[] = false
        state.loading_status[] = ""
    end
end

function _async_benchmark!(state::AppState, sim_trunc, obs_trunc, t, cache_key, limits_ready)
    try
        if !limits_ready
            state.loading_status[] = "Computing bias limits…"
            sim_tmean = ClimaAnalysis.average_time(sim_trunc)
            obs_tmean = ClimaAnalysis.average_time(obs_trunc)
            obs_tmean_re = ClimaAnalysis.resampled_as(obs_tmean, sim_tmean)
            lims = _symmetric_limits(filter(!isnan, vec(sim_tmean.data .- obs_tmean_re.data)))
            state.bias_limits_cache[cache_key] = lims
            state.bias_limits[] = lims
        end

        # The metrics panel only displays the :selected scope (see
        # _metrics_panel), so compute just that — no all-time / seasonal /
        # amplitude / phase work that would never be shown.
        state.loading_status[] = "Computing metrics…"
        metrics = compute_metrics(
            sim_trunc, obs_trunc;
            selected_idx = t,
            scopes = (:selected,),
            compute_seasonal_diagnostics = false,
        )
        state.metrics[] = metrics
    catch e
        @debug "async benchmark failed" exception = (e, catch_backtrace())
    finally
        state.is_loading[] = false
        state.loading_status[] = ""
    end
end

function _update_bias_slice!(state::AppState, sim_var, obs_var, t)
    sim_t = ClimaAnalysis.slice(sim_var; time = sim_var.dims["time"][t])
    obs_resampled_slice = _get_obs_resampled_slice(state, sim_var, obs_var, t, sim_t)
    state.bias_sliced[] = sim_t.data .- obs_resampled_slice
end

# Return obs.data resampled onto the sim grid for time index t. Cached per
# (variable, aggregation level, time index). Falls back to direct resample on
# any cache miss / failure.
function _get_obs_resampled_slice(state::AppState, sim_var, obs_var, t, sim_t)
    var_name = ClimaAnalysis.short_name(state.var[])
    level = state.aggregation_level[]
    base_key = (var_name, level)
    slot = get!(state.obs_resampled_cache, base_key) do
        Dict{Int, Array{Float64, 2}}()
    end
    if haskey(slot, t)
        return slot[t]
    end
    obs_t = ClimaAnalysis.slice(obs_var; time = obs_var.dims["time"][t])
    obs_resampled = ClimaAnalysis.resampled_as(obs_t, sim_t)
    data = Array{Float64, 2}(obs_resampled.data)
    slot[t] = data
    return data
end

function _symmetric_limits(data; q = 0.98)
    isempty(data) && return (-1.0, 1.0)
    lim = Statistics.quantile(abs.(data), q)
    lim == 0 && return (-1.0, 1.0)
    return (-lim, lim)
end

# ─── Aggregation menu ──────────────────────────────────────────────────────
function setup_aggregation_handler(aggregation_menu, time_slider, state::AppState)
    on(aggregation_menu.value) do label
        state.updating && return
        # Guard against the time-slider handler firing mid-update (the slider
        # resize below moves the index, and obs_agg isn't refreshed yet).
        state.updating = true
        try
            new_level = _label_to_level(label, state.var[])
            state.aggregation_level[] = new_level

            # Switching aggregation invalidates the per-(var,level) caches.
            state.is_loading[] = true
            state.loading_status[] = string("Aggregating to ", label, "…")

            sim_agg = aggregate_var(state.var[], new_level)
            state.sim_agg[] = sim_agg
            empty!(state.dates_array)
            append!(state.dates_array, ClimaAnalysis.dates(sim_agg))

            n_times = length(sim_agg.dims["time"])
            new_idx = _resize_time_slider!(time_slider, n_times)
            state.current_time_index[] = new_idx

            obs = get_obs(state.obs_bundle, ClimaAnalysis.short_name(state.var[]))
            obs_agg = aggregate_obs(obs, state.var[], new_level)
            state.obs_agg[] = obs_agg
            state.show_bias[] = !isnothing(obs_agg) && _has_lonlat_only(sim_agg)
            state.show_obs_line[] = !isnothing(obs_agg)

            state.var_sliced[] = var_slice(sim_agg, new_idx; height_selected = state.height_selected[])
            state.limits[] = get_limits(sim_agg, new_idx; height_selected = state.height_selected[])

            tick_indices = round.(Int, range(1, length(state.dates_array), length = min(state.n_ticks, length(state.dates_array))))
            tick_labels = [format_date_short(state.dates_array[i], new_level) for i in tick_indices]
            state.ax_timeseries.xticks = (tick_indices, tick_labels)
            state.timeseries[] = get_timeseries(sim_agg, state.lon_profile[], state.lat_profile[]; height_selected = state.height_selected[])
            state.timeseries_obs[] = get_obs_timeseries(obs_agg, state.lon_profile[], state.lat_profile[], length(state.timeseries[]))
            state.time_value_text[] = format_date_for_level(state.dates_array[new_idx], new_level)
            autolimits!(state.ax_timeseries)

            # Re-render titles with the new level's date format.
            if has_height(state.var[])
                update_title_with_height(state, new_idx, state.heights[state.height_selected[]])
            else
                update_title(state, new_idx)
            end
            state.profile_title[] = profile_title_string(state.var[], state.dates_array, new_idx, state.lon_profile[], state.lat_profile[], new_level)

            if has_height(state.var[])
                state.profile[] = get_profile(sim_agg, state.lon_profile[], state.lat_profile[], new_idx)
                notify(state.profile)
            end

            recompute_benchmark!(state)
        finally
            state.updating = false
        end
    end
end

function _label_to_level(label, var)
    label == "Seasonal" && return :seasonal
    label == "Annual" && return :annual
    return :native
end

# ─── Time slider ───────────────────────────────────────────────────────────
function setup_time_handler(time_slider, state::AppState)
    on(time_slider.value) do t
        # Skip while another handler is mid-update (it resizes the slider and
        # repaints everything itself with consistent state).
        state.updating && return
        sim_agg = state.sim_agg[]
        level = state.aggregation_level[]
        state.var_sliced[] = var_slice(sim_agg, t; height_selected = state.height_selected[])

        if has_height(state.var[])
            update_title_with_height(state, t, state.heights[state.height_selected[]])
        else
            update_title(state, t)
        end

        state.current_time_index[] = t
        state.time_value_text[] = format_date_for_level(state.dates_array[t], level)
        state.profile_title[] = profile_title_string(state.var[], state.dates_array, t, state.lon_profile[], state.lat_profile[], level)

        if has_height(state.var[])
            state.profile[] = get_profile(sim_agg, state.lon_profile[], state.lat_profile[], t)
            notify(state.profile)
            notify(state.heights_obs)
        end

        # Cheap bias map update by re-slicing — uses the per-(var,level,t) cache.
        if state.show_bias[]
            try
                obs_agg = state.obs_agg[]
                sim_dates = ClimaAnalysis.dates(sim_agg)
                obs_dates = ClimaAnalysis.dates(obs_agg)
                n = min(length(sim_dates), length(obs_dates))
                if t <= n
                    sim_t = ClimaAnalysis.slice(sim_agg; time = sim_agg.dims["time"][t])
                    obs_resampled_slice = _get_obs_resampled_slice(state, sim_agg, obs_agg, t, sim_t)
                    state.bias_sliced[] = sim_t.data .- obs_resampled_slice
                    state.bias_title[] = bias_title_string(state.var[], state.dates_array, t, level)
                end
            catch
                # leave bias_sliced unchanged
            end
        end

        # Metrics update for "Selected" scope only — skip while animating.
        if state.show_bias[] && !state.is_playing[]
            mk = (ClimaAnalysis.short_name(state.var[]), level, t)
            if haskey(state.metrics_cache, mk)
                # Cache hit (prefilled from disk): instant.
                state.metrics[] = state.metrics_cache[mk]
            else
                try
                    sim_agg_l = state.sim_agg[]
                    obs_agg_l = state.obs_agg[]
                    n = min(length(ClimaAnalysis.dates(sim_agg_l)), length(ClimaAnalysis.dates(obs_agg_l)))
                    sim_trunc = _select_time_indices(sim_agg_l, collect(1:n))
                    obs_trunc = _select_time_indices(obs_agg_l, collect(1:n))
                    new_table = MetricsTable(state.metrics[].units)
                    merge!(new_table.values, state.metrics[].values)
                    update_metrics_scope!(new_table, sim_trunc, obs_trunc, :selected; selected_idx = min(t, n))
                    state.metrics[] = new_table
                catch
                end
            end
        end
    end
end

# ─── Height slider ─────────────────────────────────────────────────────────
function setup_height_handler(height_slider, state::AppState)
    on(height_slider.value) do h
        if !has_height(state.var[]) || h < 1 || h > length(state.heights)
            return
        end
        sim_agg = state.sim_agg[]
        state.var_sliced[] = var_slice(sim_agg, state.time_selected[]; height_selected = h)
        state.limits[] = get_limits(sim_agg, state.time_selected[]; height_selected = h)

        update_title_with_height(state, state.time_selected[], state.heights[h])

        state.timeseries[] = get_timeseries(sim_agg, state.lon_profile[], state.lat_profile[]; height_selected = h)
        autolimits!(state.ax_timeseries)

        state.height_value_text[] = string(round(state.heights[h], digits = 1), " m")
        state.current_height[] = state.heights[h]
        state.timeseries_title[] = timeseries_title_string(state.var[], state.heights, h, state.lon_profile[], state.lat_profile[])
    end
end

# ─── Speed slider ──────────────────────────────────────────────────────────
function setup_speed_handler(speed_slider, state::AppState)
    on(speed_slider.value) do s
        state.speed_value_text[] = string(round(s, digits = 2), " s")
    end
end

# ─── Play / pause ──────────────────────────────────────────────────────────
function setup_play_handler(play_button, time_slider, state::AppState, button_label)
    on(play_button) do _
        state.is_playing[] = !state.is_playing[]
        if state.is_playing[]
            button_label[] = "⏸"
            n_times = length(state.sim_agg[].dims["time"])
            @async begin
                for t in 1:n_times
                    state.is_playing[] || break
                    time_slider.value[] = t
                    sleep(state.speed_selected[])
                end
                state.is_playing[] = false
                button_label[] = "▶"
            end
        else
            button_label[] = "▶"
            # Trigger one metrics refresh now that animation stopped.
            notify(state.time_selected)
        end
    end
end

# ─── Dark mode ─────────────────────────────────────────────────────────────
function setup_dark_mode_handler(state::AppState, session)
    Bonito.onjs(session, state.dark_mode, Bonito.js"""
    function (is_dark) {
        const bg = is_dark ? 'black' : 'white';
        const panel_bg = is_dark ? '#1a1a1a' : '#e0e0e0';
        const fg = is_dark ? 'white' : 'black';
        document.body.style.backgroundColor = bg;
        document.body.style.color = fg;
        document.querySelectorAll('.menu-card, .title-card').forEach(card => {
            card.style.backgroundColor = panel_bg;
            card.style.color = fg;
            card.style.borderColor = panel_bg;
        });
        document.querySelectorAll('.card:not(.menu-card):not(.title-card)').forEach(card => {
            card.style.backgroundColor = bg;
            card.style.color = fg;
            card.style.borderColor = bg;
        });
        document.querySelectorAll('h1, h2, label, span, p, td, th').forEach(el => {
            el.style.color = fg;
        });
        document.querySelectorAll('input, select').forEach(input => {
            if (is_dark) {
                input.style.backgroundColor = '#333';
                input.style.color = 'white';
                input.style.borderColor = '#555';
            } else {
                input.style.backgroundColor = '';
                input.style.color = '';
                input.style.borderColor = '';
            }
        });
        document.querySelectorAll('canvas').forEach(canvas => {
            if (canvas.parentElement) canvas.parentElement.style.backgroundColor = bg;
            if (canvas.parentElement && canvas.parentElement.parentElement)
                canvas.parentElement.parentElement.style.backgroundColor = bg;
        });
        document.querySelectorAll('div').forEach(div => {
            if (div.querySelector('canvas')) div.style.backgroundColor = bg;
        });
    }
    """)

    on(state.dark_mode) do is_dark
        bg_color, text_color, line_color = is_dark ? (:black, :white, :white) : (:white, :black, :black)
        bg_rgba = is_dark ? RGBf(0, 0, 0) : RGBf(1, 1, 1)

        state.fig.scene.backgroundcolor[] = bg_rgba
        state.fig_bias.scene.backgroundcolor[] = bg_rgba
        state.fig_profile.scene.backgroundcolor[] = bg_rgba
        state.fig_timeseries.scene.backgroundcolor[] = bg_rgba

        state.ax.titlecolor = text_color
        state.coastlines_plot.color = line_color
        state.colorbar.labelcolor = text_color
        state.colorbar.ticklabelcolor = text_color

        state.ax_bias.titlecolor = text_color
        state.coastlines_plot_bias.color = line_color
        state.colorbar_bias.labelcolor = text_color
        state.colorbar_bias.ticklabelcolor = text_color

        state.ax_profile.backgroundcolor = bg_color
        state.ax_profile.titlecolor = text_color
        state.ax_profile.xlabelcolor = text_color
        state.ax_profile.ylabelcolor = text_color
        state.ax_profile.xticklabelcolor = text_color
        state.ax_profile.yticklabelcolor = text_color
        state.profile_lines.color = line_color
        state.profile_box.color = bg_color

        state.ax_timeseries.backgroundcolor = bg_color
        state.ax_timeseries.titlecolor = text_color
        state.ax_timeseries.xlabelcolor = text_color
        state.ax_timeseries.ylabelcolor = text_color
        state.ax_timeseries.xticklabelcolor = text_color
        state.ax_timeseries.yticklabelcolor = text_color
        state.ax_timeseries.xtickcolor = text_color
        state.ax_timeseries.ytickcolor = text_color
        state.ax_timeseries.leftspinecolor = text_color
        state.ax_timeseries.rightspinecolor = text_color
        state.ax_timeseries.topspinecolor = text_color
        state.ax_timeseries.bottomspinecolor = text_color
        state.ax_timeseries.xgridcolor = (text_color, 0.2)
        state.ax_timeseries.ygridcolor = (text_color, 0.2)
        state.timeseries_lines.color = line_color
        state.timeseries_legend.labelcolor = text_color
    end
end
