function [mission_parameters] = read_input_mission_parameter(prefer_xml)
  if nargin < 1; prefer_xml = false; end
% Select the mission parameter input file to use.
% Uncomment exactly one line. All paths are relative to the ESDC root.
%
%   Default input (active):
    input_path = 'Input/ESDC_Input';
%   Example files — No Propulsion (sc_type=1, explicit):
%   No Propulsion DB range: min=125 kg, max=11866 kg.
%   low mass = lower quartile: 125 + 0.25*(11866-125) = 3100 kg
%   high mass = upper quartile: 11866 - 0.25*(11866-125) = 8900 kg
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc1_no_prop_low_mass';   % 3100 kg,  30 m/s, 2300 W, 3 yr, frac=0.10
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc1_no_prop_high_mass';  % 8900 kg,  30 m/s, 1800 W, 5 yr, frac=0.10
%
%   Example files — LEO (sc_type=2 via orbit_height=500 km):
%   LEO database range: min=25 kg, max=16221 kg.
%   low mass = lower quartile: 25 + 0.25*(16221-25) = 4000 kg
%   high mass = upper quartile: 16221 - 0.25*(16221-25) = 12000 kg
%   thrust_mode='high': evolver restricted to high-thrust/low-Isp technologies (chemical, HET)
%   thrust_mode='low':  evolver restricted to low-thrust/high-Isp EP (gridded-ion, FEEP, electrospray)
%   thrust_mode='high' + maneuver_duration_max drives thrust_min ~11 N; EP/arcjet (<3.4 N) hard-rejected, chemical wins
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_low_mass_high_thrust';   % 4000 kg, thrust_mode=high, 400 m/s, 20000 W, 2 yr, frac=0.01
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_low_mass_low_thrust';    % 4000 kg, thrust_mode=low,  200 m/s,  4000 W, 7 yr, frac=0.15
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_high_mass_high_thrust';  % 12000 kg, thrust_mode=high, 400 m/s, 60000 W, 2 yr, frac=0.01
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_high_mass_low_thrust';   % 12000 kg, thrust_mode=low,  200 m/s, 12000 W, 7 yr, frac=0.15
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_low_mass_chemical';      % 4000 kg, thrust_mode=high, maneuver_max=72000 s (~11 N), 200 m/s, 2000 W, 5 yr
%
%   Example files — HEO/GEO (sc_type=3 via orbit_height=35786 km):
%   High Earth DB range: min=458 kg, max=5698 kg.
%   low mass = lower quartile: 458 + 0.25*(5698-458) = 1800 kg
%   high mass = upper quartile: 5698 - 0.25*(5698-458) = 4400 kg
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc3_heo_low_mass';   % 1800 kg, 3000 m/s, 18000 W, 15 yr, frac=0.10
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc3_heo_high_mass';  % 4400 kg, 3000 m/s, 13000 W, 15 yr, frac=0.10
%
%   Example files — Planetary (sc_type=4, explicit):
%   Planetary DB range: min=385 kg, max=5565 kg.
%   low mass = lower quartile: 385 + 0.25*(5565-385) = 1700 kg
%   high mass = upper quartile: 5565 - 0.25*(5565-385) = 4300 kg
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc4_planetary_low_mass';   % 1700 kg, 5000 m/s, 25000 W, 10 yr, frac=0.10
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc4_planetary_high_mass';  % 4300 kg, 5000 m/s, 26000 W, 10 yr, frac=0.10
%   input_path = 'Documentation/Example Files/Input/ESDC_Input';
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_all_fields_template_revision_v2';
%
%   Example files — Payload mass and power only (no mass_total), one per orbit type:
%   mass_total is NOT provided; the evolver derives total mass via payload mass fraction scaling.
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc1_no_prop_payload_only';   % sc_type=1,  750 kg payload,  700 W payload,  30 m/s,  2300 W,  3 yr
   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_payload_only';       % sc_type=2, 1200 kg payload, 6000 W payload, 300 m/s,  8000 W,  5 yr, frac=0.05
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc3_heo_payload_only';       % sc_type=3,  550 kg payload, 5500 W payload, 3000 m/s, 18000 W, 15 yr, frac=0.10
%   input_path = 'Documentation/Example Files/Input/ESDC_Input_sc4_planetary_payload_only'; % sc_type=4,  500 kg payload, 7500 W payload, 5000 m/s, 25000 W, 10 yr, frac=0.10

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