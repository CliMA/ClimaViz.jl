# Demonstration of using Makie.Box for visibility toggling
# This shows the approach suggested for fixing 3D globe switching performance

using WGLMakie
using GeoMakie

"""
Demo function showing how to use Makie.Box.visible for toggling between 2D and 3D views.
This approach keeps both views in the same Figure at the same grid position [1,1],
and toggles visibility using the Box.visible property instead of CSS or figure swapping.
"""
function demo_box_visibility()
    # Create a single figure
    fig = Figure(size = (800, 600))
    
    # Observable to control which view is shown
    show_3d = Observable(false)
    
    # Create Box for 2D content at position [1,1]
    box_2d = Box(fig[1, 1], tellwidth=true, tellheight=true)
    box_2d.visible = !show_3d[]  # Initially visible
    
    # Add 2D content to the box
    ax_2d = Axis(box_2d[1, 1], title = "2D View", aspect = DataAspect())
    surface!(ax_2d, randn(50, 50))
    
    # Create Box for 3D content at the SAME position [1,1]
    box_3d = Box(fig[1, 1], tellwidth=true, tellheight=true)
    box_3d.visible = show_3d[]  # Initially hidden
    
    # Add 3D content to the box
    ax_3d = Axis3(box_3d[1, 1], title = "3D View")
    surface!(ax_3d, randn(50, 50))
    
    # Toggle button
    toggle_button = Button(fig[2, 1], label = Observable("Switch to 3D"))
    
    # Toggle visibility when button is clicked
    on(toggle_button.clicks) do _
        show_3d[] = !show_3d[]
        box_2d.visible = !show_3d[]
        box_3d.visible = show_3d[]
        toggle_button.label[] = show_3d[] ? "Switch to 2D" : "Switch to 3D"
    end
    
    return fig
end

# To run this demo:
# fig = demo_box_visibility()
# display(fig)
