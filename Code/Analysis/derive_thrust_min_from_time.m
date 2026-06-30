function thrust_min = derive_thrust_min_from_time(data, case_inputs, config)
% derive_thrust_min_from_time — Compute the minimum thrust to meet the maneuver time constraint
%
% PURPOSE:
%   Given a design point's propellant mass and exhaust velocity, derives the
%   minimum thrust that allows the total delta-v maneuver to be completed
%   within the allowable burn time.  This constraint hard-rejects slow
%   propulsion systems (e.g. low-power EP) when the mission requires rapid
%   manoeuvring.
%
% PHYSICAL BASIS:
%   Total impulse:   I_tot = m_prop × c_e          [N·s]
%   Burn time def:   I_tot = F × t_burn             [N·s]
%   ⟹ F_min = I_tot / t_burn_max = m_prop × c_e / t_burn_max   [N]
%
% Three input modes (checked in priority order):
%   1. maneuver_duration_max [s]  -- directly given maximum burn time
%   2. mission_duration [years] combined with propulsion_time_fraction [-]:
%        t_burn_max = propulsion_time_fraction × mission_duration_in_seconds
%   3. No user input — fall back to sc_type-based defaults from config:
%        config.Simulation_parameters.defaults.mission_duration_years
%        config.Simulation_parameters.defaults.propulsion_time_fraction
%      Default values (set in ESDC_Simulation_parameters):
%        sc_type 1 (No Propulsion): 3 yr  (SMAD, typical CubeSat lifetime)
%        sc_type 2 (LEO):           5 yr  (SMAD Table 1-3, median LEO lifetime)
%        sc_type 3 (GEO/HEO):      15 yr  (ECSS-E-ST-10-04C, GEO commercial)
%        sc_type 4 (Planetary):    10 yr  (Cassini 13yr, Rosetta/New Horizons 10yr)
%      propulsion_time_fraction default = 0.10 (SMAD 2011 p.693, EP duty cycles 5-20%)
%
% Parameters:
%   data        -- population member struct with fields:
%                    subsystem_masses.mass_propellant  [kg]
%                    c_e                               [m/s]
%                    deltav or dv                      [m/s]  (for sc_type fallback)
%   case_inputs -- input case struct with optional fields:
%                    maneuver_duration_max       [s]
%                    mission_duration            [years]
%                    propulsion_time_fraction    [-]
%   config      -- (optional) simulation config struct with defaults block
%
% Returns:
%   thrust_min  -- minimum required thrust [N], 0 if no constraint can be derived
%
% HOW TO TEST:
%   1. Mode 1: set maneuver_duration_max=3600 s, m_prop=50 kg, c_e=2000 m/s.
%      Expected: thrust_min = 50×2000/3600 = 27.8 N.
%   2. Mode 2: set mission_duration=5 yr, propulsion_time_fraction=0.10.
%      Expected: t_burn_max = 0.1 × 5 × 365.25 × 86400 = 1.577×10⁷ s.
%   3. Mode 3 (sc_type=2 default): no user input, sc_type=2.
%      Expected: t_burn_max = 0.10 × 5 yr in seconds.
%   4. Supply m_prop=0 or c_e=0: verify thrust_min=0 returned without error.
%   5. Supply sc_type=1 (no propulsion): verify thrust_min=0 (mode 3, 0-yr default).
%
% SAFEGUARDS ALREADY IN PLACE:
%   - Early return with thrust_min=0 for NaN/non-positive m_prop or c_e.
%   - sc_type=1 returns t_mission_default_yr=0 → no constraint.
%
% SAFEGUARDS TO ADD (future work):
%   - Warn when thrust_min exceeds the maximum thrust in the reference
%     database for the given technology — the constraint is then unsatisfiable.
%   - Validate that t_burn_max > 0 before dividing (guard against
%     zero propulsion_time_fraction from misconfigured defaults).

  if nargin < 3
    config = struct();
  end

  thrust_min = 0;

  m_prop = data.subsystem_masses.mass_propellant;
  c_e    = data.c_e;

  if isnan(m_prop) || isnan(c_e) || m_prop <= 0 || c_e <= 0
    return;
  end

  I_tot = m_prop * c_e;  % total impulse [N*s]

  % --- Determine maximum allowable burn time ---
  if isfield(case_inputs, 'maneuver_duration_max') ...
      && ~isempty(case_inputs.maneuver_duration_max) ...
      && case_inputs.maneuver_duration_max > 0
    % Mode 1: directly specified maximum maneuver burn time [s]
    t_burn_max = case_inputs.maneuver_duration_max;

  elseif isfield(case_inputs, 'mission_duration') ...
      && ~isempty(case_inputs.mission_duration) ...
      && case_inputs.mission_duration > 0
    % Mode 2: fraction of user-specified total mission duration
    frac = get_propulsion_fraction(case_inputs, config);
    t_mission_s = case_inputs.mission_duration * 365.25 * 86400;  % years -> s
    t_burn_max  = frac * t_mission_s;

  else
    % Mode 3: no user input — apply sc_type-based default mission duration from config.
    % Hard-coded fallbacks match the values in ESDC_Simulation_parameters:
    %   sc_type 1 (No Propulsion): 0   -> no constraint applied
    %   sc_type 2 (LEO):           5 yr  (SMAD Table 1-3)
    %   sc_type 3 (GEO/HEO):      15 yr  (ECSS-E-ST-10-04C)
    %   sc_type 4 (Planetary):    10 yr  (Cassini 13yr, Rosetta/New Horizons 10yr)
    sc_type = determine_sc_type(data);
    key = strcat('sc_type_', num2str(sc_type));
    if isstruct(config) && isfield(config, 'Simulation_parameters') ...
        && isfield(config.Simulation_parameters, 'defaults') ...
        && isfield(config.Simulation_parameters.defaults, 'mission_duration_years') ...
        && isfield(config.Simulation_parameters.defaults.mission_duration_years, key)
      t_mission_default_yr = str2double_safe(config.Simulation_parameters.defaults.mission_duration_years.(key));
      if isnan(t_mission_default_yr) || t_mission_default_yr < 0
        t_mission_default_yr = 0;
      end
    else
      switch sc_type
        case 1;  t_mission_default_yr = 0;
        case 2;  t_mission_default_yr = 5;
        case 3;  t_mission_default_yr = 15;
        case 4;  t_mission_default_yr = 10;
        otherwise; t_mission_default_yr = 5;
      end
    end
    if t_mission_default_yr <= 0
      return;  % sc_type 1 (No Propulsion): no constraint
    end
    frac = get_propulsion_fraction(case_inputs, config);
    t_burn_max = frac * t_mission_default_yr * 365.25 * 86400;
  end

  thrust_min = I_tot / t_burn_max;  % [N]
