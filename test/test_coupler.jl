@testset "Coupler components" begin

    # SimDir only scans filenames, so empty placeholder files are enough to
    # exercise discovery and pruning.
    function make_fake_coupler_dir()
        dir = mktempdir()
        atmos = joinpath(dir, "clima_atmos")
        land = joinpath(dir, "clima_land")
        ocean = joinpath(dir, "clima_ocean")
        mkpath.((atmos, land, ocean))
        for f in (
            "ta_1M_average.nc", "ta_1M_average_pressure.nc",
            "pr_1M_average.nc", "orog_inst.nc", "day31.0.hdf5", "amip.yml",
        )
            touch(joinpath(atmos, f))
        end
        touch(joinpath(land, "gpp_1M_average.nc"))
        # ocean stays empty (inactive component), clima_seaice doesn't exist
        return dir
    end

    @testset "discover_components" begin
        dir = make_fake_coupler_dir()
        comps = ClimaViz.discover_components(dir)
        @test [c.label for c in comps] == ["atmos", "land"]
        @test comps[1].path == joinpath(dir, "clima_atmos")

        atmos = comps[1].simdir
        # Pruned to monthly native-grid diagnostics: no orog (inst, no period),
        # no pressure-level coordinate variants.
        @test sort(collect(keys(atmos.vars))) == ["pr", "ta"]
        for sn in keys(atmos.vars), red in keys(atmos.vars[sn]), per in keys(atmos.vars[sn][red])
            @test per == "1M"
            @test collect(keys(atmos.vars[sn][red][per])) == [nothing]
        end

        @test sort(collect(keys(comps[2].simdir.vars))) == ["gpp"]
        @test ClimaViz.discover_components(mktempdir()) == []
    end

    @testset "_resolve_sim_path" begin
        # Loose files, no output_* subdir (land/ocean convention): use the
        # folder itself.
        loose = mktempdir()
        touch(joinpath(loose, "gpp_1M_average.nc"))
        @test ClimaViz._resolve_sim_path(loose) == loose

        # output_active symlink present (current-run pointer): read from it.
        active = mktempdir()
        mkpath(joinpath(active, "output_0000"))
        symlink("output_0000", joinpath(active, "output_active"))
        @test ClimaViz._resolve_sim_path(active) == joinpath(active, "output_active")

        # No output_active, but numbered run folders: take the highest.
        numbered = mktempdir()
        mkpath.(joinpath.(numbered, ("output_0000", "output_0002", "output_0001")))
        touch(joinpath(numbered, "output_unrelated"))  # non-numbered, ignored
        @test ClimaViz._resolve_sim_path(numbered) == joinpath(numbered, "output_0002")
    end

    @testset "discover_components ignores stale top-level files" begin
        # An atmos folder holding the current run under output_active *and* a
        # stale variable left loose at the top level: only the current run's
        # variables should appear (this is what previously caused the
        # "Time dimension is not in non-decreasing order" stitch error).
        dir = mktempdir()
        atmos = joinpath(dir, "clima_atmos")
        mkpath(joinpath(atmos, "output_0000"))
        symlink("output_0000", joinpath(atmos, "output_active"))
        touch(joinpath(atmos, "output_0000", "pr_1M_average.nc"))
        touch(joinpath(atmos, "stale_1M_average.nc"))  # leftover, must be ignored

        comps = ClimaViz.discover_components(dir)
        @test [c.label for c in comps] == ["atmos"]
        @test comps[1].path == atmos  # cache root stays the component folder
        @test sort(collect(keys(comps[1].simdir.vars))) == ["pr"]
    end

    @testset "_prune_to_1M! prunes variable_paths too" begin
        dir = make_fake_coupler_dir()
        comps = ClimaViz.discover_components(dir)
        paths = comps[1].simdir.variable_paths
        @test sort(collect(keys(paths))) == ["pr", "ta"]
        @test collect(keys(paths["ta"]["average"]["1M"])) == [nothing]
    end

    @testset "_sorted_vars" begin
        simdir = (vars = Dict("b" => 1, "a" => 2, "c" => 3),)
        @test ClimaViz._sorted_vars(simdir) == ["a", "b", "c"]
    end

    @testset "mask specs" begin
        @test ClimaViz.component_mask_kind("atmos") == :globe
        @test ClimaViz.component_mask_kind("land") == :land
        @test ClimaViz.component_mask_kind("ocean") == :ocean
        @test ClimaViz.component_mask_kind("seaice") == :ocean
        @test isnothing(ClimaViz.mask_spec(:globe).mask)
        @test ClimaViz.mask_spec(:land).mask === ClimaAnalysis.apply_oceanmask
        # An empty :land tag keeps pre-existing (ocean-masked) caches valid;
        # the others must differ so a mask change invalidates stale entries.
        @test ClimaViz.mask_spec(:land).cache_tag == ""
        @test ClimaViz.mask_spec(:globe).cache_tag != ClimaViz.mask_spec(:ocean).cache_tag != ""
        @test ClimaViz.ts_mode_labels(:globe) == ["Local (click map)", "Global"]
        @test ClimaViz.ts_mode_labels(:land) == ["Local (click map)", "Global (land mean)"]
        @test ClimaViz.ts_mode_labels(:ocean)[2] == "Global (ocean mean)"
    end
end

@testset "Summary" begin
    @testset "_summary_format" begin
        @test ClimaViz._summary_format(NaN) == "—"
        @test ClimaViz._summary_format(12.344) == "12.34"
        @test ClimaViz._summary_format(0.0123) == "0.0123"
        @test ClimaViz._summary_format(0.0) == "0.0"
    end

    @testset "_rmse_cell_color" begin
        gray = "#555555"
        @test ClimaViz._rmse_cell_color(NaN, 1.0) == gray
        @test ClimaViz._rmse_cell_color(1.0, NaN) == gray
        @test ClimaViz._rmse_cell_color(1.0, 0.0) == gray
        @test ClimaViz._rmse_cell_color(0.1, 1.0) == "#2e7d32"   # ≤ 25 % → green
        @test ClimaViz._rmse_cell_color(10.0, 1.0) == "#c62828"  # ≥ 125 % → red
        # mid ramp: exact green↔yellow midpoint (guards against the UInt8
        # wrap-around bug — blue must decrease toward yellow, not wrap to ~220)
        @test ClimaViz._rmse_cell_color(0.5, 1.0) == "#798621"
    end

    @testset "_summary_table_node" begin
        empty_node = ClimaViz._summary_table_node(NamedTuple[])
        @test occursin("No benchmark", string(empty_node))
        rows = [(
            short_name = "lhf", units = "W m^-2", obs_name = "ERA5",
            rmse = Dict(s => 10.0 for s in ClimaViz._SUMMARY_SCOPES),
            bias = Dict(s => -2.0 for s in ClimaViz._SUMMARY_SCOPES),
            obs_mean = 40.0,
        )]
        # Note: Hyperscript HTML-escapes brackets ([ → &#91;), so match pieces.
        node = string(ClimaViz._summary_table_node(rows))
        @test occursin("lhf", node) && occursin("W m^-2", node)
        @test occursin("vs ERA5", node)
        @test occursin("DJF", node)
        @test occursin("10.0", node)
        @test occursin("bias -2.0", node)
    end
end
