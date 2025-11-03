function [simulation_parameters] = read_input_simulation_parameter()
    disp('Reading Simulation Parameter Input File');
    try
        simulation_parameters = read_file_auto('Input/ESDC_Simulation_parameters');
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        error('ERROR: No Simulation Parameter Input File: %s', err.message);
    end
end


