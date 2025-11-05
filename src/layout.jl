export layout

function layout(var_menu, reduction_menu, period_menu, time_slider, height_slider, play_button, speed_slider,
                fig_map, fig_profile, fig_timeseries, show_height, profile_lines, profile_hlines,
                time_value_label, height_value_label, speed_value_label, dark_mode_checkbox, globe_3d_checkbox, globe_3d, dark_mode)
    label_style = Bonito.Styles("font-size" => "1.2rem")
    header_style = Bonito.Styles("font-size" => "2rem", "text-align" => "center")

    # Create height row with value display
    height_label = Bonito.DOM.h1("Height: "; style = label_style)
    height_row = Bonito.Row(
        height_label,
        height_slider,
        height_value_label;
    )

    # Animation control row
    animation_row = Bonito.Row(
        play_button,
        Bonito.DOM.h1("Speed: "; style = label_style),
        speed_slider,
        speed_value_label;
    )

    # Dark mode row
    dark_mode_row = Bonito.Row(
        Bonito.DOM.h1("Dark Mode: "; style = label_style),
        dark_mode_checkbox;
    )

    # 3D globe row
    globe_3d_row = Bonito.Row(
        Bonito.DOM.h1("3D Globe: "; style = label_style),
        globe_3d_checkbox;
    )

    # Menu card (no overlay, in sidebar)
    menu_card = Bonito.Card(
        Bonito.Col(
            Bonito.DOM.h1("Menu"; style = header_style),
            dark_mode_row,
            globe_3d_row,
            Bonito.Row(
                Bonito.DOM.h1("Variable: "; style = label_style),
                var_menu;
            ),
            Bonito.Row(
                Bonito.DOM.h1("Reduction: "; style = label_style),
                reduction_menu;
            ),
            Bonito.Row(
                Bonito.DOM.h1("Period: "; style = label_style),
                period_menu;
            ),
            Bonito.Row(
                Bonito.DOM.h1("Time: "; style = label_style),
                time_slider,
                time_value_label;
            ),
            height_row,
            animation_row;
            height = "auto"
        );
        shadow_size = "0"
    )

    # Timeseries card
    timeseries_card = Bonito.Card(fig_timeseries; shadow_size = "0")

    # Profile card - now using Box.visible internally, no @lift needed
    profile_card = Bonito.Card(fig_profile; shadow_size = "0")

    # Left sidebar with all controls stacked vertically
    left_sidebar = Bonito.Col(
        menu_card,
        timeseries_card,
        profile_card;
        height = "100vh"
    )

    # Map card - now using Box.visible internally, no @lift needed
    map_card = Bonito.Card(fig_map; shadow_size = "0")

    # Main layout: sidebar on left, map on right with minimal gap
    Bonito.Grid(
        left_sidebar,
        map_card;
        columns = "auto 1fr",
        gap = "5px"
    )
end
