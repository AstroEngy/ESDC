function [spacecraft_parameters] = read_reference_spacecraft_data(prefer_xml)
    if nargin < 1; prefer_xml = false; end
    disp('Reading Spacecraft Reference Database');
    
    try
        spacecraft_parameters = read_file_auto('Database/ESDC_Reference_Data_Spacecrafts', prefer_xml);
        
        % Handle singular entry (works for both XML and YAML)
        if isfield(spacecraft_parameters, 'reference_data_spracecraft') && ...
           isstruct(spacecraft_parameters.reference_data_spracecraft)
            
            structdata = spacecraft_parameters.reference_data_spracecraft;
            spacecraft_parameters.reference_data_spracecraft = {structdata};
        end
        
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        error('ERROR: No spacecraft reference data found: %s', err.message);
    end
end