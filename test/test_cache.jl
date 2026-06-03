@testset "Benchmark cache" begin

    # A synthetic entry — no ClimaAnalysis / NetCDF needed.
    make_entry(fp) = ClimaViz.BenchmarkCacheEntry(
        ClimaViz._CACHE_FORMAT_VERSION, fp,
        [0.0, 1.0, 2.0], [10.0, 20.0], 2,
        (-3.0, 3.0),
        reshape(collect(1.0:12.0), 3, 2, 2),
        [Dict((:rmse, :selected) => 1.5, (:bias, :selected) => 0.2),
         Dict((:rmse, :selected) => 1.7, (:bias, :selected) => 0.3)],
        "W m^-2",
    )
    key = ("lwu", "average", "1M", :native)

    @testset "filename sanitization" begin
        @test ClimaViz._entry_filename(key) == "lwu__average__1M__native.jls"
        @test ClimaViz._sanitize("a/b c:d") == "a_b_c_d"
    end

    @testset "roundtrip + cross-session read" begin
        dir = mktempdir()
        cache = ClimaViz.BenchmarkCache(dir)
        @test cache.dir !== nothing
        entry = make_entry("fp-1")
        ClimaViz.put_cached_entry!(cache, key, entry)
        @test isfile(joinpath(cache.dir, ClimaViz._entry_filename(key)))

        # A fresh controller (cold memory) must read it back from disk intact.
        fresh = ClimaViz.BenchmarkCache(dir)
        got = ClimaViz.get_cached_entry(fresh, key, "fp-1")
        @test got !== nothing
        @test got.n == 2
        @test got.bias_limits == (-3.0, 3.0)
        @test got.obs_resampled == entry.obs_resampled
        @test got.metrics_per_t == entry.metrics_per_t
        @test got.units == "W m^-2"
    end

    @testset "invalidation: stale fingerprint / version" begin
        dir = mktempdir()
        cache = ClimaViz.BenchmarkCache(dir)
        ClimaViz.put_cached_entry!(cache, key, make_entry("fp-1"))

        fresh = ClimaViz.BenchmarkCache(dir)
        @test ClimaViz.get_cached_entry(fresh, key, "fp-1") !== nothing
        @test ClimaViz.get_cached_entry(fresh, key, "different") === nothing
    end

    @testset "corrupt file is a miss, not a crash" begin
        dir = mktempdir()
        cache = ClimaViz.BenchmarkCache(dir)
        write(joinpath(cache.dir, ClimaViz._entry_filename(key)), "not a serialized entry")
        @test ClimaViz.get_cached_entry(cache, key, "fp-1") === nothing
    end

    @testset "disabled cache" begin
        dir = mktempdir()
        cache = ClimaViz.BenchmarkCache(dir; enabled = false)
        @test cache.dir === nothing
        @test ClimaViz.get_cached_entry(cache, key, "fp-1") === nothing
    end

    @testset "source fingerprint tracks file changes" begin
        tmpf = tempname() * ".nc"
        write(tmpf, "data")
        mock = (variable_paths = Dict(
            "lwu" => Dict("average" => Dict("1M" => Dict(nothing => [tmpf])))),)

        fp1 = ClimaViz._source_fingerprint(mock, "lwu", "average", "1M")
        @test !isempty(fp1)
        write(tmpf, "data — now longer")           # size change
        fp2 = ClimaViz._source_fingerprint(mock, "lwu", "average", "1M")
        @test fp1 != fp2
        # Unknown variable yields an empty fingerprint (never matches a stored one).
        @test ClimaViz._source_fingerprint(mock, "missing", "average", "1M") == ""
        rm(tmpf; force = true)
    end
end
