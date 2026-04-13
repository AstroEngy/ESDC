function [DOF] = read_DOF(prefer_xml)
    if nargin < 1; prefer_xml = false; end
    disp('Reading Degrees of Freedom Input File');
    
    try
        DOF = read_file_auto('Database/model_DOF', prefer_xml);
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        disp('No Degrees of Freedom Input File');
        DOF = struct();
    end
end