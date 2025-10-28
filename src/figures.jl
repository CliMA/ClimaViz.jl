export create_main_figure, create_profile_figure, create_timeseries_figure

# Create main map figure with surface plot
function create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile)
    fig = Figure(size = (2000, 1000))
    title = Observable("title")
    ax = GeoAxis(fig[1, 1], title = title, titlesize = 24.0f0)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax, :scrollzoom)

    # Surface plot
    p = surface!(ax, lon, lat, var_sliced,
                 colorrange = limits,
                 lowclip = (:black, 0.7),
                 highclip = (:yellow, 0.8),
                 shading = NoShading,
                 colormap = :thermal,
                 transparency = true,
                 alpha = 0.8)

    lines!(ax, GeoMakie.coastlines(), color = :black)

    # Add marker on map showing current location
    scatter!(ax, lon_profile, lat_profile,
            color = (:red, 0.7),
            markersize = 30,
            marker = :circle)

    # Create colorbar label with variable name and units
    colorbar_label = Observable(string(
        ClimaAnalysis.short_name(var[]),
        " [",
        ClimaAnalysis.units(var[]),
        "]"
    ))

    # Colorbar on the right side
    Colorbar(
             fig[1, 2],
             p,
             vertical = true,
             colorrange = limits,
             width = 15,
             ticklabelsize = 20.0,
             label = colorbar_label,
             labelsize = 30.0
            )

    # Update colorbar label when variable changes
    on(var) do v
        colorbar_label[] = string(
            ClimaAnalysis.short_name(v),
            " [",
            ClimaAnalysis.units(v),
            "]"
        )
    end

    return fig, ax, title
end

# Create vertical profile figure
function create_profile_figure(var, heights, profile, profile_limits, current_height,
                               profile_title, time_selected)
    fig_profile = Figure(size = (800, 500))
    profile_xlabel = Observable(string(ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]"))

    ax_profile = Axis(fig_profile[1, 1],
                     xlabel = profile_xlabel, ylabel = "Height [m]",
                     title = profile_title,
                     xlabelsize = 20, ylabelsize = 20,
                     xticklabelsize = 18, yticklabelsize = 18,
                     titlesize = 24)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax_profile, :scrollzoom)

    # Create observable for heights so it can be updated
    heights_obs = Observable(length(heights) > 0 ? heights : [0.0])

    # Create profile plot elements with observable heights
    profile_lines = lines!(ax_profile, profile, heights_obs, color = :black, linewidth = 3, visible = has_height(var[]))
    xlims!(ax_profile, profile_limits[])
    profile_hlines = hlines!(ax_profile, current_height, color = :grey, linestyle = :dash, linewidth = 2, visible = has_height(var[]))

    fig_profile
    return fig_profile, ax_profile, profile_xlabel, profile_lines, profile_hlines, heights_obs
end

# Create time series figure
function create_timeseries_figure(var, dates_array, timeseries, timeseries_title, time_selected)
    fig_timeseries = Figure(size = (800, 500))
    timeseries_ylabel = Observable(string(ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]"))

    ax_timeseries = Axis(fig_timeseries[1, 1],
                        xlabel = "", ylabel = timeseries_ylabel,
                        title = timeseries_title,
                        xlabelsize = 20, ylabelsize = 20,
                        xticklabelsize = 18, yticklabelsize = 18,
                        titlesize = 24,
                        xticklabelrotation = π/4)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax_timeseries, :scrollzoom)

    # Use numeric indices for plotting
    time_indices = 1:length(dates_array)
    lines!(ax_timeseries, time_indices, timeseries, color = :black, linewidth = 2)

    # Add vertical line showing current time
    current_time_index = Observable(time_selected[])
    vlines!(ax_timeseries, current_time_index, color = :grey, linestyle = :dash, linewidth = 2)

    # Format x-axis to show dates
    n_ticks = min(10, length(dates_array))
    tick_indices = round.(Int, range(1, length(dates_array), length=n_ticks))
    tick_labels = [Dates.format(dates_array[i], "u yyyy") for i in tick_indices]
    ax_timeseries.xticks = (tick_indices, tick_labels)

    autolimits!(ax_timeseries)

    return fig_timeseries, ax_timeseries, timeseries_ylabel, current_time_index, n_ticks
end
