export create_main_figure, create_bias_figure, create_profile_figure, create_timeseries_figure

# Main 2D map (equirectangular surface plot with coastlines and location marker)
function create_main_figure(var, var_sliced, limits, lon, lat, lon_profile, lat_profile, bg_color, earth_img)
    fig = Figure(size = (1075, 600), backgroundcolor = bg_color, figure_padding = 0)
    title = Observable("title")

    ax = GeoAxis(fig[1, 1], title = title, titlesize = 16.0f0, dest = "+proj=eqc")
    hidedecorations!(ax)
    deactivate_interaction!(ax, :scrollzoom)

    earth_surface = surface!(
        ax, -180..180, -90..90, zeros(axes(rotr90(earth_img)));
        shading = NoShading, color = rotr90(earth_img), visible = false,
    )

    surface_plot_colormap = surface!(
        ax, lon, lat, var_sliced;
        colorrange = limits,
        lowclip = (:black, 0.8),
        highclip = (:yellow, 0.9),
        shading = NoShading,
        colormap = :thermal,
        transparency = true,
        alpha = 0.9,
        visible = true,
    )

    coastlines_plot = lines!(ax, GeoMakie.coastlines(), color = :black)

    scatter!(ax, lon_profile, lat_profile;
        color = (:red, 0.7), markersize = 20, marker = :circle,
    )

    colorbar_label = Observable(string(
        ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]",
    ))

    cbar = Colorbar(
        fig[1, 1], surface_plot_colormap;
        vertical = false, colorrange = limits,
        width = Relative(0.25), height = 13,
        ticklabelsize = 16.0, label = colorbar_label, labelsize = 19.0,
        halign = :right, valign = :bottom,
        tellheight = false, tellwidth = false,
    )

    on(var) do v
        colorbar_label[] = string(
            ClimaAnalysis.short_name(v), " [", ClimaAnalysis.units(v), "]",
        )
    end

    return fig, ax, title, coastlines_plot, cbar, surface_plot_colormap, earth_surface, colorbar_label
end

# Bias map (sim - obs) with diverging colormap, symmetric around 0.
function create_bias_figure(var, bias_sliced, bias_limits, bias_title, lon, lat, lon_profile, lat_profile, bg_color)
    fig = Figure(size = (1075, 540), backgroundcolor = bg_color, figure_padding = 0)

    ax = GeoAxis(fig[1, 1], title = bias_title, titlesize = 16.0f0, dest = "+proj=eqc")
    hidedecorations!(ax)
    deactivate_interaction!(ax, :scrollzoom)

    surface_plot_bias = surface!(
        ax, lon, lat, bias_sliced;
        colorrange = bias_limits,
        shading = NoShading,
        colormap = :RdBu,
        nan_color = (:gray, 0.0),
        transparency = true,
        alpha = 0.95,
        visible = true,
    )

    coastlines_plot = lines!(ax, GeoMakie.coastlines(), color = :black)

    scatter!(ax, lon_profile, lat_profile;
        color = (:red, 0.7), markersize = 20, marker = :circle,
    )

    colorbar_label = Observable(string(
        "sim − obs [", ClimaAnalysis.units(var[]), "]",
    ))

    cbar = Colorbar(
        fig[1, 1], surface_plot_bias;
        vertical = false, colorrange = bias_limits,
        width = Relative(0.3), height = 13,
        ticklabelsize = 16.0, label = colorbar_label, labelsize = 18.0,
        halign = :right, valign = :bottom,
        tellheight = false, tellwidth = false,
    )

    on(var) do v
        colorbar_label[] = string("sim − obs [", ClimaAnalysis.units(v), "]")
    end

    return fig, ax, coastlines_plot, cbar, surface_plot_bias, colorbar_label
end

# Vertical profile figure
function create_profile_figure(
    var, heights, profile, profile_limits, current_height,
    profile_title, time_selected, bg_color, show_height,
)
    fig_profile = Figure(size = (800, 540), backgroundcolor = bg_color, figure_padding = 0)
    profile_xlabel = Observable(string(
        ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]",
    ))

    ax_profile = Axis(
        fig_profile[1, 1];
        xlabel = profile_xlabel, ylabel = "Height [m]",
        title = profile_title,
        xlabelsize = 16, ylabelsize = 16,
        xticklabelsize = 14, yticklabelsize = 14,
        titlesize = 18,
    )
    deactivate_interaction!(ax_profile, :scrollzoom)

    heights_obs = Observable(length(heights) > 0 ? heights : [0.0])

    profile_lines = lines!(ax_profile, profile, heights_obs; color = :black, linewidth = 3)
    xlims!(ax_profile, profile_limits[])
    profile_hlines = hlines!(ax_profile, current_height; color = (:grey, 0.7), linewidth = 2)

    profile_box = Box(
        fig_profile[1, 1];
        color = bg_color, strokevisible = false,
        visible = !show_height[],
        tellwidth = false, tellheight = false,
    )

    return fig_profile, ax_profile, profile_xlabel, profile_lines, profile_hlines, heights_obs, profile_box
end

# Time series figure (with optional observation overlay)
function create_timeseries_figure(
    var, dates_array, timeseries, timeseries_obs, show_obs_line,
    timeseries_title, time_selected, bg_color,
)
    fig_timeseries = Figure(size = (800, 600), backgroundcolor = bg_color, figure_padding = 0)
    timeseries_ylabel = Observable(string(
        ClimaAnalysis.short_name(var[]), " [", ClimaAnalysis.units(var[]), "]",
    ))

    ax_timeseries = Axis(
        fig_timeseries[1, 1];
        xlabel = "", ylabel = timeseries_ylabel,
        title = timeseries_title,
        xlabelsize = 16, ylabelsize = 16,
        xticklabelsize = 14, yticklabelsize = 14,
        titlesize = 18,
        xticklabelrotation = π / 4,
    )
    deactivate_interaction!(ax_timeseries, :scrollzoom)

    time_indices = 1:length(dates_array)
    timeseries_lines = lines!(
        ax_timeseries, time_indices, timeseries;
        color = :black, linewidth = 2, label = "model",
    )
    timeseries_obs_lines = lines!(
        ax_timeseries, time_indices, timeseries_obs;
        color = :orange, linewidth = 2, label = "obs", visible = show_obs_line,
    )

    current_time_index = Observable(time_selected[])
    vlines!(ax_timeseries, current_time_index; color = (:grey, 0.7), linewidth = 2)

    axislegend(
        ax_timeseries;
        position = :rt, framevisible = false, labelsize = 12, padding = (4, 4, 2, 2),
    )

    n_ticks = min(10, length(dates_array))
    tick_indices = round.(Int, range(1, length(dates_array), length = n_ticks))
    tick_labels = [Dates.format(dates_array[i], "u yyyy") for i in tick_indices]
    ax_timeseries.xticks = (tick_indices, tick_labels)

    autolimits!(ax_timeseries)

    return fig_timeseries, ax_timeseries, timeseries_ylabel, current_time_index, n_ticks,
        timeseries_lines, timeseries_obs_lines
end
