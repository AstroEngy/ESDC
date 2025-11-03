function [mission_parameters] = read_input_mission_parameter()
    disp('Reading Mission Parameter Input File');
    
    try
        mission_parameters = read_file_auto('Input/ESDC_Input');
        
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