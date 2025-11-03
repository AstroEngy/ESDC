function [DOF] = read_DOF()
    disp('Reading Degrees of Freedom Input File');
    
    try
        DOF = read_file_auto('Database/model_DOF');
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        disp('No Degrees of Freedom Input File');
        DOF = struct();
    end
end