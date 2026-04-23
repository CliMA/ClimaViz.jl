using Unitful: K, °C, mol, μmol, m, s, kg, J
import ClimaParams as CP
import ClimaLand.Parameters as LP
FT = Float64

function ClimaViz.parameterisation(
    Tₛ,
    θ, # drivers
    ν,
    V_ref_sx,
    Ea_sx,
    kM_sx,
    kM_O₂,
    O₂_a,
    p_sx,
    Csom, # parameters
    D_liq,
    D_oa,
    T_ref_sx,
    R_gas,
) # constants
    # θ has to be lower than porosity
    if θ > ν
        θ = ν
    end
    # O₂ availability (Millington-Quirk tortuosity)
    θ_a = max(ν - θ, FT(0))
    O2_avail = D_oa * O₂_a * θ_a^(FT(4 / 3))
    # DAMM model (Dual Arrhenius Michaelis-Menten), centered Arrhenius form
    Vmax = V_ref_sx * exp(-Ea_sx / R_gas * (FT(1) / Tₛ - FT(1) / T_ref_sx))
    Sx = p_sx * Csom * D_liq * max(θ, FT(0))^3
    MM_sx = Sx / (kM_sx + Sx)
    MM_o2 = O2_avail / (kM_O₂ + O2_avail)
    Rh = Vmax * MM_sx * MM_o2
    return Rh
end

function Rh_app_f()
    toml_dict = LP.create_toml_dict(FT)
    earth_param_set = LP.LandParameters(toml_dict)
    R_gas = FT(LP.gas_constant(earth_param_set))

    drivers = Drivers(
        ("Tₛ (°C)", "θ (m³ m⁻³)"), # drivers.names
        (FT.([273, 323]), FT.([0.0, 1.0])), # drivers.ranges
        ((K, °C), (m^3 * m^-3, m^3 * m^-3)),
    )

    parameters = Parameters(
        (# names
            "Soil porosity, ν (m³ m⁻³)",
            "Reference respiration rate at T_ref_sx, V_ref_sx (kg C m⁻³ s⁻¹)",
            "Activation energy, Ea_sx (J mol⁻¹)",
            "Michaelis constant for soil, kM_sx (kg C m⁻³)",
            "Michaelis constant for O₂, kM_O₂ (m³ m⁻³)",
            "Volumetric fraction of O₂ in the soil air, O₂_a (dimensionless)",
            "Fraction of soil carbon that is considered soluble, p_sx (dimensionless)",
            "Soil organic C, Csom (kg C m⁻³)",
        ),
        (# ranges (centered around toml/default_parameters.toml values)
            FT.([0.0, 1.0]), # porosity (site-specific)
            FT.([1e-8, 1e-6]), # V_ref_sx (default: 2.526e-7 kg C m⁻³ s⁻¹)
            FT.([20e3, 80e3]), # Ea_sx (default: 40000 J mol⁻¹)
            FT.([0.05, 0.6]), # kM_sx (default: 0.3 kg C m⁻³)
            FT.([4e-4, 0.04]), # kM_O₂ (default: 0.004 m³ m⁻³)
            FT.([0.05, 0.4]), # O₂_a (default: 0.2095)
            FT.([0.002, 0.25]), # p_sx (default: 0.024)
            FT.([1.0, 10.0]), # Csom (site-specific)
        ),
        (
            (m^3 * m^-3, m^3 * m^-3), # porosity
            (kg * m^-3 * s^-1, kg * m^-3 * s^-1), # V_ref_sx
            (J * mol^-1, J * mol^-1), # Ea_sx
            (kg * m^-3, kg * m^-3), # kM_sx
            (m^3 * m^-3, m^3 * m^-3), # kM_O₂
            (m, m), # O₂_a
            (m, m), # p_sx
            (kg * m^-3, kg * m^-3), # Csom
        ),
    )

    constants = Constants(
        (# names
            "Diffusivity of soil C substrate in liquid (unitless)",
            "Diffusion coefficient of oxygen in air (unitless)",
            "Reference temperature for centered Arrhenius, T_ref_sx (K)",
            "Universal gas constant (J mol⁻¹ K⁻¹)",
        ),
        (# values
            FT(3.17), # D_liq
            FT(1.67), # D_oa
            FT(288.15), # T_ref_sx
            R_gas,
        ),
    )

    inputs = Inputs(drivers, parameters, constants)

    output = Output(
        "Rh (mg C m⁻³ s⁻¹)", # name
        [0, 1 * 1e-6], # range
        (mol * m^-2 * s^-1, μmol * m^-2 * s^-1), # unit from, unit to
    )

    Rh_app = webapp(parameterisation, inputs, output)
    return Rh_app
end
