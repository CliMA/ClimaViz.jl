using Unitful: K, °C, mol, μmol, m, s, kg, J

const _FT = Float64
const _R_GAS = _FT(8.31446261815324)

function ClimaViz.parameterisation(
    Tₛ::FT,
    θ::FT,
    ν::FT,
    V_ref_sx::FT,
    Ea_sx::FT,
    kM_sx::FT,
    kM_O₂::FT,
    O₂_a::FT,
    p_sx::FT,
    Csom::FT,
    D_liq::FT,
    D_oa::FT,
    T_ref_sx::FT,
    R_gas::FT,
) where {FT <: AbstractFloat}
    if θ > ν
        θ = ν
    end
    θ_a = max(ν - θ, FT(0))
    O2_avail = D_oa * O₂_a * θ_a^(FT(4 / 3))
    Vmax = V_ref_sx * exp(-Ea_sx / R_gas * (FT(1) / Tₛ - FT(1) / T_ref_sx))
    Sx = p_sx * Csom * D_liq * max(θ, FT(0))^3
    MM_sx = Sx / (kM_sx + Sx)
    MM_o2 = O2_avail / (kM_O₂ + O2_avail)
    return Vmax * MM_sx * MM_o2
end

function _damm_app()
    FT = _FT

    drivers = Drivers(
        ("Tₛ (°C)", "θ (m³ m⁻³)"),
        (FT.([273, 323]), FT.([0.0, 1.0])),
        ((K, °C), (m^3 * m^-3, m^3 * m^-3)),
    )

    parameters = Parameters(
        (
            "Soil porosity, ν (m³ m⁻³)",
            "Reference respiration rate at T_ref_sx, V_ref_sx (kg C m⁻³ s⁻¹)",
            "Activation energy, Ea_sx (J mol⁻¹)",
            "Michaelis constant for soil, kM_sx (kg C m⁻³)",
            "Michaelis constant for O₂, kM_O₂ (m³ m⁻³)",
            "Volumetric fraction of O₂ in the soil air, O₂_a (dimensionless)",
            "Fraction of soil carbon that is considered soluble, p_sx (dimensionless)",
            "Soil organic C, Csom (kg C m⁻³)",
        ),
        (
            FT.([0.0, 1.0]),
            FT.([1e-8, 1e-6]),
            FT.([20e3, 80e3]),
            FT.([0.05, 0.6]),
            FT.([4e-4, 0.04]),
            FT.([0.05, 0.4]),
            FT.([0.002, 0.25]),
            FT.([1.0, 10.0]),
        ),
        (
            (m^3 * m^-3, m^3 * m^-3),
            (kg * m^-3 * s^-1, kg * m^-3 * s^-1),
            (J * mol^-1, J * mol^-1),
            (kg * m^-3, kg * m^-3),
            (m^3 * m^-3, m^3 * m^-3),
            (m, m),
            (m, m),
            (kg * m^-3, kg * m^-3),
        ),
    )

    constants = Constants(
        (
            "Diffusivity of soil C substrate in liquid (unitless)",
            "Diffusion coefficient of oxygen in air (unitless)",
            "Reference temperature for centered Arrhenius, T_ref_sx (K)",
            "Universal gas constant (J mol⁻¹ K⁻¹)",
        ),
        (FT(3.17), FT(1.67), FT(288.15), _R_GAS),
    )

    inputs = Inputs(drivers, parameters, constants)
    output = Output(
        "Rh (mg C m⁻³ s⁻¹)",
        [0, 1 * 1e-6],
        (mol * m^-2 * s^-1, μmol * m^-2 * s^-1),
    )

    return webapp(ClimaViz.parameterisation, inputs, output)
end

const BUILTIN_MODELS = Dict("damm_model" => _damm_app)

function ClimaViz.dashboard_paramviz(
    model_name::String;
    ip::String = "127.0.0.1",
    port::Int = 9384,
)
    haskey(BUILTIN_MODELS, model_name) || error(
        "Unknown model: $(repr(model_name)). Available: $(sort(collect(keys(BUILTIN_MODELS))))",
    )
    builder = BUILTIN_MODELS[model_name]
    app = builder()
    app = builder()  # second build works around a unicode-character rendering bug
    server = Bonito.Server(ip, port)
    Bonito.route!(server, "/" => app)
    println("$model_name dashboard running at http://$ip:$port")
    return server
end
