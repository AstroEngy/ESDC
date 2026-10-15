function [mission_parameters database simulation_parameters]= input_processing()
 %InputReading
    % Simulation Parameters — read first so prefer_xml flag is available
    % for all subsequent file reads.
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

    % Mission Parameters
    [mission_parameters] =  read_input_mission_parameter(prefer_xml);
    
    % Database     
    [database]    =  read_reference_data(prefer_xml);
    database.DOF  =  read_DOF(prefer_xml);
    
    disp(' ')
    disp('Input Reading complete')
    disp(' ')
    
    disp('Adaptive Input Preprocessing')
    disp(' ')
    
    % Add derived parameters to input case
    
    %TODO add loop for multiple cases
    input_cases = mission_parameters.Satellite_parameters.input_case;
    for i= 1:size(input_cases,2)
      mission_parameters.Satellite_parameters.input_case{i}(1,1).derived = system_completion_estimation(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
      mission_parameters.Satellite_parameters.input_case{i}(1,1).orbit = orbit_initialize(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
    end
    
    
    %disp(mission_parameters.Satellite_parameters)
end

% system_completion_estimation is now a top-level public function in
% Code/Input/system_completion_estimation.m — see that file for details.


function [mission_parameters] = orbit_initialize(mission_inputs, sim)
  mission_parameters = struct;
  %disp(mission_inputs)
  %disp(sim.Simulation_parameters)
  if isfield(mission_inputs,'orbit_height')                                                                  % case for given orbit height
    if (mission_inputs.orbit_height > sim.Simulation_parameters.defaults.orbit_min)                           % compare if min is correct
      height = mission_inputs.orbit_height;
    else
      height = sim.Simulation_parameters.defaults.orbit_min;
    end
    mission_parameters.orbit =  orbit_parameters_Earth(height);
  else                                                                                                      % case for unknown orbit height, but use default from orbit type (no prop, LEO, GEO, probe)
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
