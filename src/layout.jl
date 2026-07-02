export layout

function layout(
    var_menu, reduction_menu, period_menu, aggregation_menu, ts_mode_menu,
    time_slider, height_slider, play_button, speed_slider,
    fig, fig_bias, fig_profile, fig_timeseries,
    show_height, show_bias, metrics, coverage_text,
    time_value_label, height_value_label, speed_value_label,
    dark_mode_checkbox,
    is_loading, loading_status, obs_name;
    run_title = "",
    component_menu = nothing,
    summary_button = nothing,
    summary_overlay = nothing,
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

    # Optional run caption shown just below the play button.
    run_title_style = Bonito.Styles(
        "font-size" => "0.85rem", "font-weight" => "700",
        "margin" => "8px 0 0 0", "text-align" => "center", "color" => "#9ec5fe",
        # Render newlines in the caption as line breaks (multi-line run titles),
        # and let an over-long token (e.g. a 40-char commit hash) wrap inside the
        # 400px menu column instead of overflowing it.
        "white-space" => "pre-line", "overflow-wrap" => "anywhere",
    )

    menu_items = Any[dark_mode_row]
    if !isnothing(component_menu)
        push!(menu_items, Bonito.Row(Bonito.DOM.h1("Component: "; style = label_style), component_menu))
    end
    append!(menu_items, Any[
        Bonito.Row(Bonito.DOM.h1("Variable: "; style = label_style), var_menu),
        Bonito.Row(Bonito.DOM.h1("Aggregation: "; style = label_style), aggregation_menu),
        Bonito.Row(Bonito.DOM.h1("Time series: "; style = label_style), ts_mode_menu),
        Bonito.Row(Bonito.DOM.h1("Time: "; style = label_style), time_slider, time_value_label),
        height_row,
        animation_row,
    ])
    if !isnothing(summary_button)
        push!(menu_items, Bonito.Row(summary_button))
    end
    if !isempty(run_title)
        push!(menu_items, Bonito.DOM.div(run_title; style = run_title_style))
    end

    menu_column = Bonito.Col(menu_items...; height = "auto")

    menu_card = Bonito.Card(
        menu_column;
        shadow_size = "0",
        style = menu_card_style,
        class = "menu-card",
    )

    metrics_card = Bonito.Card(
        _metrics_panel(metrics, coverage_text, obs_name);
        shadow_size = "0",
        style = menu_card_style,
        class = "menu-card metrics-card",
    )

    menu_column_layout = Bonito.Col(menu_card, metrics_card; height = "100vh")

    surfaces_column = Bonito.Col(
        Bonito.Card(fig; shadow_size = "0"),
        Bonito.Card(fig_bias; shadow_size = "0");
        height = "100vh",
    )

    charts_column = Bonito.Col(
        Bonito.Card(fig_timeseries; shadow_size = "0"),
        Bonito.Card(fig_profile; shadow_size = "0");
        height = "100vh",
    )

    grid = Bonito.Grid(
        menu_column_layout, surfaces_column, charts_column;
        columns = "400px 1100px 800px",
        gap = "5px",
    )

    progress_bar, status_label, css_block = _progress_indicator(is_loading, loading_status)
    tail = isnothing(summary_overlay) ? () : (summary_overlay,)
    return Bonito.Col(css_block, progress_bar, status_label, grid, tail...)
end

# Compact metrics panel. Always reports the currently selected time frame
# (`:selected` scope); `coverage_text` shows which period that frame covers
# (e.g. "January 2009", "MAM 2009", "2009"). `obs_name` is the obs product
# display name, used to label the obs rows ("ERA5 mean" instead of "Obs mean").
function _metrics_panel(metrics, coverage_text, obs_name)
    label_style = Bonito.Styles(
        "font-size" => "1.1rem", "font-weight" => "600",
        "padding" => "4px 8px", "color" => "white", "text-align" => "left",
    )
    value_style = Bonito.Styles(
        "font-size" => "1.15rem", "font-variant-numeric" => "tabular-nums",
        "padding" => "4px 8px", "color" => "white", "text-align" => "right",
        "min-width" => "90px",
    )
    row_style = Bonito.Styles(
        "display" => "flex", "justify-content" => "space-between",
        "align-items" => "center", "border-bottom" => "1px solid #2a2a2a",
    )
    title_style = Bonito.Styles(
        "font-size" => "1.3rem", "font-weight" => "700",
        "margin" => "0 0 4px 0", "text-align" => "center", "color" => "white",
    )
    coverage_style = Bonito.Styles(
        "font-size" => "1.05rem", "font-weight" => "600",
        "margin" => "0 0 8px 0", "text-align" => "center", "color" => "#9ec5fe",
    )

    coverage_caption = Bonito.DOM.div(coverage_text; style = coverage_style)

    rows = Any[]
    for m in METRIC_ROWS
        value_text = map(t -> format_cell(t, m, :selected), metrics)
        row_label = m === :obs_mean ? map(n -> string(n, " mean"), obs_name) : METRIC_LABELS[m]
        push!(rows, Bonito.DOM.div(
            Bonito.DOM.span(row_label; style = label_style),
            Bonito.DOM.span(value_text; style = value_style);
            style = row_style,
        ))
    end

    units_text = map(t -> isempty(t.units) ? "" : string("Units: ", t.units), metrics)
    units_caption = Bonito.DOM.div(units_text;
        style = Bonito.Styles(
            "font-size" => "0.95rem", "color" => "#aaa",
            "padding" => "6px 8px", "text-align" => "right",
        ),
    )

    return Bonito.DOM.div(
        Bonito.DOM.h2("Benchmark metrics"; style = title_style),
        coverage_caption,
        rows...,
        units_caption,
    )
end

# Top-of-dashboard progress bar (visible only when is_loading[] is true) and a
# small status caption underneath. Animation is pure CSS so it stays smooth
# regardless of what the main thread is doing.
function _progress_indicator(is_loading::Observable, loading_status::Observable)
    css_block = Bonito.DOM.style("""
    @keyframes climaviz-loading-shimmer {
      0%   { background-position: 100% 0; }
      100% { background-position: -100% 0; }
    }
    .climaviz-progress-bar {
      height: 4px;
      width: 100%;
      background: linear-gradient(90deg, transparent 0%, #2196F3 50%, transparent 100%);
      background-size: 200% 100%;
      animation: climaviz-loading-shimmer 1.2s linear infinite;
    }
    .climaviz-progress-bar-hidden {
      height: 4px;
      width: 100%;
      background: transparent;
    }
    """)

    bar_class = map(is_loading) do loading
        loading ? "climaviz-progress-bar" : "climaviz-progress-bar-hidden"
    end

    progress_bar = Bonito.DOM.div(""; class = bar_class)

    status_style = Bonito.Styles(
        "font-size" => "0.8rem", "color" => "#9ec5fe",
        "padding" => "2px 8px", "height" => "16px",
        "font-family" => "system-ui, sans-serif",
    )
    status_label = Bonito.DOM.div(loading_status; style = status_style)

    return progress_bar, status_label, css_block
end
