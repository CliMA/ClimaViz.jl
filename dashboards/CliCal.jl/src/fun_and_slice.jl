export RMSE,
       slicevar,
       add_seasonal_access,
       add_seasonal_access_g,
       add_seasonal_access_gamma,
       cosine_weighted_global_mean,
       load_and_process_data


# Notes: slicevar and add_seasonal... will be deprecated once we have a common
# flattening and reconstruction of diagnostics. (for Atmos and Land).
# The code will then need to be refactored, and will work for Atmos and Land.
# See PR https://github.com/CliMA/ClimaAnalysis.jl/pull/269

function RMSE(x, z)
    return sqrt(mean((x.-z).^2))
end

"""
    slicevar(v, n, n_vars)

Return the slice for variable `n` (1-based) out of `n_vars` total variables,
from the flattened vector `v`.
"""
function slicevar(v, n, n_vars)
    # Calculate the stride (how many positions to move for the next site/location)
    stride = n_vars * 4  # 4 seasons per location per variable

    # Calculate indices for variable n
    start_offset = (n - 1) * 4  # Starting offset for this variable

    # Create indices list for this variable (handling all seasons for all locations)
    idx = vcat([(i + start_offset):(i + start_offset + 3) for i in 1:stride:length(v)]...)

    return v[idx]
end

function add_seasonal_access(data_dict, vars)
    result = Dict{Any, Any}()

    for (site_id, site_data) in data_dict
        result[site_id] = Dict{String, Any}()

        for var_key in vars
            # Create a new dictionary for each variable with seasonal slices
            if haskey(site_data, var_key)
                values = site_data[var_key]
                result[site_id][var_key] = Dict{String, Vector{Float64}}(
                                                                         "DJF" => values[1:4:end],
                                                                         "MAM" => values[2:4:end],
                                                                         "JJA" => values[3:4:end],
                                                                         "SON" => values[4:4:end]
                                                                        )
            end
        end
    end

    return result
end

function add_seasonal_access_g(data_dict, vars)
    result = Dict{Any, Any}()

    for (outer_key, outer_val) in data_dict
        result[outer_key] = Dict{Any, Any}()

        for (middle_key, middle_val) in outer_val
            result[outer_key][middle_key] = Dict{String, Any}()

            for var_key in vars
                if haskey(middle_val, var_key)
                    values = middle_val[var_key]
                    # Create seasonal slices for each variable
                    result[outer_key][middle_key][var_key] = Dict{String, Vector{Float64}}(
                                                                                           "DJF" => values[1:4:end],
                                                                                           "MAM" => values[2:4:end],
                                                                                           "JJA" => values[3:4:end],
                                                                                           "SON" => values[4:4:end]
                                                                                          )
                end
            end
        end
    end

    return result
end

function add_seasonal_access_gamma(data_dict, vars)
    result = Dict{String, Dict{String, Vector{Float64}}}()

    for var_key in vars
        if haskey(data_dict, var_key)
            values = data_dict[var_key]
            # Create seasonal slices for each specified variable
            result[var_key] = Dict{String, Vector{Float64}}(
                                                            "DJF" => values[1:4:end],
                                                            "MAM" => values[2:4:end],
                                                            "JJA" => values[3:4:end],
                                                            "SON" => values[4:4:end]
                                                           )
        end
    end

    return result
end

# Calculate mean lat weight averaged
function cosine_weighted_global_mean(values::Vector{Float64}, lats::Vector{Float64})
    @assert length(values) == length(lats) "Length mismatch between values and latitudes"

    weights = cosd.(lats)  # cosd for degrees
    numerator = sum(values .* weights)
    denominator = sum(weights)

    return numerator / denominator
end