end


function frac = get_propulsion_fraction(case_inputs, config)
% get_propulsion_fraction — Resolve the propulsion time fraction with fallback priority
%
% Priority order:
%   1. case_inputs.propulsion_time_fraction (user-specified per mission)
%   2. config.Simulation_parameters.defaults.propulsion_time_fraction
%   3. Hard default: 0.10 (SMAD 2011, p.693 — EP duty cycles 5–20 %)
%
% Returns frac in (0, 1].  Negative or NaN values fall back to 0.10.
  if isfield(case_inputs, 'propulsion_time_fraction') ...
      && ~isempty(case_inputs.propulsion_time_fraction) ...
      && case_inputs.propulsion_time_fraction > 0
    frac = case_inputs.propulsion_time_fraction;
  elseif isstruct(config) && isfield(config, 'Simulation_parameters') ...
      && isfield(config.Simulation_parameters, 'defaults') ...
      && isfield(config.Simulation_parameters.defaults, 'propulsion_time_fraction')
    frac = str2double_safe(config.Simulation_parameters.defaults.propulsion_time_fraction);
    if isnan(frac) || frac <= 0; frac = 0.10; end
  else
    frac = 0.10;
  end
end


function v = str2double_safe(x)
% str2double_safe — Convert a value to double regardless of storage type
%
% Handles three common cases produced by xml2struct + typeset_struct:
%   - Already a double (pass-through)
%   - Struct with .Text field (XML value-node pattern)
%   - Plain string / char array
  if isnumeric(x)
    v = x;
  elseif isstruct(x) && isfield(x, 'Text')
    v = str2double(x.Text);
  else
    v = str2double(x);
  end
end
