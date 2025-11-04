export create_main_figure, create_main_figure_3d, create_combined_figure_with_boxes, create_profile_figure, create_timeseries_figure

# Create main map figure with surface plot
function create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color)
    # Large figure that fills screen naturally (minimal CSS scaling)
    fig = Figure(size = (3200, 1800), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")

    # Equirectangular projection
    ax = GeoAxis(fig[1, 1], title = title, titlesize = 24.0f0, dest = "+proj=eqc")

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
            markersize = 30,
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
             height = 20,
             ticklabelsize = 24.0,
             label = colorbar_label,
             labelsize = 28.0,
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

    return fig, ax, title, coastlines_plot, cbar
end

# Create main 3D globe figure
function create_main_figure_3d(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color)
    # Large figure that fills screen naturally
    fig = Figure(size = (3200, 1800), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")

    # Use GlobeAxis for 3D globe with title
    ax = GeoMakie.GlobeAxis(fig[1, 1]; show_axis = false, title = title, titlesize = 24.0f0, titlevisible = true)

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
            markersize = 30,
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
             height = 20,
             ticklabelsize = 24.0,
             label = colorbar_label,
             labelsize = 28.0,
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

    return fig, ax, title, coastlines_plot_3d, cbar
end

# Create vertical profile figure
function create_profile_figure(var, heights, profile, profile_limits, current_height,
                               profile_title, time_selected, bg_color)
    # 50% bigger: 400*1.5 = 600, 350*1.5 = 525
    fig_profile = Figure(size = (600, 525), backgroundcolor = bg_color, figure_padding = 0)
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
function create_timeseries_figure(var, dates_array, timeseries, timeseries_title, time_selected, bg_color)
    # 50% bigger: 400*1.5 = 600, 350*1.5 = 525
    fig_timeseries = Figure(size = (600, 525), backgroundcolor = bg_color, figure_padding = 0)
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

# Create combined figure with both 2D and 3D using Makie.Box for visibility toggling
function create_combined_figure_with_boxes(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color, globe_3d)
    # Create a single figure
    fig = Figure(size = (3200, 1800), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")
    
    # Create Box for 2D content at position [1,1]
    box_2d = Box(fig[1, 1], tellwidth=true, tellheight=true)
    box_2d.visible = !globe_3d[]  # Initially visible if not in 3D mode
    
    # Create 2D axis inside the box
    ax_2d = GeoAxis(box_2d[1, 1], title = title, titlesize = 24.0f0, dest = "+proj=eqc")
    hidedecorations!(ax_2d)
    deactivate_interaction!(ax_2d, :scrollzoom)
    
    # 2D Surface plot
    p_2d = surface!(ax_2d, lon, lat, var_sliced,
                    colorrange = limits,
                    lowclip = (:black, 0.8),
                    highclip = (:yellow, 0.9),
                    shading = NoShading,
                    colormap = :thermal,
                    transparency = true,
                    alpha = 0.9)
    
    coastlines_2d = lines!(ax_2d, GeoMakie.coastlines(), color = :black)
    scatter!(ax_2d, lon_profile, lat_profile,
            color = (:red, 0.7),
            markersize = 30,
            marker = :circle)
    
    # Create Box for 3D content at the same position [1,1]
    box_3d = Box(fig[1, 1], tellwidth=true, tellheight=true)
    box_3d.visible = globe_3d[]  # Initially visible if in 3D mode
    
    # Create 3D axis inside the box
    ax_3d = GeoMakie.GlobeAxis(box_3d[1, 1]; show_axis = false, title = title, titlesize = 24.0f0, titlevisible = true)
    
    # Load Earth image for 3D globe background
    earth_img = FileIO.load(download("https://upload.wikimedia.org/wikipedia/commons/5/56/Blue_Marble_Next_Generation_%2B_topography_%2B_bathymetry.jpg"))
    
    surface!(ax_3d,
             -180..180, -90..90,
             zeros(axes(rotr90(earth_img)));
             shading = NoShading,
             color = rotr90(earth_img),
             backlight = 1.5f0)
    
    # 3D Surface plot
    p_3d = surface!(ax_3d, lon, lat, var_sliced,
                    colorrange = limits,
                    lowclip = (:black, 0.8),
                    highclip = (:yellow, 0.9),
                    shading = NoShading,
                    colormap = :thermal,
                    transparency = true,
                    alpha = 0.9,
                    zlevel = 20_000)
    
    coastlines_3d = lines!(ax_3d, GeoMakie.coastlines(), color = :black)
    scatter!(ax_3d, lon_profile, lat_profile,
            color = (:red, 0.7),
            markersize = 30,
            marker = :circle,
            zlevel = 25_000)
    
    # Create colorbar label
    colorbar_label = Observable(string(
        ClimaAnalysis.short_name(var[]),
        " [",
        ClimaAnalysis.units(var[]),
        "]"
    ))
    
    # Colorbar (shared between both views)
    cbar = Colorbar(
             fig[1, 1],
             p_2d,  # Use 2D plot for colorbar reference
             vertical = false,
             colorrange = limits,
             width = Relative(0.25),
             height = 20,
             ticklabelsize = 24.0,
             label = colorbar_label,
             labelsize = 28.0,
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
    
    # Toggle box visibility based on globe_3d observable
    on(globe_3d) do is_3d
        box_2d.visible = !is_3d
        box_3d.visible = is_3d
    end
    
    return fig, box_2d, box_3d, ax_2d, ax_3d, title, coastlines_2d, coastlines_3d, cbar
end
