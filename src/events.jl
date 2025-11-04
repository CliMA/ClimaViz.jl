# Handle mouse click on map for location selection
function setup_mouse_click_handler(fig, state::AppState)
    on(events(fig).mousebutton) do event
        if event.button == Mouse.left && event.action == Mouse.press
            # mouseposition gives coordinates in axis data space (handles CSS scaling)
            mp = mouseposition(state.ax)

            println("\n=== MOUSE CLICK DEBUG ===")
            println("mouseposition: $mp")

            # Transform from projection coordinates (meters) to lon/lat
            trans = Proj.Transformation(state.ax.dest[], state.ax.source[]; always_xy=true)
            lonlat = trans(mp)

            println("Transformed lon/lat: lon=$(lonlat[1]), lat=$(lonlat[2])")
            println("=========================\n")

            state.lon_profile[] = lonlat[1]
            state.lat_profile[] = lonlat[2]

            # Update profile if variable has height
            if has_height(state.var[])
                state.profile[] = get_profile(state.var[], state.lon_profile[], state.lat_profile[], state.time_selected[])
                # Calculate limits across ALL times at this location
                state.profile_limits[] = get_profile_limits_all_times(state.var[], state.lon_profile[], state.lat_profile[])
                xlims!(state.ax_profile, state.profile_limits[])

                println("Heights: ", state.heights)
                println("Profile data length: ", length(state.profile[]))
                println("Profile data: ", state.profile[])
                println("Profile lines visible: ", state.profile_lines.visible[])
                println("Profile hlines visible: ", state.profile_hlines.visible[])
            else
                println("No height dimension - skipping profile update")
            end
            println("========================\n")

            # Update titles with new location
            state.profile_title[] = profile_title_string(state.var[], state.dates_array, state.time_selected[], state.lon_profile[], state.lat_profile[])
            state.timeseries_title[] = timeseries_title_string(state.var[], state.heights, state.height_selected[], state.lon_profile[], state.lat_profile[])

            # Update time series
            state.timeseries[] = get_timeseries(state.var[], state.lon_profile[], state.lat_profile[]; height_selected = state.height_selected[])
            autolimits!(state.ax_timeseries)
        end
    end
end

# Handle variable menu selection
function setup_variable_handler(var_menu, reduction_menu, period_menu, height_slider, state::AppState, heights_obs)
    on(var_menu.value) do v
        # Set flag to prevent other handlers from firing
        state.updating = true

        try
            println("\n=== VARIABLE CHANGE DEBUG ===")
            println("New variable: $v")

            # Get available reductions for this variable
            available_reductions = collect(keys(state.simdir.vars[v]))

            # Set reduction option_index to 1 first (always safe)
            reduction_menu.option_index[] = 1

            # Set reduction to first available
            first_reduction = first(available_reductions)
            reduction_menu.value[] = first_reduction

            # Now update reduction options
            reduction_menu.options[] = available_reductions

            # Get available periods for this reduction
            available_periods = collect(keys(state.simdir.vars[v][first_reduction]))

            # Set period option_index to 1 first (always safe)
            period_menu.option_index[] = 1

            # Set period to first available
            first_period = first(available_periods)
            period_menu.value[] = first_period

            # Now update period options
            period_menu.options[] = available_periods

            # Get the new variable
            new_var = get(state.simdir; short_name = v, reduction = first_reduction, period = first_period)

            println("New variable has height: ", has_height(new_var))

            # Update heights and slider
            heights_new = has_height(new_var) ? new_var.dims[get_height_dim_name(new_var)] : Float64[]

            println("New heights: ", heights_new)

            # Update height slider
            # First, set index to 1 (always safe)
            height_slider.index[] = 1

            # Update the slider values (the available options)
            new_values = collect(1:max(1, length(heights_new)))
            height_slider.values[] = new_values

            # Now set slider to the desired index
            new_height_idx = has_height(new_var) ? length(heights_new) : 1
            height_slider.index[] = new_height_idx

            # Update all variable state
            update_for_new_variable(state, new_var, heights_new, heights_obs)

            println("After update - Profile lines visible: ", state.profile_lines.visible[])
            println("After update - Profile hlines visible: ", state.profile_hlines.visible[])
            println("=============================\n")
        finally
            # Always reset the flag
            state.updating = false
        end
    end
end

