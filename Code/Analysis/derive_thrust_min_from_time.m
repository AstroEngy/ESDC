function thrust_min = derive_thrust_min_from_time(data, case_inputs, config)
% Derives the minimum thrust required to complete the propulsion maneuver
% within the user-specified time constraint.
%
% Physical basis:
%   Total impulse from propellant:   I_tot = m_prop * c_e          [N*s]
%   Constant-thrust burn definition: I_tot = F * t_burn             [N*s]
%   =>  F_min = I_tot / t_burn_max = m_prop * c_e / t_burn_max      [N]
%
% Three input modes (checked in priority order):
%   1. maneuver_duration_max [s]  -- directly given maximum burn time
%   2. mission_duration [years] combined with propulsion_time_fraction [-]:
%        t_burn_max = propulsion_time_fraction * mission_duration_in_seconds
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
% Returns propulsion_time_fraction: user input > config default > hard default 0.10
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
  if isnumeric(x)
    v = x;
  elseif isstruct(x) && isfield(x, 'Text')
    v = str2double(x.Text);
  else
    v = str2double(x);
  end
end
