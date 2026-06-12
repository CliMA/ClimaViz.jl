@testset "Utility Functions" begin

    @testset "get_profile_limits" begin
        # Test basic profile limits calculation
        profile_data = [1.0, 2.0, 3.0, 4.0, 5.0]
        min_val, max_val = ClimaViz.get_profile_limits(profile_data)

        # Expected: min = 1.0, max = 5.0, range = 4.0, padding = 0.2
        # Result: (0.8, 5.2)
        @test min_val ≈ 0.8
        @test max_val ≈ 5.2

        # Test with custom padding
        min_val, max_val = ClimaViz.get_profile_limits(profile_data, padding_fraction = 0.1)
        @test min_val ≈ 0.6
        @test max_val ≈ 5.4

        # Test with zero padding
        min_val, max_val = ClimaViz.get_profile_limits(profile_data, padding_fraction = 0.0)
        @test min_val ≈ 1.0
        @test max_val ≈ 5.0

        # Test with single value (edge case): a flat profile gets a
        # ±(0.1|v| + 0.1) buffer so the axis never has a zero-width range.
        profile_data_single = [3.0]
        min_val, max_val = ClimaViz.get_profile_limits(profile_data_single)
        @test min_val ≈ 2.6
        @test max_val ≈ 3.4
    end

    @testset "has_height" begin
        # Create mock objects with dims dictionary
        var_with_z = (dims = Dict("z" => [1, 2, 3]),)
        var_with_z_reference = (dims = Dict("z_reference" => [1, 2, 3]),)
        var_without_height = (dims = Dict("time" => [1, 2, 3]),)

        @test ClimaViz.has_height(var_with_z) == true
        @test ClimaViz.has_height(var_with_z_reference) == true
        @test ClimaViz.has_height(var_without_height) == false
    end

    @testset "get_height_dim_name" begin
        # Create mock objects
        var_with_z = (dims = Dict("z" => [1, 2, 3]),)
        var_with_z_reference = (dims = Dict("z_reference" => [1, 2, 3]),)
        var_without_height = (dims = Dict("time" => [1, 2, 3]),)

        @test ClimaViz.get_height_dim_name(var_with_z) == "z"
        @test ClimaViz.get_height_dim_name(var_with_z_reference) == "z_reference"
        @test_throws ErrorException ClimaViz.get_height_dim_name(var_without_height)
    end

    @testset "print_startup_message" begin
        # Test that print_startup_message doesn't error
        # We can't easily test the output without mocking stdout,
        # but we can ensure it runs without errors
        @test (ClimaViz.print_startup_message(8080); true)
        @test (ClimaViz.print_startup_message(3000); true)
    end

    @testset "_pad_series" begin
        @test ClimaViz._pad_series([1.0, 2.0], 4) ≈ [1.0, 2.0, NaN, NaN] nans = true
        @test ClimaViz._pad_series([1.0, 2.0, 3.0], 2) == [1.0, 2.0]
        @test ClimaViz._pad_series([1.0, 2.0], 2) == [1.0, 2.0]
    end

    @testset "obs_source_name" begin
        @test ClimaViz.obs_source_name(nothing) == "obs"
        tagged = (attributes = Dict("obs_source" => "ERA5"),)
        untagged = (attributes = Dict{String, Any}(),)
        @test ClimaViz.obs_source_name(tagged) == "ERA5"
        @test ClimaViz.obs_source_name(untagged) == "obs"
    end

    @testset "timeseries_title_string modes" begin
        var = ClimaAnalysis.OutputVar(
            Dict{String, Any}("short_name" => "lhf"),
            Dict("time" => [0.0, 1.0, 2.0]),
            Dict{String, Dict}(),
            [1.0, 2.0, 3.0],
        )
        t_local = ClimaViz.timeseries_title_string(var, Float64[], 1, -118.25, 34.05, :local)
        t_global = ClimaViz.timeseries_title_string(var, Float64[], 1, -118.25, 34.05, :global)
        @test occursin("Lon: -118.25°, Lat: 34.05°", t_local)
        @test occursin("Global (land mean)", t_global)
        @test occursin("lhf", t_global)
    end
end