# Handle reduction menu selection
function setup_reduction_handler(reduction_menu, period_menu, state::AppState, heights_obs)
    on(reduction_menu.value) do reduction
        # Skip if we're in the middle of updating
        if state.updating
            return
        end

        state.updating = true

        try
            # Get current variable name from state
            var_name = ClimaAnalysis.short_name(state.var[])

            # Get available periods for this reduction
            available_periods = collect(keys(state.simdir.vars[var_name][reduction]))

            # Set period option_index to 1 first (always safe)
            period_menu.option_index[] = 1

            # Set period to first available
            first_period = first(available_periods)
            period_menu.value[] = first_period

            # Now update period options
            period_menu.options[] = available_periods

            # Get the new variable
            new_var = get(state.simdir; short_name = var_name, reduction = reduction, period = first_period)

            # Update heights
            heights_new = has_height(new_var) ? new_var.dims[get_height_dim_name(new_var)] : Float64[]

            # Update everything (reuse the same logic from variable handler)
            update_for_new_variable(state, new_var, heights_new, heights_obs)
        finally
            state.updating = false
        end
    end
end

# Handle period menu selection
function setup_period_handler(period_menu, reduction_menu, state::AppState, heights_obs)
    on(period_menu.value) do period
        # Skip if we're in the middle of updating
        if state.updating
            return
        end

        state.updating = true

        try
            # Get current variable name and reduction
            var_name = ClimaAnalysis.short_name(state.var[])
            reduction = reduction_menu.value[]

            # Get the new variable
            new_var = get(state.simdir; short_name = var_name, reduction = reduction, period = period)

            # Update heights
            heights_new = has_height(new_var) ? new_var.dims[get_height_dim_name(new_var)] : Float64[]

            # Update everything
            update_for_new_variable(state, new_var, heights_new, heights_obs)
        finally
            state.updating = false
        end
    end
end

# Helper function to update all state when variable changes
function update_for_new_variable(state::AppState, new_var, heights_new, heights_obs)
    println("\n--- UPDATE FOR NEW VARIABLE ---")
    println("Has height: ", has_height(new_var))
    println("Heights new: ", heights_new)

    # Update the variable in state
    state.var[] = new_var

    # Update show_height based on new variable
    state.show_height[] = has_height(new_var)

    # Update heights for new variable
    empty!(state.heights)
    append!(state.heights, heights_new)

    # CRITICAL: Update the heights observable so the plot updates
    if length(heights_new) > 0
        heights_obs[] = collect(heights_new)
        println("Updated heights_obs to: ", heights_obs[])
    else
        heights_obs[] = [0.0]
        println("Updated heights_obs to dummy: ", heights_obs[])
    end

    println("State heights after update: ", state.heights)

    # Update visualization
    state.var_sliced[] = var_slice(state.var[], state.time_selected[]; height_selected = state.height_selected[])
    state.limits[] = get_limits(state.var[], state.time_selected[]; height_selected = state.height_selected[])

    # Update title
    if has_height(state.var[])
        update_title_with_height(state, state.time_selected[], state.heights[state.height_selected[]])
    else
        update_title(state, state.time_selected[])
    end

    # Update axis labels with new variable info
    state.profile_xlabel[] = string(ClimaAnalysis.short_name(state.var[]), " [", ClimaAnalysis.units(state.var[]), "]")
    state.timeseries_ylabel[] = string(ClimaAnalysis.short_name(state.var[]), " [", ClimaAnalysis.units(state.var[]), "]")

    # Update dates array for new variable
    dates_array_new = ClimaAnalysis.dates(state.var[])
    empty!(state.dates_array)
    append!(state.dates_array, dates_array_new)

    # Update x-axis tick labels
    tick_indices = round.(Int, range(1, length(state.dates_array), length=state.n_ticks))
    tick_labels = [Dates.format(state.dates_array[i], "u yyyy") for i in tick_indices]
    state.ax_timeseries.xticks = (tick_indices, tick_labels)

    # Update titles
    state.timeseries_title[] = timeseries_title_string(state.var[], state.heights, state.height_selected[], state.lon_profile[], state.lat_profile[])
    state.profile_title[] = profile_title_string(state.var[], state.dates_array, state.time_selected[], state.lon_profile[], state.lat_profile[])

    # Update height value label
    if has_height(state.var[])
        state.height_value_text[] = string(round(state.heights[state.height_selected[]], digits=1), " m")
    else
        state.height_value_text[] = "N/A"
    end

    # Update profile and timeseries
    if has_height(state.var[])
        state.profile[] = get_profile(state.var[], state.lon_profile[], state.lat_profile[], state.time_selected[])
        # Calculate limits across ALL times at this location for stable visualization
        state.profile_limits[] = get_profile_limits_all_times(state.var[], state.lon_profile[], state.lat_profile[])
        xlims!(state.ax_profile, state.profile_limits[])
        state.current_height[] = state.heights[state.height_selected[]]

        println("Profile data: ", state.profile[])
        println("Profile limits: ", state.profile_limits[])
        println("Current height: ", state.current_height[])

        # Show profile figure when variable has height
        println("Setting profile visibility to TRUE")
        state.profile_lines.visible = true
        state.profile_hlines.visible = true

        # Force axis update
        autolimits!(state.ax_profile)
        xlims!(state.ax_profile, state.profile_limits[])

        println("Profile lines visible after setting: ", state.profile_lines.visible[])
        println("Profile hlines visible after setting: ", state.profile_hlines.visible[])
    else
        println("Setting profile visibility to FALSE")
        # Hide profile figure when variable has no height
        state.profile_lines.visible = false
        state.profile_hlines.visible = false
    end
    state.timeseries[] = get_timeseries(state.var[], state.lon_profile[], state.lat_profile[]; height_selected = state.height_selected[])
    autolimits!(state.ax_timeseries)

    println("-------------------------------\n")
