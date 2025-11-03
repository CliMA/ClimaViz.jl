export makeapp

function makeapp(path_to_eki_file)

    loaded_data = load_and_process_data(path_to_eki_file)

    app = App(title="CliCal v0.3.0") do
        # Initialize figure
        fig = Figure(size = (2500, 1800), fontsize = 22)

        # Setup default axes
        ax_y = GM.GeoAxis(
                          fig[1, 1];
                          dest = "+proj=wintri",
                          title = "Era5 data (y)",
                         )
        #    lines!(ax_y, GM.coastlines())

        ax_g = GM.GeoAxis(
                          fig[1, 2];
                          dest = "+proj=wintri",
                          title = "ClimaLand (g)",
                         )
        #    lines!(ax_g, GM.coastlines())

        ax_anomalies = GM.GeoAxis(
                                  fig[2, 2];
                                  dest = "+proj=wintri",
                                  title = "Anomalies: ClimaLand (g) - Era5 (y)",
                                 )
        #    lines!(ax_anomalies, GM.coastlines())
        ax_gamma = GM.GeoAxis(
                              fig[3, 2];
                              dest = "+proj=wintri",
                              title = "Noise variance (Γ)",
                             )

        ax_sm = Axis(fig[2, 1],
                     title = "Seasonal means",
                     limits = (0.99, 4.01, 0, 400),
                     ylabel = "Value (W m⁻²)",
                     xticks = (1:4, ["DJF", "MAM", "JJA", "SON"]),
                     xlabel = "Season",
                    )

        ax_gy = Axis(fig[3, 1],
                     title = "g vs y",
                     ylabel = "y (Era5, W m⁻²)",
                     xlabel = "g (ClimaLand, W m⁻²)",
                    )

        variable_list_vec = loaded_data["variable_list"]  # Default
        menu_var = Dropdown(variable_list_vec)
        menu_iter = Dropdown(1:loaded_data["n_iterations"])
        menu_m = Dropdown(1:loaded_data["n_ensembles"])
        menu_season = Dropdown(["DJF", "MAM", "JJA", "SON"])

        year_x = @lift(2008+$(menu_iter.value))
        title_fig = @lift("$($(menu_season.value)) $($(menu_var.value)), iteration $($(menu_iter.value)), ensemble $($(menu_m.value)), year $($(year_x))")
        Label(fig[0, :], title_fig, fontsize=30, tellwidth = false)


        # Update display
        maps = update_fig(menu_var, menu_iter, menu_m, menu_season, fig, ax_y, ax_g, ax_gamma, ax_anomalies, ax_sm, ax_gy, loaded_data["seasonal_g_data"], loaded_data["seasonal_y_data"], loaded_data["seasonal_gamma_data"], loaded_data["lons"], loaded_data["lats"])

        return layout(menu_var, menu_iter, menu_m, menu_season, loaded_data, maps)
    end
end
