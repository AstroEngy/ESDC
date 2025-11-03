function [database] = read_reference_data()
    disp('Reading Reference Data Input File');
    database = read_file_auto('Database/ESDC_Reference_Data_Systems');
    disp('Success');
    disp(' ');
    fflush(stdout);
end