% read_input_mission_parameter — Load the spacecraft mission design constraints
%
% PURPOSE:
%   Reads Input/ESDC_Input (YAML or XML) and returns the mission parameters
%   that define what the spacecraft must do: total mass, delta-v, power,
%   orbit height, mission duration, payload requirements, thrust_mode etc.
%   These drive every design decision in the evolver.
%
% INTENT:
%   Separates the "what the spacecraft must do" data from both the solver
%   configuration and the hardware database.  Users change their spacecraft
%   design problem by editing the input file path — no code changes needed.
%
% INPUT FILE PATH RESOLUTION (Priority order):
%   1. Environment variable ESDC_INPUT_PATH (highest priority)
%      Set externally: setenv('ESDC_INPUT_PATH', 'Input/ESDC_Input_LEO_300kg_Arcjet')
%      Ideal for CI/CD pipelines and batch processing
%
%   2. ESDC_Simulation_parameters.yaml: io.input_file_path section
%      Edit this file to change the default input for interactive work
%      Examples:
%        input_file_path: 'Input/ESDC_Input_LEO_650ms_1500W'
%        input_file_path: 'Input/ESDC_Input_LEO_300kg_Arcjet'
%
%   3. Hardcoded fallback: 'Input/ESDC_Input_LEO_650ms_1500W'
%      Used only if both environment variable and config file are unavailable
%
% Parameters:
%   prefer_xml (logical, optional, default false): When true, tries the XML
%              file first. Can also be set in ESDC_Simulation_parameters.yaml
%
% Returns:
%   mission_parameters (struct): Parsed input file.
%       .Satellite_parameters.input_case (cell array): One cell per case.
%       Each cell contains a struct with fields from the input YAML, e.g.:
%         .mass_total, .deltav, .propulsion_power, .orbit_height,
%         .mission_duration, .thrust_mode, .mass_payload, .power_payload,
%         .sc_type (optional explicit override)
%
% Usage:
%   mission_parameters = read_input_mission_parameter()
%   mission_parameters = read_input_mission_parameter(true)  % prefer XML
%   % With environment variable override:
%   setenv('ESDC_INPUT_PATH', 'Input/ESDC_Input_LEO_300kg_Arcjet')
%   mission_parameters = read_input_mission_parameter()
%
% HOW TO TEST:
%   1. Load the default input and verify input_case is a cell array with at
%      least one entry containing a .mass_total field (or .mass_payload if
%      in payload-only mode).
%   2. Change input_file_path in ESDC_Simulation_parameters.yaml to one of
%      the example files and verify the returned struct matches the expected
%      sc_type and mass range in the comments below.
%   3. Set ESDC_INPUT_PATH environment variable and verify it takes priority
%      over the config file setting.
%   4. Corrupt Input/ESDC_Input.yaml; confirm the error
%      "ERROR: No input definition file: ..." is raised.
%   5. Supply a single input_case in XML and verify it is wrapped in a cell
%      array (not left as a bare struct) so downstream indexing with {i} works.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that each input_case contains at least one of mass_total,
%     mass_payload, or power_total to allow system_completion_estimation
%     to work.
%   - Warn when mass_payload > mass_total (infeasible input).
%
% EXAMPLE INPUT FILES (for reference):
%   No Propulsion (sc_type=1, explicit):
%     'Input/ESDC_Input_sc1_no_prop_low_mass'   % 3100 kg
%     'Input/ESDC_Input_sc1_no_prop_high_mass'  % 8900 kg
%   LEO (sc_type=2 via orbit_height=500 km):
%     'Input/ESDC_Input_sc2_leo_low_mass_high_thrust'   % 4000 kg, high-thrust
%     'Input/ESDC_Input_sc2_leo_high_mass_low_thrust'   % 12000 kg, low-thrust
%   HEO/GEO (sc_type=3 via orbit_height=35786 km):
%     'Input/ESDC_Input_sc3_heo_low_mass'   % 1800 kg
%     'Input/ESDC_Input_sc3_heo_high_mass'  % 4400 kg
%   Planetary (sc_type=4, explicit):
%     'Input/ESDC_Input_sc4_planetary_low_mass'   % 1700 kg
%     'Input/ESDC_Input_sc4_planetary_high_mass'  % 4300 kg
function [mission_parameters] = read_input_mission_parameter(prefer_xml)
  if nargin < 1; prefer_xml = false; end
  
  % ---- Step 1: Read simulation parameters to get io configuration ----
  % (This provides both prefer_xml and input_file_path settings)
  try
    simulation_parameters = read_input_simulation_parameter();
  catch
    % If simulation parameters cannot be read, continue with defaults
    simulation_parameters = struct();
  end
  
  % ---- Step 2: Resolve input file path with priority:
  %     1. Environment variable ESDC_INPUT_PATH (highest priority)
  %     2. ESDC_Simulation_parameters.io.input_file_path (config file)
  %     3. Default fallback
  input_path = get_input_file_path(simulation_parameters);
  
  % ---- Step 3: Extract prefer_xml flag if not already provided
  if ~prefer_xml && isfield(simulation_parameters, 'Simulation_parameters') && ...
     isfield(simulation_parameters.Simulation_parameters, 'io') && ...
     isfield(simulation_parameters.Simulation_parameters.io, 'prefer_xml')
    prefer_xml = logical(simulation_parameters.Simulation_parameters.io.prefer_xml);
  end

    disp(['Reading Mission Parameter Input File: ' input_path]);
    
    try
        mission_parameters = read_file_auto(input_path, prefer_xml);
        
        % Handle single input_case (works for both XML and YAML)
        if isfield(mission_parameters, 'Satellite_parameters') && ...
           isfield(mission_parameters.Satellite_parameters, 'input_case')
            
            if isstruct(mission_parameters.Satellite_parameters.input_case)
                % Convert single struct to cell array
                structdata = mission_parameters.Satellite_parameters.input_case;
                mission_parameters.Satellite_parameters.input_case = {structdata};
            end
        end
        
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        error('ERROR: No input definition file: %s', err.message);
    end
end