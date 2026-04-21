"""
  Drivers(names, ranges, units)

A struct to store drivers names, ranges and units
"""
struct Drivers
  names
  ranges
  units
end

"""
  Parameters(names, ranges, units)

A struct to store parameters names, ranges and units
"""
struct Parameters
  names
  ranges
  units
end

"""
  Constants(names, values)

A struct to store constants names and values
"""
struct Constants
  names
  values
end

"""
  Inputs(drivers, parameters, constants)

A struct to store drivers, parameters and constants.
"""
struct Inputs
  drivers::Drivers
  parameters::Parameters
  constants::Constants
end

"""
  Output(name, range, unit)

A struct to store output name, range and unit.
"""
struct Output
  name
  range
  unit
end

# Function stubs — methods are added by ParamVizExt
function parameterisation end
function webapp end
function param_dashboard end

"""
    dashboard_paramviz(model_name::String; ip="127.0.0.1", port=9384)

Launch a web dashboard for a built-in parameterisation model.

`model_name` selects the model to visualize. Currently available:
- `"damm_model"` — Heterotrophic respiration (Dual Arrhenius Michaelis-Menten).

Starts a Bonito server, routes the app at `"/"`, prints the URL, and returns
the server. In a script, call `wait()` after to keep the process alive.

Implemented by the `ParamVizExt` extension — load `Unitful` and `UnitfulMoles`
in the session for this to resolve.
"""
function dashboard_paramviz end
