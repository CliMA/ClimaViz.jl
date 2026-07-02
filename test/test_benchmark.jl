@testset "Benchmark obs and display units" begin

    _mk_flux(short_name, units, data) = ClimaAnalysis.OutputVar(
        Dict{String, Any}("short_name" => short_name, "units" => units),
        Dict("time" => [0.0, 1.0]),
        Dict{String, Dict}(),
        data,
    )

    @testset "to_display_units water fluxes" begin
        # ClimaAtmos pr is a negative-downward mass flux: sign flips, mm/day.
        pr = ClimaViz.to_display_units(
            _mk_flux("pr", "kg m^-2 s^-1", [-2.0e-5, -1.0e-5]),
        )
        @test ClimaAnalysis.units(pr) == "mm day^-1"
        @test pr.data ≈ [-2.0e-5, -1.0e-5] .* -86400.0

        # evspsbl is already positive-up: rescale only.
        ev = ClimaViz.to_display_units(
            _mk_flux("evspsbl", "kg m^-2 s^-1", [3.0e-5, 4.0e-5]),
        )
        @test ClimaAnalysis.units(ev) == "mm day^-1"
        @test ev.data ≈ [3.0e-5, 4.0e-5] .* 86400.0

        # Energy fluxes pass through untouched.
        lhf = _mk_flux("lhf", "W m^-2", [10.0, 20.0])
        @test ClimaViz.to_display_units(lhf) === lhf
    end

    # The artifact-backed loaders: assert units, labels, and physically sane
    # global (unweighted, NaN-ignoring) means over the full record.
    _nanmean(v) = begin
        vals = filter(!isnan, vec(Float64.(v.data)))
        sum(vals) / length(vals)
    end

    @testset "pr obs loader (GPCP)" begin
        obs = default_gpcp_obs()
        @test haskey(obs, "pr")
        v = obs["pr"](nothing)
        @test v isa ClimaAnalysis.OutputVar
        @test ClimaAnalysis.units(v) == "mm day^-1"
        @test v.attributes["short_name"] == "pr"
        @test v.attributes["obs_source"] == "GPCP"
        @test 0.5 < _nanmean(v) < 5.0
    end

    @testset "evspsbl obs loader (ERA5 mer)" begin
        obs = default_era5_obs()
        @test haskey(obs, "evspsbl")
        v = obs["evspsbl"](nothing)
        @test v isa ClimaAnalysis.OutputVar
        @test ClimaAnalysis.units(v) == "mm day^-1"
        @test v.attributes["short_name"] == "evspsbl"
        @test v.attributes["obs_source"] == "ERA5"
        # ERA5 stores evaporation negative; the loader flips it positive-up.
        @test 0.2 < _nanmean(v) < 6.0
    end

    @testset "prw obs loader (ERA5 tcw)" begin
        obs = default_era5_obs()
        @test haskey(obs, "prw")
        v = obs["prw"](nothing)
        @test v isa ClimaAnalysis.OutputVar
        @test ClimaAnalysis.units(v) == "kg m^-2"
        @test v.attributes["short_name"] == "prw"
        @test v.attributes["obs_source"] == "ERA5"
        @test 5.0 < _nanmean(v) < 40.0
    end

    @testset "default_obs merges all registries" begin
        obs = default_obs()
        for name in ("lhf", "hfls", "nee", "pr", "evspsbl", "prw")
            @test haskey(obs, name)
        end
    end
end
