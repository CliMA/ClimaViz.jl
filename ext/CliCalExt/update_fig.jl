export update_fig

function update_fig(menu_var, menu_iter, menu_m, menu_season, fig, ax_y, ax_g, ax_gamma, ax_anomalies, ax_sm, ax_gy, seasonal_g_data, seasonal_y_data, seasonal_gamma_data, lons, lats)

    m_v = menu_var.value
    m_i = menu_iter.value
    m_m = menu_m.value
    m_s = menu_season.value

    g = @lift(seasonal_g_data[$m_i][$m_m][$m_v][$m_s])
    y = @lift(seasonal_y_data[$m_i][$m_v][$m_s])
    Γ = @lift(seasonal_gamma_data[$m_v][$m_s])

    anomalies = @lift($g .- $y)
    rmse_y_g = @lift(string("RMSE = ", round(RMSE($g, $y), digits=1), " W m⁻²"))

    min_p = @lift(minimum(vcat($g, $y)))
    max_p = @lift(maximum(vcat($g, $y)))
    limits_p = @lift(($min_p, $max_p))

    min_ano = @lift(minimum($anomalies))
    max_ano = @lift(maximum($anomalies))
    limits_ano = (-30, 30)

    p_g = surface!(ax_g, lons, lats, g, colorrange = limits_p, shading = NoShading)
    p_y = surface!(ax_y, lons, lats, y, colorrange = limits_p, shading = NoShading)
    p_gamma = surface!(ax_gamma, lons, lats, Γ, colorrange = (0,50), shading = NoShading)
    p_ano = surface!(ax_anomalies, lons, lats, anomalies, colorrange = limits_ano, colormap = cgrad(:bluesreds, categorical = false), highclip = :red, lowclip = :blue, shading = NoShading)

    cl = @lift($m_v * " (W m⁻²)")
    cb = Colorbar(fig[1, 3], colorrange = limits_p, label = cl, height = 300, tellheight = false)

    cl_ano = @lift($m_v * " (W m⁻²)")
    cb_ano = Colorbar(fig[2, 3], colorrange = limits_ano, label = cl_ano, height = 300, tellheight = false, colormap = cgrad(:bluesreds, categorical = false), highclip = :red, lowclip = :blue)

    cb_gamma = Colorbar(fig[3, 3], colorrange = (0, 50), label = cl, height = 300, tellheight = false)

    y_seasonal_means = @lift([cosine_weighted_global_mean(seasonal_y_data[$m_i][$m_v][season], lats) for season in ["DJF", "MAM", "JJA", "SON"]])
    y_seasonal_means_1 = @lift([cosine_weighted_global_mean(seasonal_y_data[1][$m_v][season], lats) for season in ["DJF", "MAM", "JJA", "SON"]])

    g_seasonal_means = @lift([cosine_weighted_global_mean(seasonal_g_data[$m_i][$m_m][$m_v][season], lats) for season in ["DJF", "MAM", "JJA", "SON"]])
    g_seasonal_means_1 = @lift([cosine_weighted_global_mean(seasonal_g_data[1][1][$m_v][season], lats) for season in ["DJF", "MAM", "JJA", "SON"]])

    min_sm = 0 # @lift(minimum(vcat($y_seasonal_means, $g_seasonal_means)))
    max_sm = @lift(maximum(vcat($y_seasonal_means, $g_seasonal_means)) + 10)
    limits_sm = @lift(($min_sm, $max_sm))

    line_y_1 = lines!(ax_sm, 1:4, y_seasonal_means_1, color= (:green, 0.3), linestyle = :dash)
    lines_g_1 = lines!(ax_sm, 1:4, g_seasonal_means_1, color= (:black, 0.3), linestyle = :dash)
    lines_g = lines!(ax_sm, 1:4, g_seasonal_means, color= :black)
    lines_y = lines!(ax_sm, 1:4, y_seasonal_means, color= :green)
    text!(ax_sm, 0.1, 0.1, text = rmse_y_g, align = (:left, :top), space = :relative)

    scatter_gy = scatter!(ax_gy, g, y, color= (:black, 0.2))
    max_y = @lift([0, maximum($y)])
    one_to_one_line = lines!(ax_gy, max_y, max_y, color = :black)
    @lift(ylims!(ax_gy, minimum($y), maximum($y)))
    @lift(xlims!(ax_gy, minimum($y), maximum($g)))

    seasons = ["DJF", "MAM", "JJA", "SON"]
    current_s = @lift(findfirst(==($m_s), seasons))
    current_s_array = @lift([$current_s, $current_s])
    lines!(ax_sm, current_s_array, [0, 1000], color= :red, linewidth = 3)
    @lift(ylims!(ax_sm, $min_sm, $max_sm))
    axislegend(ax_sm, [lines_y, lines_g], ["era5", "ClimaLand"])

    fig
    return fig
end
