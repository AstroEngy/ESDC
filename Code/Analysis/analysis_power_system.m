% analysis_power_system — Size the spacecraft power supply system (PV + battery + converter)
%
% PURPOSE:
%   Computes the required PV array area, battery energy capacity, and power
%   converter ratings needed to supply the spacecraft's total power demand
%   through eclipse/shadow periods in the given orbit.
%   This is a first-order engineering sizing model, not a detailed circuit sim.
%
% INTENT:
%   Provides every population member with a self-consistent power system
%   sizing so that downstream functions (mass budget, volume scaling) can
%   work with real power hardware parameters.  The function is intentionally
%   lightweight (no iteration loop) because it is called for every mutation
%   in every generation.
%
% Physical model (simplified):
%   PV area   = P_required / (p_solar * eff_PV)
%   where P_required includes battery charging losses, converter losses,
%   and a design margin per NASA-GSFC-STD-1000 (25 %).
%
%   Battery = P_consumed × t_shadow / eff_battery
%   PDU     = sized from max battery/solar currents at bus voltage (28 V default).
%
% Parameters:
%   design   (struct): Current population member with subsystem_masses and
%            subsystem_powers.  Used for power_total and propulsion_power.
%   input    (struct): Input case with .orbit.orbit (timing + height).
%   db_data  (struct): Reference database (currently unused, reserved for
%            future hardware-specific efficiency lookup).
%   config   (struct): Simulation parameters (currently unused, reserved for
%            future configurable margins).
%
% Returns:
%   PSS_system (struct): Power supply sizing results with sub-structs:
%     .PV.PV_power_output_required   [W]  — required solar array output
%     .PV.PV_eff_area_required       [m²] — required solar cell area
%     .battery.E_battery_required_max [Wh] — battery energy capacity needed
%     .battery.P_batt_max            [W]  — peak battery discharge power
%     .converter.I_PDU_in/out        [A]  — PDU input/output current
%     .orbit_power_parameters.*      — orbit-specific solar flux values
%
% Hardcoded constants (candidates for config parameters):
%   eff_battery  = 0.95  (Li-ion, Battery Test Centre AU)
%   eff_converter = 0.96  (NanoAvionics EPS)
%   power_margin  = 1.25  (NASA-GSFC-STD-1000, 25 % margin)
%   eff_PV        = 0.40  (AzurSpace 3C44 triple-junction)
%   U_batt_default= 28 V  (NTRS-20150019744)
%
% HOW TO TEST:
%   1. Supply a known orbit (ISS, h=400 km) and verify t_sun/t_orbit ≈ 0.61.
%   2. Verify PV_power_output_required = p_consumed_max × power_margin /
%      (eff_battery × eff_converter) to 4 significant figures.
%   3. Set t_shadow=0 (always-sunlit orbit); verify E_battery_required_max=0
%      and P_batt_max=0 (no storage needed).
%   4. Verify all output fields are positive and finite (no NaN/Inf).
%
% SAFEGUARDS TO ADD (future work):
%   - Move eff_battery, eff_converter, power_margin, eff_PV, U_batt_default
%     to Simulation_parameters.defaults so they are configurable per run.
%   - Add a warning when PV area exceeds a configurable plausibility limit
%     (e.g. > 100 m²) indicating the power demand may be unrealistic.
%   - Replace the fixed solar constant with the orbit-specific value from
%     celestial_constants() to handle non-Earth or deep-space orbits.
function [PSS_system] = analysis_power_system(design, input, db_data, config)

  PSS_system = struct;                                                          % overall data structure power supply system
  PSS_system.PV = struct;                                                       % data on photovoltaics
  PSS_system.battery = struct;                                                  % data on batteries
  PSS_system.converter = struct;                                                % data on power conversion units
  PSS_system.orbit_power_parameters = struct;                                     % data on orbital parameters for power system sizing
  
  orbit =  input.orbit.orbit;
  height = orbit.height;

  constants = celestial_constants();                                            % use solar system and physical constants
  au = constants.au;
  solar_constant = constants.solar_constant_at_au;
  
  % ---- Solar flux at orbit altitude ----------------------------------------
  % Inverse-square law: flux decreases with distance from Earth centre.
  p_a_mean = solar_constant;
  p_a_min = solar_constant*(au/(au+height))^2;   % minimum (apoapsis of an eccentric orbit)
  p_a_max = solar_constant*(au/(au-height))^2;   % maximum (periapsis)
  

  % ---- PV sizing -----------------------------------------------------------
  t_orbit = orbit.time.orbit;
  t_sun = orbit.time.average_light;                                                                   %considers penumbra light reduction
  fraction_sun_time_orbit = t_sun/t_orbit;
  
  % Worst-case power demand: full power consumption for the entire orbit
  % (propulsion power from the individual overrides the SMAD estimate when higher)
  p_consumed_max = design.subsystem_powers.power_total- design.subsystem_powers.propulsion_power+design.propulsion_power;

  
  eff_battery = 0.95;                                                                                % https://batterytestcentre.com.au/project/lithium-ion/
  eff_converter = 0.96;                                                                              % https://nanoavionics.com/cubesat-components/cubesat-electrical-power-system-eps/
  power_margin = 1.25;                                                                                % TODO: add margin definition to defaults as well as as option , currently fixed to 20 % https://standards.nasa.gov/standard/gsfc/gsfc-std-1000
  
  eff_PV = 0.4;                                                                                       % http://www.azurspace.com/images/products/0004355-00-01_3C44_AzurDesign_10x10.pdf , use adaptive values here
  % Required solar array output power, accounting for battery charging inefficiency,
  % converter losses, and the design margin.
  PV_power_output_required =  p_consumed_max/(eff_battery*eff_converter)*power_margin;           %add losses, margin should also include inclination errors

  PV_eff_area_required = PV_power_output_required/(p_a_mean*eff_PV);    % solar cell area [m²]
  
  PV_heat_from_solar = PV_eff_area_required*p_a_mean*(1-eff_PV);   % waste heat deposited by unconverted solar flux [W]
  
  % ---- Battery sizing ------------------------------------------------------
  % Battery must store enough energy to power the spacecraft through the shadow.
  t_shadow = orbit.time.shadow.shadow_total;

  E_battery_required_max = p_consumed_max*t_shadow/eff_battery;  % [Wh] required energy capacity
  P_batt_max = E_battery_required_max/t_shadow;                   % [W]  peak discharge power
  Q_batt =  P_batt_max*(1- eff_battery);                          % [W]  waste heat during discharge
  U_batt_default = 28;                                                                              % https://ntrs.nasa.gov/api/citations/20150019744/downloads/20150019744.pdf , distinction for 10 kW 70 and 100 V, ISS 160 -> 120V
  I_batt_max = P_batt_max/U_batt_default;                         % [A]  peak discharge current
  n_cycles_per_year = ceil(31557600/t_orbit);                      % orbit periods per year

  % ---- PDU/converter sizing ------------------------------------------------
  I_PDU_in  = PV_power_output_required/U_batt_default;   % input current from solar array
  I_PDU_out = P_batt_max/U_batt_default*eff_converter;   % output current to spacecraft bus
  Q_PDU_max = P_batt_max*(1-eff_converter);               % converter waste heat [W]

  % ---- Pack results --------------------------------------------------------
  PSS_system.orbit_power_parameters.p_a_mean       = p_a_mean;
  PSS_system.orbit_power_parameters.p_a_min        = p_a_min;
  PSS_system.orbit_power_parameters.p_a_max        = p_a_max;
  PSS_system.orbit_power_parameters.p_consumed_max = p_consumed_max;
  PSS_system.orbit_power_parameters.power_margin   = power_margin;

  PSS_system.PV.PV_power_output_required = PV_power_output_required;
  PSS_system.PV.PV_efficiency            = eff_PV ;
  PSS_system.PV.PV_eff_area_required  = PV_eff_area_required;
  PSS_system.PV.heat.Q_PV_solar_irradiance = PV_heat_from_solar;

  PSS_system.battery.E_battery_required_max = E_battery_required_max;
  PSS_system.battery.P_batt_max       = P_batt_max;
  PSS_system.battery.heat.Q_batt_max         = Q_batt;
  PSS_system.battery.voltage          = U_batt_default;
  PSS_system.battery.current_max      = I_batt_max;
  PSS_system.battery.n_cycles_per_year= n_cycles_per_year;
  PSS_system.battery.batt_efficiency       = eff_battery;

  PSS_system.converter.I_PDU_in       = I_PDU_in;
  PSS_system.converter.I_PDU_out      = I_PDU_out;
  PSS_system.converter.heat.Q_conv_max       = Q_PDU_max;
  PSS_system.converter.PDU_efficiency     = eff_converter;


end