# Function to load data and process it
function load_and_process_data(eki_file)
    println("Loading: EKI=$(eki_file)")

    # Load eki object
    eki = JLD2.load_object(eki_file)

    # Get basic information
    n_ensembles = EKP.get_N_ens(eki)
    n_iterations = EKP.get_N_iterations(eki)
    errors = eki.error_metrics["loss"]
    normalized_errors = errors ./ errors[1] .* 100

    # Get all g
    g_all = [EKP.get_g(eki, i) for i in 1:n_iterations]

    # Get all y
    obs_series = EKP.get_observation_series(eki)
    y_obs = obs_series.observations
    y_all = [EKP.get_obs(y_obs[i]) for i in 1:n_iterations]

    # Get prior, variable_list, and locations
    prior, variable_list, locations = obs_series.metadata

    # Get all gamma (noise)
    noise = EKP.get_obs_noise_cov(eki, build = false)
    noise_variance = reduce(vcat, [diag(m) for m in noise])
    # Ollie: how do I get a vector of same length as y_all

    # Get all constrained parameters
    params = EKP.get_ϕ(prior, eki)
    param_dict = Dict(i => [params[i][:, j] for j in 1:size(params[i], 2)] for i in eachindex(params))
    params_name = prior.name

    # Get variable list - extract from the prior or config if available
    # This is a bit of an assumption - adjust based on how your prior stores variable names
    n_vars = length(variable_list)

    # Process y_data
    y_data = Dict()
    for iteration_n in 1:length(y_all)
        y_data[iteration_n] = Dict()
        for (var_idx, var_name) in enumerate(variable_list)
            y_data[iteration_n][var_name] = slicevar(y_all[iteration_n], var_idx, n_vars)
        end
    end

    # Process g_data
    g_data = Dict()
    for iteration_n in 1:length(g_all)
        g = g_all[iteration_n]
        g_data[iteration_n] = Dict()

        # Create indices for each variable
        idxs = Dict()
        for (var_idx, var_name) in enumerate(variable_list)
            idxs[var_name] = slicevar(1:size(g, 1), var_idx, n_vars)
        end

        # Fill in g_data
        for ensemble in 1:size(g, 2)
            g_data[iteration_n][ensemble] = Dict(
                                                 var => g[idxs[var], ensemble] for var in variable_list
                                                )
        end
    end

    # Process gamma_data
    gamma_data = Dict()
    for (var_idx, var_name) in enumerate(variable_list)
        gamma_data[var_name] = slicevar(noise_variance, var_idx, n_vars)
    end

    # Create structures with seasonal access
    seasonal_y_data = add_seasonal_access(y_data, variable_list)
    seasonal_g_data = add_seasonal_access_g(g_data, variable_list)
    seasonal_gamma_data = add_seasonal_access_gamma(gamma_data, variable_list)

    # Extract locations
    lons = map(x -> x[1], locations)
    lats = map(x -> x[2], locations)

    # Define RMSE benchmarks (can be customized based on your variables)
    rmse_benchmarks = Dict()
    for var in variable_list
        # Default benchmarks, can be customized
        if var == "lhf"
            rmse_benchmarks[var] = 20
        elseif var == "shf"
            rmse_benchmarks[var] = 15
        elseif var == "swu"
            rmse_benchmarks[var] = 25
        elseif var == "lwu"
            rmse_benchmarks[var] = 10
        else
            # Default for other variables
            rmse_benchmarks[var] = 20
        end
    end

    return Dict(
                "eki" => eki,
                "prior" => prior,
                "n_ensembles" => n_ensembles,
                "n_iterations" => n_iterations,
                "errors" => errors,
                "normalized_errors" => normalized_errors,
                "g_all" => g_all,
                "y_all" => y_all,
                "params" => params,
                "param_dict" => param_dict,
                "params_name" => params_name,
                "variable_list" => variable_list,
                "y_data" => y_data,
                "g_data" => g_data,
                "seasonal_y_data" => seasonal_y_data,
                "seasonal_g_data" => seasonal_g_data,
                "seasonal_gamma_data" => seasonal_gamma_data,
                "lons" => lons,
                "lats" => lats,
                "rmse_benchmarks" => rmse_benchmarks
               )
end
