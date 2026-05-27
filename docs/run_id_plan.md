# Run ID propagation plan

Goal: every ClimaLand output `.nc` carries a `run_id` (and friends) so the
ClimaViz dashboard can tell the user which run they're looking at, without
relying on the output directory's path.

## Where the ID lives in the data

Use NetCDF **global attributes** on the output files, not the per-variable
`comments` field. `ClimaDiagnostics.NetCDFWriter` already supports a
`global_attribs::Dict` kwarg, so this is a small plumbing change rather than
new infrastructure. Per-variable `comments` is currently documentation about
the variable; mixing run metadata in there would be a regression.

Suggested attributes:

| Key | Source | Notes |
|---|---|---|
| `run_id` | see below per run type | Required. |
| `run_type` | `"long_run"` \| `"calibration"` | Helps the dashboard format the label. |
| `git_sha` | `git rev-parse --short HEAD` of `pkgdir(ClimaLand)` | Optional but cheap and very useful. |
| `script` | relative path to the launch script | Optional. |
| `iteration`, `member` | calibration only | Optional. |

## Source of the ID per run type

| Run type | `run_id` value |
|---|---|
| Long run on Buildkite | `ENV["BUILDKITE_BUILD_NUMBER"]` |
| Long run, manual local | `"local-<yyyymmddHHMMSS>"` fallback |
| Calibration | `basename(output_dir) * "/iter_<i>/member_<m>"` |

## Required changes in ClimaLand

### A. Plumb `global_attribs` through the diagnostics layer

File: `src/diagnostics/default_diagnostics.jl`

1. Add `global_attribs = nothing` kwarg to `default_diagnostics(...)`.
2. Add `global_attribs = nothing` kwarg to `default_output_writer(domain, start_date, outdir; ...)` (all three method signatures: `SphericalShell/SphericalSurface`, `Plane/HybridBox`, `Column/Point`).
3. Forward to `NetCDFWriter(space, outdir; start_date, ..., global_attribs)`.

`NetCDFWriter` already accepts `global_attribs` — no upstream change needed in `ClimaDiagnostics`.

### B. Long-run script

File: `experiments/long_runs/snowy_land_pmodel.jl` (and any sibling long-run scripts you want to cover, e.g. `bucket.jl`, `low_res_snowy_land_*.jl`).

Add near the top, after `device_suffix` is known:

```julia
run_id = get(ENV, "BUILDKITE_BUILD_NUMBER",
             "local-" * Dates.format(now(), "yyyymmddHHMMSS"))
git_sha = try
    readchomp(`git -C $(pkgdir(ClimaLand)) rev-parse --short HEAD`)
catch
    ""
end
global_attribs = Dict(
    "run_id"   => run_id,
    "run_type" => "long_run",
    "script"   => relpath(@__FILE__, pkgdir(ClimaLand)),
    "git_sha"  => git_sha,
)
```

`LandSimulation` currently builds default diagnostics internally given
`outdir`. To thread the attributes through, either:

- **Option 1 (recommended):** call `default_diagnostics(model, start_date, outdir; global_attribs)` explicitly here, then pass `diagnostics = ...` into `LandSimulation`. The calibration path already does this — long runs would just match.
- **Option 2:** add a `global_attribs` kwarg to `LandSimulation` that it forwards into its own `default_diagnostics` call.

Option 1 has zero API surface change and is the smaller diff.

### C. Calibration model interface

File: `experiments/calibration/models/snowy_land.jl` (and `bucket.jl` next to it).

`default_diagnostics(...)` is already called explicitly at line ~130 with `outdir`. Just add `global_attribs` to that call:

```julia
run_id = joinpath(basename(rstrip(output_dir, '/')),
                  "iter_$(iteration)", "member_$(member)")
git_sha = try
    readchomp(`git -C $(pkgdir(ClimaLand)) rev-parse --short HEAD`)
catch
    ""
end
global_attribs = Dict(
    "run_id"    => run_id,
    "run_type"  => "calibration",
    "iteration" => iteration,
    "member"    => member,
    "git_sha"   => git_sha,
)

diagnostics = ClimaLand.Diagnostics.default_diagnostics(
    model, start_date, outdir;
    output_vars = short_names,
    reduction_period = :monthly,
    reduction_type = :average,
    global_attribs,
)
```

## Required changes in ClimaViz

### A. Read the ID

In `src/dashboard.jl`, after `initial_var` is constructed:

```julia
run_id    = get(initial_var.attributes, "run_id",
                basename(rstrip(path, '/')))
run_type  = get(initial_var.attributes, "run_type", "")
git_sha   = get(initial_var.attributes, "git_sha", "")
```

Pass these into `layout(...)`.

### B. Show it in the UI

In `src/layout.jl`, add a small header at the top of the menu column (above
the dark-mode row), styled with the existing `title-card` class so it picks
up the dark/light theme automatically:

```julia
run_label = Bonito.DOM.div(
    Bonito.DOM.h2("Run: " * run_id; style = ...),
    Bonito.DOM.span(string(run_type, "  ", git_sha); style = ...);
    class = "title-card",
    style = menu_card_style,
)
```

Include `git_sha` only when non-empty. Tooltip the long form on hover.

### Backwards compatibility

The dashboard already falls back to `basename(path)` if `run_id` is absent,
so existing output directories (without the new attribute) keep working
unchanged.

## Suggested order

1. ClimaLand PR adding the `global_attribs` plumbing (independent, harmless when nil).
2. Update the two experiment scripts to populate `run_id`.
3. ClimaViz PR adding the header readout, with the `basename(path)` fallback.
