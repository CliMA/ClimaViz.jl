export makeapp

function makeapp(path_to_eki_file)

    loaded_data = load_and_process_data(path_to_eki_file)

    app = App(title="CliCal v0.3.0") do
        # Initialize figure for 2D view
        fig_2d = Figure(size = (2500, 1800), fontsize = 22)

        # Setup 2D axes
        ax_y_2d = GM.GeoAxis(
                          fig_2d[1, 1];
                          dest = "+proj=wintri",
                          title = "Era5 data (y)",
                         )

        ax_g_2d = GM.GeoAxis(
                          fig_2d[1, 2];
                          dest = "+proj=wintri",
                          title = "ClimaLand (g)",
                         )

        ax_anomalies_2d = GM.GeoAxis(
                                  fig_2d[2, 2];
                                  dest = "+proj=wintri",
                                  title = "Anomalies: ClimaLand (g) - Era5 (y)",
                                 )
        
        ax_gamma_2d = GM.GeoAxis(
                              fig_2d[3, 2];
                              dest = "+proj=wintri",
                              title = "Noise variance (Γ)",
                             )

        ax_sm_2d = Axis(fig_2d[2, 1],
                     title = "Seasonal means",
                     limits = (0.99, 4.01, 0, 400),
                     ylabel = "Value (W m⁻²)",
                     xticks = (1:4, ["DJF", "MAM", "JJA", "SON"]),
                     xlabel = "Season",
                    )

        ax_gy_2d = Axis(fig_2d[3, 1],
                     title = "g vs y",
                     ylabel = "y (Era5, W m⁻²)",
                     xlabel = "g (ClimaLand, W m⁻²)",
                    )

        # Initialize figure for 3D view
        fig_3d = Figure(size = (2500, 1800), fontsize = 22)

        # Setup 3D globe axes
        ax_y_3d = GM.GlobeAxis(fig_3d[1, 1]; show_axis = false, title = "Era5 data (y)")
        ax_g_3d = GM.GlobeAxis(fig_3d[1, 2]; show_axis = false, title = "ClimaLand (g)")
        ax_anomalies_3d = GM.GlobeAxis(fig_3d[2, 2]; show_axis = false, title = "Anomalies: ClimaLand (g) - Era5 (y)")
        ax_gamma_3d = GM.GlobeAxis(fig_3d[3, 2]; show_axis = false, title = "Noise variance (Γ)")

        ax_sm_3d = Axis(fig_3d[2, 1],
                     title = "Seasonal means",
                     limits = (0.99, 4.01, 0, 400),
                     ylabel = "Value (W m⁻²)",
                     xticks = (1:4, ["DJF", "MAM", "JJA", "SON"]),
                     xlabel = "Season",
                    )

        ax_gy_3d = Axis(fig_3d[3, 1],
                     title = "g vs y",
                     ylabel = "y (Era5, W m⁻²)",
                     xlabel = "g (ClimaLand, W m⁻²)",
                    )

        variable_list_vec = loaded_data["variable_list"]  # Default
        menu_var = Dropdown(variable_list_vec)
        menu_iter = Dropdown(1:loaded_data["n_iterations"])
        menu_m = Dropdown(1:loaded_data["n_ensembles"])
        menu_season = Dropdown(["DJF", "MAM", "JJA", "SON"])
        checkbox_3d = Checkbox(false)

        year_x = @lift(2008+$(menu_iter.value))
        title_fig = @lift("$($(menu_season.value)) $($(menu_var.value)), iteration $($(menu_iter.value)), ensemble $($(menu_m.value)), year $($(year_x))")
        Label(fig_2d[0, :], title_fig, fontsize=30, tellwidth = false)
        Label(fig_3d[0, :], title_fig, fontsize=30, tellwidth = false)

        # Update display for both 2D and 3D
        maps_2d = update_fig(menu_var, menu_iter, menu_m, menu_season, fig_2d, ax_y_2d, ax_g_2d, ax_gamma_2d, ax_anomalies_2d, ax_sm_2d, ax_gy_2d, loaded_data["seasonal_g_data"], loaded_data["seasonal_y_data"], loaded_data["seasonal_gamma_data"], loaded_data["lons"], loaded_data["lats"])
        maps_3d = update_fig(menu_var, menu_iter, menu_m, menu_season, fig_3d, ax_y_3d, ax_g_3d, ax_gamma_3d, ax_anomalies_3d, ax_sm_3d, ax_gy_3d, loaded_data["seasonal_g_data"], loaded_data["seasonal_y_data"], loaded_data["seasonal_gamma_data"], loaded_data["lons"], loaded_data["lats"])

        return layout(menu_var, menu_iter, menu_m, menu_season, checkbox_3d, loaded_data, maps_2d, maps_3d)
    end
end
