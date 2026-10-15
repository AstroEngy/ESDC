% input_processing — Load and pre-process all ESDC input data
%
% PURPOSE:
%   Reads the three input sources (simulation config, mission parameters,
%   hardware database + DOF), then derives any missing mass/power values by
%   applying SMAD statistical scaling laws and initialises the orbit model.
%   Returns the three data structures needed by the evolver.
%
% INTENT:
%   Centralises all I/O and pre-processing so the evolver receives complete,
%   consistent data structs regardless of which subset of parameters the user
%   provided.  The "adaptive input pre-processing" step makes ESDC robust to
%   partially-specified inputs — users need only supply the parameters they
%   know (total mass, or payload mass, or total power) and the rest are
%   estimated from historical spacecraft statistics (SMAD).
%
% Parameters:  none
% Returns:
%   mission_parameters   (struct): Input case(s) with mission constraints.
%       .Satellite_parameters.input_case{i}: per-case struct containing at
%       least .derived (estimated masses/powers/sc_type) and .orbit (orbit
%       timing parameters).
%   database             (struct): Hardware reference data and scaling lookup
%       tables.  .reference_data holds component catalogues; .DOF holds the
%       mutation space definition.
%   simulation_parameters (struct): Solver configuration (see
%       read_input_simulation_parameter for full field list).
%
% Usage:
%   [input, db_data, config] = input_processing()
%
% HOW TO TEST:
%   1. Call with the default input files and verify that all three returned
%      structs are non-empty and that input.Satellite_parameters.input_case
%      contains at least one cell with a .derived.sc_type field (1–4).
%   2. Provide a minimal input (mass_total only) and verify that all
%      subsystem mass and power fields are populated in .derived.
%   3. Provide payload mass only (no mass_total) and confirm mass_total
%      is estimated via the payload-fraction SMAD path.
%   4. Provide inconsistent inputs (e.g. mass_total AND mass_payload > mass_total)
%      and verify a warning or error is raised.
%   5. Test with orbit_height specified vs omitted and confirm that
%      .orbit.orbit.height is set to the supplied or default value.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that derived.mass_total > 0 and is not NaN before returning.
%   - Check that at least one of mass_total, mass_payload, power_total is
%     provided in each input case; raise a clear error otherwise.
%   - Confirm that sc_type is in {1,2,3,4} after determination.
function [mission_parameters database simulation_parameters]= input_processing()

 % ---- Step 1: Read simulation settings first (provides prefer_xml flag) ---
    [simulation_parameters] = read_input_simulation_parameter();

    % Extract prefer_xml flag (default false if not set)
    prefer_xml = false;
    if isfield(simulation_parameters, 'Simulation_parameters') && ...
       isfield(simulation_parameters.Simulation_parameters, 'io') && ...
       isfield(simulation_parameters.Simulation_parameters.io, 'prefer_xml')
      prefer_xml = logical(simulation_parameters.Simulation_parameters.io.prefer_xml);
    end
    if prefer_xml
      disp('IO mode: XML preferred (YAML used as fallback)');
    end

    % ---- Step 2: Read mission design constraints ----------------------------
    [mission_parameters] =  read_input_mission_parameter(prefer_xml);

    % ---- Step 3: Read hardware reference database and DOF ------------------
    [database]    =  read_reference_data(prefer_xml);
    database.DOF  =  read_DOF(prefer_xml);

    disp(' ')
    disp('Input Reading complete')
    disp(' ')

    disp('Adaptive Input Preprocessing')
    disp(' ')

    % ---- Step 4: Derive missing parameters for each input case -------------
    % system_completion_estimation fills in any subsystem masses and powers
    % that were not directly provided, using SMAD statistical fractions.
    % orbit_initialize computes orbit timing from height or sc_type default.
    %
    % TODO: extend loop to handle multiple cases in one simulation run.
    input_cases = mission_parameters.Satellite_parameters.input_case;
    for i= 1:size(input_cases,2)
      mission_parameters.Satellite_parameters.input_case{i}(1,1).derived = system_completion_estimation(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
      mission_parameters.Satellite_parameters.input_case{i}(1,1).orbit = orbit_initialize(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
    end

end


% orbit_initialize — Compute orbital timing parameters for the input case
%
% PURPOSE:
%   Given the mission input, determines the orbit height (from the input
%   directly or from sc_type defaults) and calls orbit_parameters_Earth()
%   to compute orbit period, sun/shadow time fractions and other timing
%   data needed by the power system analysis.
%
% Parameters:
%   mission_inputs (struct): one input_case, may contain .orbit_height [km].
%   sim            (struct): simulation_parameters with defaults.orbit.*
%
% Returns:
%   mission_parameters (struct): .orbit field containing the orbit timing
%       struct from orbit_parameters_Earth().
%
% HOW TO TEST:
%   1. Provide orbit_height=500 (LEO); confirm orbit period ≈ 5675 s.
%   2. Omit orbit_height with sc_type=2 (LEO); confirm default LEO height
%      is used from sim.Simulation_parameters.defaults.orbit.Low_Earth.
%   3. Provide orbit_height below orbit_min; confirm orbit_min is used.
function [mission_parameters] = orbit_initialize(mission_inputs, sim)
  mission_parameters = struct;
  if isfield(mission_inputs,'orbit_height')                                                                  % case for given orbit height
    if (mission_inputs.orbit_height > sim.Simulation_parameters.defaults.orbit_min)                           % compare if min is correct
      height = mission_inputs.orbit_height;
    else
      % Clamp to minimum allowed orbit height (from simulation defaults)
      height = sim.Simulation_parameters.defaults.orbit_min;
    end
    mission_parameters.orbit =  orbit_parameters_Earth(height);
  else                                                                                                      % case for unknown orbit height, but use default from orbit type (no prop, LEO, GEO, probe)
    % Select default orbit height based on sc_type classification
    if mission_inputs.derived.sc_type == 1
      height = sim.Simulation_parameters.defaults.orbit.no_propulsion;
    elseif mission_inputs.derived.sc_type == 2
      height = sim.Simulation_parameters.defaults.orbit.Low_Earth;
    elseif mission_inputs.derived.sc_type == 3
      height = sim.Simulation_parameters.defaults.orbit.High_Earth;
    else
      height = sim.Simulation_parameters.defaults.orbit_min;
    end           
    mission_parameters.orbit =  orbit_parameters_Earth(height);    % missing case for space probe
  end
  %disp(height)
  %disp(mission_parameters)
  % if not, do estimate by orbit type bla 
  
endfunction
