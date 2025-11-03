function [data] = read_file_auto(base_path)
    % Automatically read either YAML or XML file
    % Usage:
    %   data = read_file_auto('Input/ESDC_Input');
    %   data = read_file_auto('Database/model_DOF');
    
    yaml_file = [base_path '.yaml'];
    xml_file = [base_path '.xml'];
    
    % Prefer YAML if it exists
    if exist(yaml_file, 'file')
        data = esdc_yaml.read(yaml_file);
    elseif exist(xml_file, 'file')
        data = xml2struct(xml_file);
        data = typeset_struct(data);
    else
        error('ESDC:FileNotFound', 'Neither %s nor %s found', yaml_file, xml_file);
    end
end