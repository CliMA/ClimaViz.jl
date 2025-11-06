export create_main_figure, create_main_figure_3d, create_profile_figure, create_timeseries_figure

# Create main map figure with surface plot
function create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color)
    # Large figure that fills screen naturally (minimal CSS scaling)
    fig = Figure(size = (2150, 1200), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")

    # Equirectangular projection
    ax = GeoAxis(fig[1, 1], title = title, titlesize = 16.0f0, dest = "+proj=eqc")

    # Hide axis decorations for cleaner look
    hidedecorations!(ax)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax, :scrollzoom)

    # Surface plot
    p = surface!(ax, lon, lat, var_sliced,
                 colorrange = limits,
                 lowclip = (:black, 0.8),
                 highclip = (:yellow, 0.9),
                 shading = NoShading,
                 colormap = :thermal,
                 transparency = true,
                 alpha = 0.9)

    coastlines_plot = lines!(ax, GeoMakie.coastlines(), color = :black)

    # Add marker on map showing current location
    scatter!(ax, lon_profile, lat_profile,
            color = (:red, 0.7),
            markersize = 20,
            marker = :circle)

    # Create colorbar label with variable name and units
    colorbar_label = Observable(string(
        ClimaAnalysis.short_name(var[]),
        " [",
        ClimaAnalysis.units(var[]),
        "]"
    ))

    # Horizontal colorbar at bottom-right inside the map
    cbar = Colorbar(
             fig[1, 1],
             p,
             vertical = false,
             colorrange = limits,
             width = Relative(0.25),
             height = 13,
             ticklabelsize = 16.0,
             label = colorbar_label,
             labelsize = 19.0,
             halign = :right,
             valign = :bottom,
             tellheight = false,
             tellwidth = false
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

    return fig, ax, title, coastlines_plot, cbar, p
end

# Create main 3D globe figure
function create_main_figure_3d(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color)
    # Large figure that fills screen naturally
    fig = Figure(size = (2150, 1200), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")

    # Use GlobeAxis for 3D globe with title
    ax = GeoMakie.GlobeAxis(fig[1, 1]; show_axis = false, title = title, titlesize = 16.0f0, titlevisible = true)

    # Load Earth image for background
    earth_img = FileIO.load(download("https://upload.wikimedia.org/wikipedia/commons/5/56/Blue_Marble_Next_Generation_%2B_topography_%2B_bathymetry.jpg"))

    # Add Earth image as base surface at z=0
    surface!(ax,
             -180..180, -90..90,
             zeros(axes(rotr90(earth_img)));
             shading = NoShading,
             color = rotr90(earth_img),
             backlight = 1.5f0,
            )

    # Surface plot on globe at elevated z-level (above Earth surface)
    p = surface!(ax, lon, lat, var_sliced,
                 colorrange = limits,
                 lowclip = (:black, 0.8),
                 highclip = (:yellow, 0.9),
                 shading = NoShading,
                 colormap = :thermal,
                 transparency = true,
                 alpha = 0.9,
                 zlevel = 20_000)

    # Add coastlines for 3D globe (black lines, will change with dark mode)
    coastlines_plot_3d = lines!(ax, GeoMakie.coastlines(), color = :black)

    # Add marker on map showing current location (at elevated z-level to be visible above data)
    scatter!(ax, lon_profile, lat_profile,
            color = (:red, 0.7),
            markersize = 20,
            marker = :circle,
            zlevel = 25_000)

    # Create colorbar label with variable name and units
    colorbar_label = Observable(string(
        ClimaAnalysis.short_name(var[]),
        " [",
        ClimaAnalysis.units(var[]),
        "]"
    ))

    # Horizontal colorbar at bottom-right inside the map
    cbar = Colorbar(
             fig[1, 1],
             p,
             vertical = false,
             colorrange = limits,
             width = Relative(0.25),
             height = 13,
             ticklabelsize = 16.0,
             label = colorbar_label,
             labelsize = 19.0,
             halign = :right,
             valign = :bottom,
             tellheight = false,
             tellwidth = false
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

    return fig, ax, title, coastlines_plot_3d, cbar, p
end

# Create vertical profile figure
function create_profile_figure(var, heights, profile, profile_limits, current_height,
                               profile_title, time_selected, bg_color, show_height)
    # Scaled to 67% for better fit at 100% zoom
    fig_profile = Figure(size = (400, 350), backgroundcolor = bg_color, figure_padding = 0)
    profile_xlabel = Observable(string(ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]"))

    ax_profile = Axis(fig_profile[1, 1],
                     xlabel = profile_xlabel, ylabel = "Height [m]",
                     title = profile_title,
                     xlabelsize = 13, ylabelsize = 13,
                     xticklabelsize = 12, yticklabelsize = 12,
                     titlesize = 16)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax_profile, :scrollzoom)

    # Create observable for heights so it can be updated
    heights_obs = Observable(length(heights) > 0 ? heights : [0.0])

    # Create profile plot elements with separate x,y observables - simple and direct
    # No longer need to control visibility of lines - the Box will cover them
    profile_lines = lines!(ax_profile, profile, heights_obs, color = :black, linewidth = 3)
    xlims!(ax_profile, profile_limits[])
    profile_hlines = hlines!(ax_profile, current_height, color = :grey, linestyle = :dash, linewidth = 2)

    # Create a Box that covers the figure when there's no height dimension
    # The box is white in normal mode, black in dark mode
    # It's visible when show_height is false (i.e., when there's no height dimension)
    profile_box = Box(fig_profile[1, 1],
                      color = bg_color,
                      strokevisible = false,
                      visible = !show_height[],
                      tellwidth = false,
                      tellheight = false)

    fig_profile
    return fig_profile, ax_profile, profile_xlabel, profile_lines, profile_hlines, heights_obs, profile_box
end

# Create time series figure
function create_timeseries_figure(var, dates_array, timeseries, timeseries_title, time_selected, bg_color)
    # Scaled to 67% for better fit at 100% zoom
    fig_timeseries = Figure(size = (400, 350), backgroundcolor = bg_color, figure_padding = 0)
    timeseries_ylabel = Observable(string(ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]"))

    ax_timeseries = Axis(fig_timeseries[1, 1],
                        xlabel = "", ylabel = timeseries_ylabel,
                        title = timeseries_title,
                        xlabelsize = 13, ylabelsize = 13,
                        xticklabelsize = 12, yticklabelsize = 12,
                        titlesize = 16,
                        xticklabelrotation = π/4)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax_timeseries, :scrollzoom)

    # Use numeric indices for plotting
    time_indices = 1:length(dates_array)
    timeseries_lines = lines!(ax_timeseries, time_indices, timeseries, color = :black, linewidth = 2)

    # Add vertical line showing current time
    current_time_index = Observable(time_selected[])
    vlines!(ax_timeseries, current_time_index, color = :grey, linestyle = :dash, linewidth = 2)

    # Format x-axis to show dates
    n_ticks = min(10, length(dates_array))
    tick_indices = round.(Int, range(1, length(dates_array), length=n_ticks))
    tick_labels = [Dates.format(dates_array[i], "u yyyy") for i in tick_indices]
    ax_timeseries.xticks = (tick_indices, tick_labels)

    autolimits!(ax_timeseries)

    return fig_timeseries, ax_timeseries, timeseries_ylabel, current_time_index, n_ticks, timeseries_lines
end
