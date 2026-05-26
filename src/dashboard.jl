"""
    dashboard(path::String; HPC=false, obs=default_era5_obs())

Launch an interactive web dashboard for visualizing climate simulation outputs
and benchmarking against gridded observations when available.

Features:
- Variable / reduction / period menus driven by `ClimaAnalysis.SimDir`.
- Temporal aggregation (Monthly / Seasonal / Annual) re-binning the time axis
  on the fly — choices are restricted to levels at least as coarse as the
  native data resolution.
- 2D map (model) with click-to-select location.
- Bias map (model − observation) when an observation is registered for the
  selected variable; otherwise hidden.
- Vertical profile when the variable has a `z` / `z_reference` dimension;
  otherwise replaced by a benchmark metrics table (Sim mean, Obs mean, Bias,
  RMSE, Spatial r, Amplitude ratio, Phase shift across All-time / Selected /
  DJF / MAM / JJA / SON).
- Time-series at the selected location.

# Arguments
- `path::String`: simulation output directory (readable by `SimDir`).
- `HPC::Bool = false`: serve on `0.0.0.0:8080` for HPC port-forwarding.
- `obs::Dict{String,Function} = default_era5_obs()`: maps variable short_names
  to obs loaders. Each loader receives the sim's start_date and returns a
  `ClimaAnalysis.OutputVar`. The default registers ERA5 monthly fluxes for
  `lhf`, `shf`, `lwu`, `swu` via the ClimaViz LazyArtifact.

# Example
```julia
using ClimaViz
dashboard("path/to/output/")
```
"""
function dashboard(path; HPC = false, obs = default_era5_obs())
    app = Bonito.App(title = "CliMA dashboard") do session
        simdir = ClimaAnalysis.SimDir(path)
        vars = collect(keys(simdir.vars))

        # Dark mode (default on)
        checkbox_style = Bonito.Styles(
            "width" => "18px", "height" => "18px", "cursor" => "pointer",
            "accent-color" => "#2196F3", "margin" => "0", "transform" => "scale(1.1)",
        )
        dark_mode_checkbox = Bonito.Checkbox(true; style = checkbox_style)
        dark_mode = dark_mode_checkbox.value

        # UI styling
        var_menu_style = map(dark_mode) do is_dark
            Bonito.Styles(
                "font-size" => "0.95rem", "font-weight" => "bold",
                "padding" => "6px 8px", "border-radius" => "4px",
                "cursor" => "pointer", "min-width" => "80px", "max-width" => "180px",
                "color" => "black",
            )
        end
        dropdown_style = Bonito.Styles(
            "font-size" => "0.95rem", "padding" => "6px 8px",
            "border-radius" => "4px", "cursor" => "pointer",
            "min-width" => "80px", "max-width" => "180px",
        )

        # Variable / reduction / period
        var_menu = Bonito.ChoicesBox(vars; style = var_menu_style)
        var_menu.value[] = first(vars)
        var_selected = var_menu.value

        available_reductions = collect(keys(simdir.vars[var_selected[]]))
        reduction_menu = Bonito.Dropdown(available_reductions; style = dropdown_style)
        reduction_menu.value[] = first(available_reductions)

        available_periods = collect(keys(simdir.vars[var_selected[]][first(available_reductions)]))
        period_menu = Bonito.Dropdown(available_periods; style = dropdown_style)
        period_menu.value[] = first(available_periods)

        # Initial variable
        initial_var = get(simdir; short_name = var_selected[], reduction = reduction_menu.value[], period = period_menu.value[])
        lon = initial_var.dims["lon"]
        lat = initial_var.dims["lat"]
        times = initial_var.dims["time"]
        dates_array = ClimaAnalysis.dates(initial_var)

        # Aggregation menu
        levels = available_levels(initial_var)
        agg_labels = [aggregation_label(initial_var, l) for l in levels]
        aggregation_menu = Bonito.Dropdown(agg_labels; style = dropdown_style)
        aggregation_menu.value[] = first(agg_labels)
        aggregation_level = Observable(:native)

        # Observable for the current variable + aggregated form. Use Any-typed
        # observables because we swap between 3D and 4D OutputVars at runtime.
        var = Observable{Any}(initial_var)
        sim_agg = Observable{Any}(initial_var)  # :native — same object
        # Obs bundle (driven by sim's start_date if present in attributes)
        sim_start = try
            Dates.DateTime(initial_var.attributes["start_date"])
        catch
            dates_array[1]
        end
        obs_bundle = ObsBundle(obs; start_date = sim_start)

        initial_obs = get_obs(obs_bundle, ClimaAnalysis.short_name(initial_var))
        initial_obs_agg = aggregate_obs(initial_obs, initial_var, :native)
        obs_agg = Observable{Any}(initial_obs_agg)
        show_bias = Observable(!isnothing(initial_obs_agg) && _has_lonlat_only(initial_var))

        # Sliders
        time_slider = Bonito.StylableSlider(1:length(times))
        time_selected = time_slider.value

        heights = has_height(initial_var) ? initial_var.dims[get_height_dim_name(initial_var)] : Float64[]
        height_slider = Bonito.StylableSlider(1:max(1, length(heights)))
        height_slider.value[] = max(1, length(heights))
        height_selected = height_slider.value

        speed_slider = Bonito.StylableSlider(range(0.0, 0.3, length = 31))
        speed_slider.value[] = 0.1
        speed_selected = speed_slider.value

        # Play button
        button_style = Bonito.Styles(
            "padding" => "8px", "font-size" => "1.2rem", "font-weight" => "bold",
            "border-radius" => "4px", "border" => "2px solid #888888",
            "background-color" => "#888888", "color" => "white", "cursor" => "pointer",
            "width" => "40px", "height" => "40px",
            "display" => "flex", "align-items" => "center", "justify-content" => "center",
        )
        is_playing = Observable(false)
        button_label = Observable("▶")
        play_button = Bonito.Button(button_label; style = button_style)

        show_height = Observable(has_height(initial_var))

        # Text labels
        value_style = Bonito.Styles("font-size" => "0.9rem", "color" => "white")
        time_value_text = Observable(format_date_for_level(dates_array[time_selected[]], aggregation_level[]))
        time_value_label = Bonito.DOM.h1(time_value_text; style = value_style)

        height_value_text = Observable(has_height(initial_var) ? string(round(heights[height_selected[]], digits = 1), " m") : "N/A")
        height_value_label = Bonito.DOM.h1(height_value_text; style = value_style)

        speed_value_text = Observable(string(round(speed_selected[], digits = 2), " s"))
        speed_value_label = Bonito.DOM.h1(speed_value_text; style = value_style)

        # Main 2D map observables
        var_sliced = Observable(var_slice(initial_var, time_selected[]; height_selected = height_selected[]))
        limits = Observable(get_limits(initial_var, time_selected[]; height_selected = height_selected[]))

        # Bias observables
        bias_sliced = Observable(fill(NaN, length(lon), length(lat)))
        bias_limits = Observable((-1.0, 1.0))
        bias_title = Observable(show_bias[] ? bias_title_string(initial_var, dates_array, time_selected[], aggregation_level[]) : "no observation available")

        # Metrics observable + scope dropdown selection
        metrics = Observable(MetricsTable(ClimaAnalysis.units(initial_var)))
        metrics_scope = Observable(:all_time)

        # Loading bar state
        is_loading = Observable(false)
        loading_status = Observable("")

        # Profile / location
        lon_profile = Observable(-118.25)
        lat_profile = Observable(34.05)

        if has_height(initial_var)
            profile = Observable(get_profile(initial_var, lon_profile[], lat_profile[], time_selected[]))
            profile_limits = Observable(get_limits(initial_var, time_selected[]; height_selected = height_selected[], low_q = 0.0, high_q = 1.0))
            current_height = Observable(heights[height_selected[]])
        else
            profile = Observable([0.0])
            profile_limits = Observable((0.0, 1.0))
            current_height = Observable(0.0)
        end

        timeseries = Observable(get_timeseries(initial_var, lon_profile[], lat_profile[]; height_selected = height_selected[]))
        timeseries_obs = Observable(get_obs_timeseries(initial_obs_agg, lon_profile[], lat_profile[], length(timeseries[])))
        show_obs_line = Observable(!isnothing(initial_obs_agg))

        profile_title = Observable(profile_title_string(initial_var, dates_array, time_selected[], lon_profile[], lat_profile[], aggregation_level[]))
        timeseries_title = Observable(timeseries_title_string(initial_var, heights, height_selected[], lon_profile[], lat_profile[]))

        # Earth image (still used as background fallback in main figure)
        earth_img_path = joinpath(@__DIR__, "..", "assets", "Blue_Marble.jpg")
        earth_img = FileIO.load(earth_img_path)

        # Figures
        fig, ax, title, coastlines_plot, cbar, surface_plot_colormap, earth_surface, colorbar_label =
            create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, :black, earth_img)

        fig_bias, ax_bias, coastlines_plot_bias, cbar_bias, surface_plot_bias, colorbar_label_bias =
            create_bias_figure(var, bias_sliced, bias_limits, bias_title, lon, lat, lon_profile, lat_profile, :black)

        fig_profile, ax_profile, profile_xlabel, profile_lines, profile_hlines, heights_obs, profile_box =
            create_profile_figure(var, heights, profile, profile_limits, current_height, profile_title, time_selected, :black, show_height)

        # Initial profile decoration visibility
        initial_has_height = show_height[]
        for prop in (:xticksvisible, :yticksvisible, :xticklabelsvisible, :yticklabelsvisible,
                     :xlabelvisible, :ylabelvisible, :titlevisible,
                     :leftspinevisible, :rightspinevisible, :topspinevisible, :bottomspinevisible)
            setproperty!(ax_profile, prop, initial_has_height)
        end

        fig_timeseries, ax_timeseries, timeseries_ylabel, current_time_index, n_ticks,
            timeseries_lines, timeseries_obs_lines =
            create_timeseries_figure(
                var, dates_array, timeseries, timeseries_obs, show_obs_line,
                timeseries_title, time_selected, :black,
            )

        bias_limits_cache = Dict{Tuple{String, Symbol}, Tuple{Float64, Float64}}()
        obs_resampled_cache = Dict{Tuple{String, Symbol}, Any}()

        state = AppState(
            simdir, var, obs_bundle, dates_array, collect(heights), times,
            aggregation_level, sim_agg, obs_agg,
            var_sliced, limits, title,
            show_bias, bias_sliced, bias_limits, bias_title,
            metrics, metrics_scope,
            lon_profile, lat_profile, profile, profile_limits, current_height, profile_title, profile_xlabel,
            heights_obs,
            timeseries, timeseries_obs, show_obs_line, timeseries_title, timeseries_ylabel, current_time_index,
            time_selected, height_selected, speed_selected,
            time_value_text, height_value_text, speed_value_text,
            dark_mode, show_height, is_playing, is_loading, loading_status,
            ax, ax_bias, ax_profile, ax_timeseries,
            profile_lines, profile_hlines, timeseries_lines, timeseries_obs_lines,
            coastlines_plot, coastlines_plot_bias,
            cbar, cbar_bias, colorbar_label, colorbar_label_bias,
            profile_box, surface_plot_colormap, surface_plot_bias,
            earth_surface, earth_img,
            lon, lat,
            fig, fig_bias, fig_profile, fig_timeseries,
            bias_limits_cache, obs_resampled_cache,
            n_ticks, false,
        )

        if has_height(var[])
            update_title_with_height(state, time_selected[], heights[height_selected[]])
        else
            update_title(state, time_selected[])
        end

        # Wire up handlers
        setup_mouse_click_handler(fig, state)
        setup_variable_handler(var_menu, reduction_menu, period_menu, height_slider, time_slider, aggregation_menu, state)
        setup_reduction_handler(reduction_menu, period_menu, time_slider, aggregation_menu, state)
        setup_period_handler(period_menu, reduction_menu, time_slider, aggregation_menu, state)
        setup_aggregation_handler(aggregation_menu, time_slider, state)
        setup_time_handler(time_slider, state)
        setup_height_handler(height_slider, state)
        setup_speed_handler(speed_slider, state)
        setup_play_handler(play_button, time_slider, state, button_label)
        setup_dark_mode_handler(state, session)

        # Toggle profile_box and axis decoration visibility on show_height change
        on(show_height) do has_h
            profile_box.visible = !has_h
            for prop in (:xticksvisible, :yticksvisible, :xticklabelsvisible, :yticklabelsvisible,
                         :xlabelvisible, :ylabelvisible, :titlevisible,
                         :leftspinevisible, :rightspinevisible, :topspinevisible, :bottomspinevisible)
                setproperty!(ax_profile, prop, has_h)
            end
        end

        # Initial benchmark computation
        recompute_benchmark!(state)

        # Initial dark-mode (start dark) styling on Makie side
        ax.titlecolor = :white
        coastlines_plot.color = :white
        cbar.labelcolor = :white
        cbar.ticklabelcolor = :white
        ax_bias.titlecolor = :white
        coastlines_plot_bias.color = :white
        cbar_bias.labelcolor = :white
        cbar_bias.ticklabelcolor = :white
        ax_profile.backgroundcolor = :black
        ax_profile.titlecolor = :white
        ax_profile.xlabelcolor = :white
        ax_profile.ylabelcolor = :white
        ax_profile.xticklabelcolor = :white
        ax_profile.yticklabelcolor = :white
        profile_lines.color = :white
        profile_box.color = :black
        ax_timeseries.backgroundcolor = :black
        ax_timeseries.titlecolor = :white
        ax_timeseries.xlabelcolor = :white
        ax_timeseries.ylabelcolor = :white
        ax_timeseries.xticklabelcolor = :white
        ax_timeseries.yticklabelcolor = :white
        timeseries_lines.color = :white

        notify(dark_mode)

        return layout(
            var_menu, reduction_menu, period_menu, aggregation_menu,
            time_slider, height_slider, play_button, speed_slider,
            fig, fig_bias, fig_profile, fig_timeseries,
            show_height, show_bias, metrics, metrics_scope,
            time_value_label, height_value_label, speed_value_label,
            dark_mode_checkbox,
            is_loading, loading_status,
        )
    end

    if HPC == true
        IP = "0.0.0.0"
        port = 8080
        global server = Bonito.Server(IP, port; proxy_url = "http://localhost:$port")
        Bonito.route!(server, "/" => app)
        print_startup_message(port)
    end

    return app
end
