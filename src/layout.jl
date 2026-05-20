export layout

function layout(
    var_menu, reduction_menu, period_menu, aggregation_menu,
    time_slider, height_slider, play_button, speed_slider,
    fig, fig_bias, fig_profile, fig_timeseries,
    show_height, show_bias, metrics,
    time_value_label, height_value_label, speed_value_label,
    dark_mode_checkbox,
)
    label_style = Bonito.Styles(
        "font-size" => "0.9rem", "font-weight" => "600",
        "margin" => "0",
        "display" => "flex", "align-items" => "center", "gap" => "4px",
        "color" => "white",
    )

    height_row = Bonito.Row(
        Bonito.DOM.h1("Height: "; style = label_style),
        height_slider, height_value_label,
    )

    animation_row = Bonito.Row(
        play_button,
        Bonito.DOM.h1("Speed: "; style = label_style),
        speed_slider, speed_value_label,
    )

    checkbox_row_style = Bonito.Styles(
        "display" => "flex", "align-items" => "center",
        "gap" => "8px", "padding" => "4px 0", "color" => "white",
    )
    dark_mode_row = Bonito.DOM.div(
        Bonito.DOM.span("Dark Mode: "; style = label_style),
        dark_mode_checkbox;
        style = checkbox_row_style,
    )

    menu_card_style = Bonito.Styles(
        "padding" => "8px", "border-radius" => "6px",
        "background-color" => "#1a1a1a",
    )

    menu_column = Bonito.Col(
        dark_mode_row,
        Bonito.Row(Bonito.DOM.h1("Variable: "; style = label_style), var_menu),
        Bonito.Row(Bonito.DOM.h1("Reduction: "; style = label_style), reduction_menu),
        Bonito.Row(Bonito.DOM.h1("Period: "; style = label_style), period_menu),
        Bonito.Row(Bonito.DOM.h1("Aggregation: "; style = label_style), aggregation_menu),
        Bonito.Row(Bonito.DOM.h1("Time: "; style = label_style), time_slider, time_value_label),
        height_row,
        animation_row;
        height = "auto",
    )

    menu_card = Bonito.Card(
        menu_column;
        shadow_size = "0",
        style = menu_card_style,
        class = "menu-card",
    )

    menu_column_layout = Bonito.Col(menu_card; height = "100vh")

    surfaces_column = Bonito.Col(
        Bonito.Card(fig; shadow_size = "0"),
        Bonito.Card(fig_bias; shadow_size = "0");
        height = "100vh",
    )

    charts_column = Bonito.Col(
        Bonito.Card(fig_timeseries; shadow_size = "0"),
        Bonito.Card(fig_profile; shadow_size = "0"),
        Bonito.Card(_metrics_card(metrics); shadow_size = "0", class = "metrics-card");
        height = "100vh",
    )

    Bonito.Grid(
        menu_column_layout, surfaces_column, charts_column;
        columns = "400px 1100px 800px",
        gap = "5px",
    )
end

function _metrics_card(metrics)
    header_style = Bonito.Styles(
        "padding" => "6px 8px", "font-weight" => "600",
        "text-align" => "center", "border-bottom" => "1px solid #444",
        "color" => "white",
    )
    cell_style = Bonito.Styles(
        "padding" => "4px 8px", "text-align" => "right",
        "font-variant-numeric" => "tabular-nums",
        "color" => "white",
    )
    label_cell_style = Bonito.Styles(
        "padding" => "4px 8px", "text-align" => "left",
        "font-weight" => "600",
        "color" => "white",
    )

    header_cells = [Bonito.DOM.th(""; style = header_style)]
    for s in METRIC_SCOPES
        push!(header_cells, Bonito.DOM.th(SCOPE_LABELS[s]; style = header_style))
    end
    thead = Bonito.DOM.thead(Bonito.DOM.tr(header_cells...))

    rows = []
    for m in METRIC_ROWS
        cells = [Bonito.DOM.td(METRIC_LABELS[m]; style = label_cell_style)]
        for s in METRIC_SCOPES
            cell_text = map(t -> format_cell(t, m, s), metrics)
            push!(cells, Bonito.DOM.td(cell_text; style = cell_style))
        end
        push!(rows, Bonito.DOM.tr(cells...))
    end
    units_text = map(t -> isempty(t.units) ? "" : string("Units: ", t.units), metrics)
    units_caption = Bonito.DOM.div(units_text;
        style = Bonito.Styles(
            "font-size" => "0.8rem", "color" => "#aaa",
            "padding" => "4px 8px", "text-align" => "right",
        ),
    )

    table_style = Bonito.Styles(
        "border-collapse" => "collapse",
        "width" => "100%",
        "font-size" => "0.85rem",
    )
    title = Bonito.DOM.h2(
        "Benchmark metrics";
        style = Bonito.Styles(
            "font-size" => "1rem", "font-weight" => "700",
            "margin" => "0 0 6px 0", "text-align" => "center", "color" => "white",
        ),
    )
    return Bonito.DOM.div(
        title,
        Bonito.DOM.table(thead, Bonito.DOM.tbody(rows...); style = table_style),
        units_caption,
    )
end