end

# Handle time slider changes
function setup_time_handler(time_slider, state::AppState)
    on(time_slider.value) do t
        state.var_sliced[] = var_slice(state.var[], t; height_selected = state.height_selected[])

        # Update title
        if has_height(state.var[])
            update_title_with_height(state, t, state.heights[state.height_selected[]])
        else
            update_title(state, t)
        end

        # Update vertical line position in timeseries
        state.current_time_index[] = t

        # Update time value label
        state.time_value_text[] = Dates.format(state.dates_array[t], "u yyyy")

        # Update profile title with new date
        state.profile_title[] = profile_title_string(state.var[], state.dates_array, t, state.lon_profile[], state.lat_profile[])

        if has_height(state.var[])
            # Update profile data but NOT the limits (limits stay fixed for animation)
            state.profile[] = get_profile(state.var[], state.lon_profile[], state.lat_profile[], t)
        end
    end
end

# Handle height slider changes
function setup_height_handler(height_slider, state::AppState)
    on(height_slider.value) do h
        # Guard against invalid height indices
        if !has_height(state.var[]) || h < 1 || h > length(state.heights)
            return
        end

        state.var_sliced[] = var_slice(state.var[], state.time_selected[]; height_selected = h)
        state.limits[] = get_limits(state.var[], state.time_selected[]; height_selected = h)

        # Update title with new height
        update_title_with_height(state, state.time_selected[], state.heights[h])

        # Update time series for new height
        state.timeseries[] = get_timeseries(state.var[], state.lon_profile[], state.lat_profile[]; height_selected = h)
        autolimits!(state.ax_timeseries)

        # Update height value label
        state.height_value_text[] = string(round(state.heights[h], digits=1), " m")

        # Update profile limits directly from current profile data (don't recalculate)
        # The profile doesn't change when height changes, so we don't need to update limits
        state.current_height[] = state.heights[h]
        state.timeseries_title[] = timeseries_title_string(state.var[], state.heights, h, state.lon_profile[], state.lat_profile[])
    end
end

# Handle speed slider changes
function setup_speed_handler(speed_slider, state::AppState)
    on(speed_slider.value) do s
        state.speed_value_text[] = string(round(s, digits=2), " s")
    end
end

# Handle play button for animation
function setup_play_handler(play_button, time_slider, state::AppState)
    n_times = length(state.times)
    on(play_button) do _
        println("Playing animation")
        for t in 1:n_times
            state.var_sliced[] = var_slice(state.var[], t; height_selected = state.height_selected[])

            # Update title
            if has_height(state.var[])
                update_title_with_height(state, t, state.heights[state.height_selected[]])
            else
                update_title(state, t)
            end

            if has_height(state.var[])
                # Update profile data but NOT the limits (limits stay fixed for animation)
                state.profile[] = get_profile(state.var[], state.lon_profile[], state.lat_profile[], t)
            end

            # Update time slider value to move the vertical line
            time_slider.value[] = t

            sleep(state.speed_selected[])
        end
    end
end

