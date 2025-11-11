"""
    dashboard(path::String)

Launch an interactive web dashboard for visualizing climate simulation outputs.

The dashboard provides an interactive interface for exploring simulation data including:
- Variable selection and visualization
- Time series analysis
- Spatial mapping with GeoMakie
- Vertical profile analysis (when height dimension is available)
- Interactive controls for time, height, and animation

# Arguments
- `path::String`: Path to the simulation output directory. Should contain output files
  that can be read by ClimaAnalysis.SimDir.

# Usage

```julia
using ClimaViz

# Launch dashboard with simulation outputs
dashboard("path/to/output/")
```

After launching, open your browser to `http://localhost:8080/`
to view the dashboard.

For HPC usage, set up SSH port forwarding first:
```bash
ssh -L 8080:localhost:8080 user@hpc.example.com
```

Then run the dashboard command and access it on your local browser.

# Notes
- The dashboard runs on port 8080 by default
- If a previous server is running, it will be closed automatically
- Supports both 2D and 3D (with height) data
- Uses WGLMakie for web-based interactive plotting

# See Also
- [`ClimaAnalysis.SimDir`](https://clima.github.io/ClimaAnalysis.jl/): For loading simulation data
"""
function dashboard(path; HPC = false)
#    if @isdefined(server)
#        close(server)
#    end

    app = Bonito.App(title="CliMA dashboard") do session
        # Load simulation data
        simdir = ClimaAnalysis.SimDir(path)
        vars = collect(keys(simdir.vars))

        # Create dark mode checkbox first so we can use it for styling (default to dark mode)
        checkbox_style = Bonito.Styles(
            "width" => "18px",
            "height" => "18px",
            "cursor" => "pointer",
            "accent-color" => "#2196F3",
            "margin" => "0",
            "transform" => "scale(1.1)"
        )
        dark_mode_checkbox = Bonito.Checkbox(true; style = checkbox_style)  # Start in dark mode
        dark_mode = dark_mode_checkbox.value

        # Create UI controls (wider menu with bigger fonts)
        var_menu_style = map(dark_mode) do is_dark
            Bonito.Styles(
                "font-size" => "0.95rem",
                "font-weight" => "bold",
                "padding" => "6px 8px",
                "border-radius" => "4px",
                "cursor" => "pointer",
                "min-width" => "80px",
                "max-width" => "180px",
                "color" => "black"
            )
        end
        var_menu = Bonito.ChoicesBox(vars; style = var_menu_style)
        var_menu.value[] = first(vars)
        var_selected = var_menu.value

        # Get available reductions and periods for initial variable
        initial_var_name = var_selected[]
        available_reductions = collect(keys(simdir.vars[initial_var_name]))
        initial_reduction = first(available_reductions)

        dropdown_style = Bonito.Styles(
            "font-size" => "0.95rem",
            "padding" => "6px 8px",
            "border-radius" => "4px",
            "cursor" => "pointer",
            "min-width" => "80px",
            "max-width" => "180px"
        )

        reduction_menu = Bonito.Dropdown(available_reductions; style = dropdown_style)
        reduction_menu.value[] = initial_reduction
        reduction_selected = reduction_menu.value

        available_periods = collect(keys(simdir.vars[initial_var_name][initial_reduction]))
        initial_period = first(available_periods)

        period_menu = Bonito.Dropdown(available_periods; style = dropdown_style)
        period_menu.value[] = initial_period
        period_selected = period_menu.value

        # Initialize with selected variable
        initial_var = get(simdir; short_name = var_selected[], reduction = reduction_selected[], period = period_selected[])
        lon = initial_var.dims["lon"]
        lat = initial_var.dims["lat"]
        times = initial_var.dims["time"]
        dates_array = ClimaAnalysis.dates(initial_var)

        # Create observables and sliders
        var = Observable{OutputVarAny}(initial_var)
        time_slider = Bonito.StylableSlider(1:length(times))
        time_selected = time_slider.value

        heights = has_height(var[]) ? var[].dims[get_height_dim_name(var[])] : Float64[]
        initial_height_idx = max(1, length(heights))

        # Create height slider with initial range
        height_slider = Bonito.StylableSlider(1:max(1, length(heights)))
        height_slider.value[] = initial_height_idx
        height_selected = height_slider.value

        speed_slider = Bonito.StylableSlider(range(0.0, 0.3, length=31))
        speed_slider.value[] = 0.1
        speed_selected = speed_slider.value

        # Create square pause/play toggle button with symbols
        button_style = Bonito.Styles(
            "padding" => "8px",
            "font-size" => "1.2rem",
            "font-weight" => "bold",
            "border-radius" => "4px",
            "border" => "2px solid #888888",
            "background-color" => "#888888",
            "color" => "white",
            "cursor" => "pointer",
            "width" => "40px",
            "height" => "40px",
            "display" => "flex",
            "align-items" => "center",
            "justify-content" => "center"
        )
        is_playing = Observable(false)
        button_label = Observable("▶")
        play_button = Bonito.Button(button_label; style = button_style)

        # Transparency gradient controls for 3D (3D always uses transparent gradient mode)
        # Slider for quantiles threshold (controls the quantile range)
        # Range from 0.01 to 0.25 with 10 steps
        # Value represents the lower quantile (upper is automatically 1 - value)
        slider_style = Bonito.Styles(
            "min-width" => "30px",
            "width" => "80px"
        )
        transparency_quantiles_slider = Bonito.StylableSlider(range(0.01, 0.25, length=10); style = slider_style)
        transparency_quantiles_slider.value[] = 0.05  # Default to current behavior
        transparency_quantiles = transparency_quantiles_slider.value

        # Dropdown for normal/inverted transparency
        transparency_direction_options = ["normal", "inverted"]
        transparency_direction_menu = Bonito.Dropdown(transparency_direction_options; style = dropdown_style)
        transparency_direction_menu.value[] = "normal"
        transparency_direction = transparency_direction_menu.value

        # Dropdown for color selection
        color_options = ["white", "black", "green", "blue"]
        transparency_color_menu = Bonito.Dropdown(color_options; style = dropdown_style)
        transparency_color_menu.value[] = "white"
        transparency_color = transparency_color_menu.value

        # Create fixed observable for transparency gradient (always true for 3D, always false for 2D)
        transparency_gradient = Observable(true)

        # Create observable for showing height dimension
        show_height = Observable(has_height(var[]))

        # Create value labels (white text for dark mode default)
        value_style = Bonito.Styles("font-size" => "0.9rem", "color" => "white")
        time_value_text = Observable(Dates.format(dates_array[time_selected[]], "u yyyy"))
        time_value_label = Bonito.DOM.h1(time_value_text; style = value_style)

        height_value_text = Observable(has_height(var[]) ? string(round(heights[height_selected[]], digits=1), " m") : "N/A")
        height_value_label = Bonito.DOM.h1(height_value_text; style = value_style)

        speed_value_text = Observable(string(round(speed_selected[], digits=2), " s"))
        speed_value_label = Bonito.DOM.h1(speed_value_text; style = value_style)

        quantiles_value_text = Observable(string(round(Int, transparency_quantiles[] * 100), "%"))
        quantiles_value_label = Bonito.DOM.h1(quantiles_value_text; style = value_style)

        # Create data observables
        var_sliced = Observable(var_slice(var[], time_selected[]; height_selected = height_selected[]))
        limits = Observable(get_limits(var[], time_selected[]; height_selected = height_selected[]))

        lon_profile = Observable(-118.25)  # Los Angeles
        lat_profile = Observable(34.05)    # Los Angeles

        # Initialize profile with dummy data if no height dimension
        # This ensures the plot elements are created properly
        if has_height(var[])
            profile = Observable(get_profile(var[], lon_profile[], lat_profile[], time_selected[]))
            profile_limits = Observable(get_limits(var[], time_selected[]; height_selected = height_selected[], low_q = 0.0, high_q = 1.0))
            current_height = Observable(heights[height_selected[]])
        else
            # Use dummy data for initialization - single point to create valid plot
            profile = Observable([0.0])
            profile_limits = Observable((0.0, 1.0))
            current_height = Observable(0.0)
        end

        timeseries = Observable(get_timeseries(var[], lon_profile[], lat_profile[]; height_selected = height_selected[]))

        # Create title observables
        profile_title = Observable(profile_title_string(var[], dates_array, time_selected[], lon_profile[], lat_profile[]))
        timeseries_title = Observable(timeseries_title_string(var[], heights, height_selected[], lon_profile[], lat_profile[]))

        # Download Earth image once for both 2D and 3D figures (1024px for lower memory usage)
        earth_img = FileIO.load(download("https://upload.wikimedia.org/wikipedia/commons/thumb/5/56/Blue_Marble_Next_Generation_%2B_topography_%2B_bathymetry.jpg/1024px-Blue_Marble_Next_Generation_%2B_topography_%2B_bathymetry.jpg"))

        # Create figures (with black background for dark mode by default)
        fig, ax, title, coastlines_plot, cbar, surface_plot_colormap, surface_plot_rgba, rgba_colors, earth_surface, colorbar_label = create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, :black, earth_img)

        # Create 3D globe figure
        fig_3d, ax_3d, title_3d, coastlines_plot_3d, cbar_3d, surface_plot_3d_colormap, surface_plot_3d_rgba, rgba_colors_3d, earth_surface_3d, colorbar_label_3d, stars = create_main_figure_3d(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, :black, earth_img)

        fig_profile, ax_profile, profile_xlabel, profile_lines, profile_hlines, heights_obs, profile_box =
            create_profile_figure(var, heights, profile, profile_limits, current_height, profile_title, time_selected, :black, show_height)

        # Set initial visibility of axis decorations based on whether variable has height
        initial_has_height = show_height[]
        ax_profile.xticksvisible = initial_has_height
        ax_profile.yticksvisible = initial_has_height
        ax_profile.xticklabelsvisible = initial_has_height
        ax_profile.yticklabelsvisible = initial_has_height
        ax_profile.xlabelvisible = initial_has_height
        ax_profile.ylabelvisible = initial_has_height
        ax_profile.titlevisible = initial_has_height
        ax_profile.leftspinevisible = initial_has_height
        ax_profile.rightspinevisible = initial_has_height
        ax_profile.topspinevisible = initial_has_height
        ax_profile.bottomspinevisible = initial_has_height

        fig_timeseries, ax_timeseries, timeseries_ylabel, current_time_index, n_ticks, timeseries_lines =
            create_timeseries_figure(var, dates_array, timeseries, timeseries_title, time_selected, :black)

        # Create AppState to bundle all state
        state = AppState(
            simdir, var, dates_array, heights, times,
            var_sliced, limits, title,
            lon_profile, lat_profile, profile, profile_limits, current_height, profile_title, profile_xlabel,
            heights_obs,
            timeseries, timeseries_title, timeseries_ylabel, current_time_index,
            time_selected, height_selected, speed_selected,
            time_value_text, height_value_text, speed_value_text, quantiles_value_text,
            dark_mode, Observable(:white),  # fig_bg_color (not used anymore but kept for compatibility)
            show_height,
            transparency_gradient, transparency_direction, transparency_color, transparency_quantiles,
            ax, ax_3d, ax_profile, ax_timeseries, profile_lines, profile_hlines, timeseries_lines, coastlines_plot, coastlines_plot_3d, cbar, cbar_3d, colorbar_label, colorbar_label_3d, profile_box,
            surface_plot_colormap, surface_plot_rgba, surface_plot_3d_colormap, surface_plot_3d_rgba,
            rgba_colors, rgba_colors_3d,
            earth_surface, earth_surface_3d, earth_img,
            lon, lat,
            fig, fig_3d, fig_profile, fig_timeseries,
            n_ticks,
            false  # updating flag
        )

        # Update main title using state
        if has_height(var[])
            update_title_with_height(state, time_selected[], heights[height_selected[]])
        else
            update_title(state, time_selected[])
        end

        # Set up all event handlers - they now access heights_obs and profile_combined from state
        setup_mouse_click_handler(fig, state)
        setup_variable_handler(var_menu, reduction_menu, period_menu, height_slider, state)
        setup_reduction_handler(reduction_menu, period_menu, state)
        setup_period_handler(period_menu, reduction_menu, state)
        setup_time_handler(time_slider, state)
        setup_height_handler(height_slider, state)
        setup_speed_handler(speed_slider, state)
        setup_quantiles_handler(transparency_quantiles_slider, state)
        setup_play_handler(play_button, time_slider, state, is_playing, button_label)
        setup_transparency_gradient_handler(state)
        setup_dark_mode_handler(state, session)

        # Trigger dark mode handler to apply initial dark mode styles
        notify(dark_mode)

        # Delete 3D colorbar since 3D always uses transparent gradient mode (no colorbar needed)
        delete!(cbar_3d)

        # Initialize 3D RGBA colors (3D always uses transparent gradient mode)
        # Trigger initial computation by notifying var_sliced
        notify(state.var_sliced)

        # Toggle profile_box visibility and axis decorations when show_height changes
        # The box is visible when there's no height dimension (covers the profile)
        # Also hide axis decorations (spines, ticks, labels, title) when there's no height
        on(show_height) do has_height
            profile_box.visible = !has_height
            # Hide all axis decorations when there's no height
            ax_profile.xticksvisible = has_height
            ax_profile.yticksvisible = has_height
            ax_profile.xticklabelsvisible = has_height
            ax_profile.yticklabelsvisible = has_height
            ax_profile.xlabelvisible = has_height
            ax_profile.ylabelvisible = has_height
            ax_profile.titlevisible = has_height
            ax_profile.leftspinevisible = has_height
            ax_profile.rightspinevisible = has_height
            ax_profile.topspinevisible = has_height
            ax_profile.bottomspinevisible = has_height
        end

        # Setup initial zoom for 3D globe (since it's always visible now)
        # Use a Timer to zoom after scene is rendered
        Timer(1.0) do timer
            try
                println("Applying initial zoom to 3D globe...")
                zoom!(ax_3d.scene, 0.04)  # Values < 1.0 zoom IN, > 1.0 zoom OUT
                println("Zoom applied successfully!")
            catch e
                println("Warning: Could not apply zoom to 3D globe: ", e)
            end
        end

        # Set initial colors for dark mode (since we start in dark mode)
        ax.titlecolor = :white
        coastlines_plot.color = :white
        cbar.labelcolor = :white
        cbar.ticklabelcolor = :white
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
        # Show stars initially (dark mode default)
        stars[1].visible = true
        stars[2].visible = true

        # Also update 3D figure background when dark mode changes
        on(dark_mode) do is_dark
            bg_rgba = is_dark ? RGBf(0, 0, 0) : RGBf(1, 1, 1)
            text_color = is_dark ? :white : :black
            line_color = is_dark ? :white : :black
            fig_3d.scene.backgroundcolor[] = bg_rgba
            ax_3d.titlecolor = text_color
            # Update 3D coastlines color
            coastlines_plot_3d.color = line_color
            # Toggle stars visibility - show in dark mode only
            # stars is a tuple of (main_stars, halo_stars)
            stars[1].visible = is_dark
            stars[2].visible = is_dark
        end

        # Return layout
        return layout(var_menu, reduction_menu, period_menu, time_slider, height_slider, play_button, speed_slider,
                     fig, fig_3d, fig_profile, fig_timeseries, show_height, profile_lines, profile_hlines,
                     time_value_label, height_value_label, speed_value_label, dark_mode_checkbox, dark_mode,
                     transparency_quantiles_slider, quantiles_value_label, transparency_direction_menu, transparency_color_menu)
    end

    # Those lines below should be run for HPC
    if HPC == true
        IP = "127.0.0.1"
        port = 8080
        global server = Bonito.Server(IP, port; proxy_url = "http://localhost:$port")
        Bonito.route!(server, "/" => app)
        print_startup_message(port)
    end

    return app
end

# on Microsoft Azure run:
#=
    using ClimaViz
    path_atmos = "data/climaland_longrun"
    path_land = "data/climaatmos"
    IP = "127.0.0.1"
    port = 9385
    # if Azure
    server = Bonito.Server(IP, port; proxy_url = "https://clima.westus3.cloudapp.azure.com/jsserve/")
    # if local
    server = Bonito.Server(IP, port; proxy_url = "http://localhost:$port")
    atmos_app = dashboard(path_atmos);
    land_app = dashboard(path_land);
    Bonito.route!(server, "/atmos" => atmos_app)
    Bonito.route!(server, "/land" => land_app)
=#
