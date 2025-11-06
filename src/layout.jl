export layout

function layout(var_menu, reduction_menu, period_menu, time_slider, height_slider, play_button, speed_slider,
                fig, fig_3d, fig_profile, fig_timeseries, show_height, profile_lines, profile_hlines,
                time_value_label, height_value_label, speed_value_label, dark_mode_checkbox, globe_3d_checkbox, globe_3d, dark_mode,
                transparency_gradient_checkbox, transparency_direction_menu, transparency_color_menu)
    label_style = Bonito.Styles(
        "font-size" => "0.9rem",
        "font-weight" => "600",
        "margin" => "0",
        "display" => "flex",
        "align-items" => "center",
        "gap" => "6px"
    )
    header_style = Bonito.Styles(
        "font-size" => "1.3rem",
        "text-align" => "center",
        "font-weight" => "bold",
        "margin-bottom" => "0.5rem"
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
        "padding" => "4px 0"
    )
    dark_mode_label = Bonito.DOM.span("Dark Mode: "; style = label_style)
    dark_mode_row = Bonito.DOM.div(
        dark_mode_label,
        dark_mode_checkbox;
        style = checkbox_row_style
    )

    # 3D globe row with improved layout
    globe_3d_label = Bonito.DOM.span("3D Globe: "; style = label_style)
    globe_3d_row = Bonito.DOM.div(
        globe_3d_label,
        globe_3d_checkbox;
        style = checkbox_row_style
    )

    # Transparency gradient row with improved layout
    transparency_gradient_label = Bonito.DOM.span("Transparency Gradient: "; style = label_style)
    transparency_gradient_row = Bonito.DOM.div(
        transparency_gradient_label,
        transparency_gradient_checkbox;
        style = checkbox_row_style
    )

    # Menu card with improved styling and two-column layout
    # Make it grey in white mode for better visual separation
    menu_card_style = Bonito.Styles(
        "padding" => "12px",
        "border-radius" => "8px",
        "background-color" => "#f5f5f5"  # Light grey in white mode
    )

    # Left column: dark mode, 3D globe, variable, reduction, period
    left_column = Bonito.Col(
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
        );
        height = "auto"
    )

    # Right column: transparency gradient, direction, color, time, height, play
    right_column = Bonito.Col(
        transparency_gradient_row,
        Bonito.Row(
            Bonito.DOM.h1("Direction: "; style = label_style),
            transparency_direction_menu;
        ),
        Bonito.Row(
            Bonito.DOM.h1("Color: "; style = label_style),
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
        Bonito.Grid(
            left_column,
            right_column;
            columns = "1fr 1fr",
            gap = "10px"
        );
        shadow_size = "0",
        style = menu_card_style,
        class = "menu-card"
    )

    # Timeseries card with centering
    card_center_style = Bonito.Styles(
        "display" => "flex",
        "justify-content" => "center",
        "width" => "100%"
    )
    timeseries_card = Bonito.DOM.div(
        Bonito.Card(fig_timeseries; shadow_size = "0");
        style = card_center_style
    )

    # Profile card - now always shows the profile figure
    # When there's no height dimension, the Makie.Box inside covers it
    profile_card = Bonito.DOM.div(
        Bonito.Card(fig_profile; shadow_size = "0");
        style = card_center_style
    )

    # Left sidebar with all controls stacked vertically
    left_sidebar = Bonito.Col(
        menu_card,
        timeseries_card,
        profile_card;
        height = "100vh"
    )

    # Map cards - Alternative approach: simpler visibility toggle
    # Keep both figures in layout, toggle which one is displayed
    # This approach uses conditional rendering based on observable
    map_card = Observable(globe_3d[] ? Bonito.Card(fig_3d; shadow_size = "0") : Bonito.Card(fig; shadow_size = "0"))
    
    on(globe_3d) do is_3d
        map_card[] = is_3d ? Bonito.Card(fig_3d; shadow_size = "0") : Bonito.Card(fig; shadow_size = "0")
    end

    # Main layout: sidebar on left, map on right with minimal gap
    Bonito.Grid(
        left_sidebar,
        map_card;
        columns = "auto 1fr",
        gap = "5px"
    )
end
