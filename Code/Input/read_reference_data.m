function [database] = read_reference_data(prefer_xml)
    if nargin < 1; prefer_xml = false; end
    disp('Reading Reference Data Input File');
    database = read_file_auto('Database/ESDC_Reference_Data_Systems', prefer_xml);
    disp('Success');
    disp(' ');
    fflush(stdout);
end