# Handle dark mode toggle
function setup_dark_mode_handler(state::AppState, session)
    # Set up JavaScript callback for CSS changes
    Bonito.onjs(session, state.dark_mode, Bonito.js"""
    function (is_dark) {
        if (is_dark) {
            document.body.style.backgroundColor = 'black';
            document.body.style.color = 'white';
            // Update all cards
            document.querySelectorAll('.card').forEach(card => {
                card.style.backgroundColor = 'black';
                card.style.color = 'white';
                card.style.borderColor = 'black';
            });
            // Update all text elements except inputs/checkboxes
            document.querySelectorAll('h1, label, span, p').forEach(el => {
                el.style.color = 'white';
            });
            // Update input elements (sliders, dropdowns, etc.) - keep them light for visibility
            document.querySelectorAll('input, select').forEach(input => {
                input.style.backgroundColor = '#333';
                input.style.color = 'white';
                input.style.borderColor = '#555';
            });
            // Update Makie canvas containers (figure backgrounds)
            document.querySelectorAll('canvas').forEach(canvas => {
                // Set the canvas parent background
                if (canvas.parentElement) {
                    canvas.parentElement.style.backgroundColor = 'black';
                }
                // Also check grandparent
                if (canvas.parentElement && canvas.parentElement.parentElement) {
                    canvas.parentElement.parentElement.style.backgroundColor = 'black';
                }
            });
            // Target any div that might contain the figures
            document.querySelectorAll('div').forEach(div => {
                if (div.querySelector('canvas')) {
                    div.style.backgroundColor = 'black';
                }
            });
        } else {
            document.body.style.backgroundColor = 'white';
            document.body.style.color = 'black';
            // Update all cards
            document.querySelectorAll('.card').forEach(card => {
                card.style.backgroundColor = 'white';
                card.style.color = 'black';
                card.style.borderColor = '#e0e0e0';
            });
            // Update all text elements
            document.querySelectorAll('h1, label, span, p').forEach(el => {
                el.style.color = 'black';
            });
            // Reset input elements
            document.querySelectorAll('input, select').forEach(input => {
                input.style.backgroundColor = '';
                input.style.color = '';
                input.style.borderColor = '';
            });
            // Update Makie canvas containers (figure backgrounds)
            document.querySelectorAll('canvas').forEach(canvas => {
                // Set the canvas parent background
                if (canvas.parentElement) {
                    canvas.parentElement.style.backgroundColor = 'white';
                }
                // Also check grandparent
                if (canvas.parentElement && canvas.parentElement.parentElement) {
                    canvas.parentElement.parentElement.style.backgroundColor = 'white';
                }
            });
            // Target any div that might contain the figures
            document.querySelectorAll('div').forEach(div => {
                if (div.querySelector('canvas')) {
                    div.style.backgroundColor = 'white';
                }
            });
        }
    }
    """)

    # Julia-side updates for Makie plots
    on(state.dark_mode) do is_dark
        println("Dark mode: ", is_dark)

        if is_dark
            # Dark mode colors
            bg_color = :black
            text_color = :white
            line_color = :white
            # Convert to RGBA for scene backgroundcolor
            bg_rgba = RGBf(0, 0, 0)
        else
            # Light mode colors
            bg_color = :white
            text_color = :black
            line_color = :black
            # Convert to RGBA for scene backgroundcolor
            bg_rgba = RGBf(1, 1, 1)
        end

        # Update figure background colors directly (need RGBA type)
        state.fig.scene.backgroundcolor[] = bg_rgba
        state.fig_profile.scene.backgroundcolor[] = bg_rgba
        state.fig_timeseries.scene.backgroundcolor[] = bg_rgba

        # Update main figure (map) - GeoAxis only supports title color
        state.ax.titlecolor = text_color

        # Update coastlines color
        state.coastlines_plot.color = line_color

        # Update colorbar text colors
        state.colorbar.labelcolor = text_color
        state.colorbar.ticklabelcolor = text_color

        # Update profile axis
        state.ax_profile.backgroundcolor = bg_color
        state.ax_profile.titlecolor = text_color
        state.ax_profile.xlabelcolor = text_color
        state.ax_profile.ylabelcolor = text_color
        state.ax_profile.xticklabelcolor = text_color
        state.ax_profile.yticklabelcolor = text_color

        # Update profile lines color
        state.profile_lines.color = line_color

        # Update timeseries axis
        state.ax_timeseries.backgroundcolor = bg_color
        state.ax_timeseries.titlecolor = text_color
        state.ax_timeseries.xlabelcolor = text_color
        state.ax_timeseries.ylabelcolor = text_color
        state.ax_timeseries.xticklabelcolor = text_color
        state.ax_timeseries.yticklabelcolor = text_color

        # Update timeseries lines color
        state.timeseries_lines.color = line_color
    end
end
