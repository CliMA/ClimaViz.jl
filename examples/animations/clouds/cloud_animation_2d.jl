using GLMakie
using GeoMakie
using ClimaAnalysis
using FileIO
using Statistics

earth_img = load(download("https://upload.wikimedia.org/wikipedia/commons/5/56/Blue_Marble_Next_Generation_%2B_topography_%2B_bathymetry.jpg"))

fig = Figure(size = (6000, 3000), figure_padding = 0) #, backgroundcolor = :black)
#ax = GeoMakie.GlobeAxis(fig[1,1]; show_axis = false)
ax = GeoMakie.GeoAxis(fig[1,1]; dest = "+proj=eqc")
hidedecorations!(ax)

simdir = SimDir("data")
var = get(simdir, "clwvi")
lon = var.dims["lon"]
lat = var.dims["lat"]

surface!(ax,
         -180..180, -90..90,
         zeros(axes(rotr90(earth_img)));
         shading = NoShading,
         color = rotr90(earth_img),
         backlight = 1.5f0,
        )

time = Observable(1)

var_time = @lift(slice(var, time = var.dims["time"][$time]))
var_data = @lift($var_time.data)

limits = (0, 0.04)

alpha_values = @lift(($var_data .- minimum($var_data)) ./ (maximum($var_data) - minimum($var_data)))

low_val = @lift(quantile(vec($alpha_values), 0.2))
high_val = @lift(quantile(vec($alpha_values), 0.85))

transform(x; low=low_val, high=high_val) = clamp((x - low) / (high - low), 0, 1)

alpha_values = @lift(transform.($alpha_values; low = $low_val, high = $high_val))   # apply elementwise to your matrix

cloud_trans = @lift(RGBAf.(1, 1, 1, $alpha_values))

p = surface!(ax, lon, lat, var_data,
             color = cloud_trans,
#             zlevel = 300_000,
             shading = NoShading,
             transparency = true,
            )

total_frames = length(var.dims["time"])

record(fig, "animation_2d.mp4", 1:total_frames; framerate = 20, compression = 5) do t
#    if t == 1
#        zoom!(ax.scene, 0.6)
#    end
    time[] = t
#    rotate_cam!(ax.scene, 0, -0.015, 0)
end
