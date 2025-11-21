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

        # Test with single value (edge case)
        # When all values are the same, add a buffer to avoid Makie error
        profile_data_single = [3.0]
        min_val, max_val = ClimaViz.get_profile_limits(profile_data_single)
        # Buffer = max(abs(3.0) * 0.1, 0.5) = max(0.3, 0.5) = 0.5
        @test min_val ≈ 2.5
        @test max_val ≈ 3.5

        # Test with all zeros (another edge case)
        profile_data_zeros = [0.0, 0.0, 0.0]
        min_val, max_val = ClimaViz.get_profile_limits(profile_data_zeros)
        # Buffer = max(abs(0.0) * 0.1, 0.5) = 0.5
        @test min_val ≈ -0.5
        @test max_val ≈ 0.5
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
end
