export layout

function layout(var_menu, reduction_menu, period_menu, time_slider, height_slider, play_button, speed_slider,
                fig, fig_3d, fig_profile, fig_timeseries, show_height, profile_lines, profile_hlines,
                time_value_label, height_value_label, speed_value_label, dark_mode_checkbox, dark_mode,
                transparency_quantiles_slider, quantiles_value_label, transparency_direction_menu, transparency_color_menu)
    label_style = Bonito.Styles(
        "font-size" => "0.9rem",
        "font-weight" => "600",
        "margin" => "0",
        "display" => "flex",
        "align-items" => "center",
        "gap" => "4px",
        "color" => "white"  # Start with white for dark mode default
    )
    header_style = Bonito.Styles(
        "font-size" => "1.1rem",
        "text-align" => "center",
        "font-weight" => "bold",
        "margin-bottom" => "0.3rem"
    )

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

    # Dark mode row with improved layout
    checkbox_row_style = Bonito.Styles(
        "display" => "flex",
        "align-items" => "center",
        "gap" => "8px",
        "padding" => "4px 0",
        "color" => "white"  # Start with white for dark mode default
    )
    dark_mode_label = Bonito.DOM.span("Dark Mode: "; style = label_style)
    dark_mode_row = Bonito.DOM.div(
        dark_mode_label,
        dark_mode_checkbox;
        style = checkbox_row_style
    )

    # 3D transparency controls row (3D always uses transparent gradient mode)
    gradient_threshold_row = Bonito.DOM.div(
        Bonito.DOM.span("3D Gradient Threshold: "; style = label_style),
        transparency_quantiles_slider,
        quantiles_value_label;
        style = checkbox_row_style
    )

    # Menu card with compact styling
    # Start with dark mode colors (since dark mode is default)
    menu_card_style = Bonito.Styles(
        "padding" => "8px",
        "border-radius" => "6px",
        "background-color" => "#1a1a1a"  # Dark grey for dark mode (default)
    )

    # Single column menu (narrower, taller)
    menu_column = Bonito.Col(
        dark_mode_row,
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
        gradient_threshold_row,
        Bonito.Row(
            Bonito.DOM.h1("3D Direction: "; style = label_style),
            transparency_direction_menu;
        ),
        Bonito.Row(
            Bonito.DOM.h1("3D Color: "; style = label_style),
            transparency_color_menu;
        ),
        Bonito.Row(
            Bonito.DOM.h1("Time: "; style = label_style),
            time_slider,
            time_value_label;
        ),
        height_row,
        animation_row;
        height = "auto"
    )

    menu_card = Bonito.Card(
        menu_column;
        shadow_size = "0",
        style = menu_card_style,
        class = "menu-card"
    )

    # Column 1: Menu card only
    menu_column_layout = Bonito.Col(
        menu_card;
        height = "100vh"
    )

    # Column 2: 2D surface (top) and 3D surface (bottom) stacked vertically
    surfaces_column = Bonito.Col(
        Bonito.Card(fig; shadow_size = "0"),
        Bonito.Card(fig_3d; shadow_size = "0");
        height = "100vh"
    )

    # Column 3: Timeseries (top) and Profile (bottom) stacked vertically
    charts_column = Bonito.Col(
        Bonito.Card(fig_timeseries; shadow_size = "0"),
        Bonito.Card(fig_profile; shadow_size = "0");
        height = "100vh"
    )

    # Main layout: 3 columns tightly packed (no flexible spacing)
    Bonito.Grid(
        menu_column_layout,
        surfaces_column,
        charts_column;
        columns = "400px 1100px 800px",
        gap = "5px"
    )
end
