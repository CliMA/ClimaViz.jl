export create_main_figure, create_main_figure_3d, create_profile_figure, create_timeseries_figure

# Create main map figure with surface plot
function create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color, earth_img)
    # Reduced size (half of original) so 2D and 3D can stack and both fit on screen
    fig = Figure(size = (1075, 600), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")

    # Equirectangular projection with title
    ax = GeoAxis(fig[1, 1], title = title, titlesize = 16.0f0, dest = "+proj=eqc")

    # Hide axis decorations for cleaner look
    hidedecorations!(ax)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax, :scrollzoom)

    # Add Earth image as base surface (initially hidden)
    earth_surface = surface!(ax,
             -180..180, -90..90,
             zeros(axes(rotr90(earth_img)));
             shading = NoShading,
             color = rotr90(earth_img),
             visible = false)  # Hidden by default

    # Create observable for RGBA colors
    rgba_colors = Observable(RGBAf.(1.0, 1.0, 1.0, ones(size(var_sliced[]))))

    # Surface plot with colormap (2D always uses colormap mode)
    p_colormap = surface!(ax, lon, lat, var_sliced,
                 colorrange = limits,
                 lowclip = (:black, 0.8),
                 highclip = (:yellow, 0.9),
                 shading = NoShading,
                 colormap = :thermal,
                 transparency = true,
                 alpha = 0.9,
                 visible = true)

    # Surface plot with RGBA colors (2D never uses this)
    p_rgba = surface!(ax, lon, lat, var_sliced,
                 color = rgba_colors,
                 shading = NoShading,
                 transparency = true,
                 visible = false)

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
             p_colormap,
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

    return fig, ax, title, coastlines_plot, cbar, p_colormap, p_rgba, rgba_colors, earth_surface, colorbar_label
end

# Create main 3D globe figure
function create_main_figure_3d(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color, earth_img)
    # Reduced height by 10% from 600 to 540 for better layout fit
    # Reduced pixel density (px_per_unit=0.5) for faster rendering
    fig = Figure(size = (1075, 540), backgroundcolor = bg_color, figure_padding = 0, px_per_unit = 0.5)
    title = Observable("title")

    # Use GlobeAxis for 3D globe (title now shown in separate card)
    ax = GeoMakie.GlobeAxis(fig[1, 1]; show_axis = false)

    # Add Earth image as base surface at z=0 (3D always shows Earth in transparent gradient mode)
    earth_surface = surface!(ax,
             -180..180, -90..90,
             zeros(axes(rotr90(earth_img)));
             shading = NoShading,
             color = rotr90(earth_img),
             backlight = 1.5f0,
             visible = true
            )

    # Create observable for RGBA colors (3D)
    rgba_colors_3d = Observable(RGBAf.(1.0, 1.0, 1.0, ones(size(var_sliced[]))))

    # Surface plot on globe with colormap (3D never uses this)
    p_colormap = surface!(ax, lon, lat, var_sliced,
                 colorrange = limits,
                 lowclip = (:black, 0.8),
                 highclip = (:yellow, 0.9),
                 shading = NoShading,
                 colormap = :thermal,
                 transparency = true,
                 alpha = 0.9,
                 zlevel = 20_000,
                 visible = false)

    # Surface plot on globe with RGBA colors (3D always uses transparent gradient)
    p_rgba = surface!(ax, lon, lat, var_sliced,
                 color = rgba_colors_3d,
                 shading = NoShading,
                 transparency = true,
                 zlevel = 20_000,
                 visible = true)

    # Add coastlines for 3D globe - hidden in transparent gradient mode
    coastlines_plot_3d = lines!(ax, GeoMakie.coastlines(), color = :black, visible = false)

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
             p_colormap,
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

    # Create starfield for space background (visible only in dark mode)
    # Generate random star positions in 3D space around the globe
    n_stars_background = 15000  # Base stars
    n_stars_milkyway = 25000    # Extra stars for Milky Way band
    Random.seed!(42)  # For reproducibility

    # Background stars - uniformly distributed
    star_radius = 1e8  # Far from Earth
    star_theta_bg = 2π .* rand(n_stars_background)
    star_phi_bg = acos.(2 .* rand(n_stars_background) .- 1)

    # Convert to Cartesian coordinates
    star_x_bg = star_radius .* sin.(star_phi_bg) .* cos.(star_theta_bg)
    star_y_bg = star_radius .* sin.(star_phi_bg) .* sin.(star_theta_bg)
    star_z_bg = star_radius .* cos.(star_phi_bg)

    # Milky Way band - concentrated along a great circle
    # Create a tilted band (like viewing the Milky Way from Earth)
    star_theta_mw = 2π .* rand(n_stars_milkyway)
    # Concentrate stars near the equatorial plane (narrow gaussian distribution)
    star_phi_deviation = 0.15 .* randn(n_stars_milkyway)  # Gaussian around 0
    star_phi_mw = π/2 .+ star_phi_deviation  # Concentrated near equator with tilt

    # Convert Milky Way stars to Cartesian
    star_x_mw = star_radius .* sin.(star_phi_mw) .* cos.(star_theta_mw)
    star_y_mw = star_radius .* sin.(star_phi_mw) .* sin.(star_theta_mw)
    star_z_mw = star_radius .* cos.(star_phi_mw)

    # Apply rotation to tilt the Milky Way band (30 degrees)
    tilt_angle = π/6  # 30 degrees
    star_x_mw_rotated = star_x_mw .* cos(tilt_angle) .- star_z_mw .* sin(tilt_angle)
    star_z_mw_rotated = star_x_mw .* sin(tilt_angle) .+ star_z_mw .* cos(tilt_angle)

    # Combine all stars
    star_x = vcat(star_x_bg, star_x_mw_rotated)
    star_y = vcat(star_y_bg, star_y_mw)
    star_z = vcat(star_z_bg, star_z_mw_rotated)
    n_stars = n_stars_background + n_stars_milkyway

    # Create different star types for variety
    # Some very bright (pure white), some dimmer
    # Milky Way stars are slightly dimmer on average
    star_brightness = vcat(rand(n_stars_background), 0.7 .* rand(n_stars_milkyway))
    star_colors = [RGBAf(1, 1, 1, b > 0.85 ? 1.0 : 0.3 + 0.5*b) for b in star_brightness]

    # Slightly bigger stars
    star_sizes = 1.0 .+ 2.0 .* rand(n_stars)

    # Add main stars (small, no borders)
    stars_main = scatter!(ax.scene, star_x, star_y, star_z,
                    color = star_colors,
                    markersize = star_sizes,
                    strokewidth = 0,  # No borders
                    space = :data,
                    visible = false)

    # Add halo effect for bright stars only
    bright_indices = findall(b -> b > 0.85, star_brightness)
    halo_colors = [RGBAf(1, 1, 1, 0.15) for _ in bright_indices]
    halo_sizes = star_sizes[bright_indices] .* 3  # 3x larger for halo

    stars_halo = scatter!(ax.scene, star_x[bright_indices], star_y[bright_indices], star_z[bright_indices],
                    color = halo_colors,
                    markersize = halo_sizes,
                    strokewidth = 0,
                    space = :data,
                    visible = false)

    # Return both star layers as a tuple
    stars = (stars_main, stars_halo)

    return fig, ax, title, coastlines_plot_3d, cbar, p_colormap, p_rgba, rgba_colors_3d, earth_surface, colorbar_label, stars
