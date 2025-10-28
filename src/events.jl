# Handle mouse click on map for location selection
function setup_mouse_click_handler(fig, state::AppState)
    on(events(fig).mousebutton) do event
        if event.button == Mouse.left && event.action == Mouse.press
            mp = mouseposition(state.ax)
            trans = Proj.Transformation(state.ax.dest[], state.ax.source[]; always_xy=true)
            lonlat = trans(mp)

            state.lon_profile[] = lonlat[1]
            state.lat_profile[] = lonlat[2]

            println("\n=== MOUSE CLICK DEBUG ===")
            println("Clicked at (lon, lat): $lonlat")
            println("Variable has height: ", has_height(state.var[]))

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
