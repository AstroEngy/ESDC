function [data] = read_file_auto(base_path, prefer_xml)
    % Automatically read either YAML or XML file.
    % Usage:
    %   data = read_file_auto('Input/ESDC_Input');
    %   data = read_file_auto('Database/model_DOF');
    %   data = read_file_auto('Database/model_DOF', true);  % force XML
    %
    % prefer_xml (optional, default false): when true, XML is tried first
    % and YAML is only used as fallback.  Set via
    % Simulation_parameters.io.prefer_xml in ESDC_Simulation_parameters.

    if nargin < 2
      prefer_xml = false;
    end

    yaml_file = [base_path '.yaml'];
    xml_file  = [base_path '.xml'];

    if prefer_xml
      first_file  = xml_file;
      second_file = yaml_file;
      read_first  = @() read_xml(xml_file);
      read_second = @() esdc_yaml.read(yaml_file);
    else
      first_file  = yaml_file;
      second_file = xml_file;
      read_first  = @() esdc_yaml.read(yaml_file);
      read_second = @() read_xml(xml_file);
    end

    if exist(first_file, 'file')
      data = read_first();
    elseif exist(second_file, 'file')
      data = read_second();
    else
      error('ESDC:FileNotFound', 'Neither %s nor %s found', yaml_file, xml_file);
    end
end

function data = read_xml(xml_file)
  data = xml2struct(xml_file);
  data = typeset_struct(data);
end