end

# Create vertical profile figure
function create_profile_figure(var, heights, profile, profile_limits, current_height,
                               profile_title, time_selected, bg_color, show_height, profile_global_avg)
    # Width for right column in 3-column layout
    fig_profile = Figure(size = (800, 540), backgroundcolor = bg_color, figure_padding = 0)
    profile_xlabel = Observable(string(ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]"))

    ax_profile = Axis(fig_profile[1, 1],
                     xlabel = profile_xlabel, ylabel = "Height [m]",
                     title = profile_title,
                     xlabelsize = 16, ylabelsize = 16,
                     xticklabelsize = 14, yticklabelsize = 14,
                     titlesize = 18)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax_profile, :scrollzoom)

    # Create observable for heights so it can be updated
    heights_obs = Observable(length(heights) > 0 ? heights : [0.0])

    # Create profile plot elements with separate x,y observables - simple and direct
    # No longer need to control visibility of lines - the Box will cover them
    profile_lines = lines!(ax_profile, profile, heights_obs, color = :black, linewidth = 3)
    # Add global average line in dotted grey
    profile_global_avg_lines = lines!(ax_profile, profile_global_avg, heights_obs, color = :grey, linestyle = :dot, linewidth = 2)
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
    return fig_profile, ax_profile, profile_xlabel, profile_lines, profile_hlines, heights_obs, profile_box, profile_global_avg_lines
end

# Create time series figure
function create_timeseries_figure(var, dates_array, timeseries, timeseries_title, time_selected, bg_color, timeseries_global_avg)
    # Width for right column in 3-column layout
    fig_timeseries = Figure(size = (800, 600), backgroundcolor = bg_color, figure_padding = 0)
    timeseries_ylabel = Observable(string(ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]"))

    ax_timeseries = Axis(fig_timeseries[1, 1],
                        xlabel = "", ylabel = timeseries_ylabel,
                        title = timeseries_title,
                        xlabelsize = 16, ylabelsize = 16,
                        xticklabelsize = 14, yticklabelsize = 14,
                        titlesize = 18,
                        xticklabelrotation = π/4)

    # Deactivate zoom via scroll
    deactivate_interaction!(ax_timeseries, :scrollzoom)

    # Use numeric indices for plotting
    time_indices = 1:length(dates_array)
    timeseries_lines = lines!(ax_timeseries, time_indices, timeseries, color = :black, linewidth = 2)
    # Add global average line in dotted grey
    timeseries_global_avg_lines = lines!(ax_timeseries, time_indices, timeseries_global_avg, color = :grey, linestyle = :dot, linewidth = 2)

    # Add vertical line showing current time
    current_time_index = Observable(time_selected[])
    vlines!(ax_timeseries, current_time_index, color = :grey, linestyle = :dash, linewidth = 2)

    # Format x-axis to show dates
    n_ticks = min(10, length(dates_array))
    tick_indices = round.(Int, range(1, length(dates_array), length=n_ticks))
    tick_labels = [Dates.format(dates_array[i], "u yyyy") for i in tick_indices]
    ax_timeseries.xticks = (tick_indices, tick_labels)

    autolimits!(ax_timeseries)

    return fig_timeseries, ax_timeseries, timeseries_ylabel, current_time_index, n_ticks, timeseries_lines, timeseries_global_avg_lines
end
