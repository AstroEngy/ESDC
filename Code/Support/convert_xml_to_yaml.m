% ==================================================================
% convert_xml_to_yaml.m - Convert ESDC XML files to YAML
% Author: AstroEngy
% Date: 2025-10-30
% ==================================================================

function convert_xml_to_yaml(xml_file, yaml_file)
    % Convert XML file to YAML format
    %
    % Usage:
    %   convert_xml_to_yaml('Input/ESDC_Input.xml', 'Input/ESDC_Input.yaml');
    %   convert_xml_to_yaml('Database/ESDC_Reference_Data_Systems.xml', ...
    %                       'Database/ESDC_Reference_Data_Systems.yaml');
    
    fprintf('\n=== XML to YAML Converter ===\n\n');
    fprintf('Input:  %s\n', xml_file);
    fprintf('Output: %s\n\n', yaml_file);
    
    % Check if xml2struct is available
    if ~exist('xml2struct', 'file')
        error('xml2struct function not found. Please ensure it is in your path.');
    end
    
    % Read XML
    fprintf('Reading XML...\n');
    xml_data = xml2struct(xml_file);
    
    % Convert structure
    fprintf('Converting structure...\n');
    yaml_data = convert_structure(xml_data);
    
    % Write YAML
    fprintf('Writing YAML...\n');
    esdc_yaml.write(yaml_file, yaml_data);
    
    fprintf('\n✓ Conversion complete!\n\n');
    
    % Show file sizes
    xml_info = dir(xml_file);
    yaml_info = dir(yaml_file);
    
    fprintf('File sizes:\n');
    fprintf('  XML:  %d bytes\n', xml_info.bytes);
    fprintf('  YAML: %d bytes\n', yaml_info.bytes);
    fprintf('  Reduction: %.1f%%\n\n', ...
            100 * (1 - yaml_info.bytes / xml_info.bytes));
end

function yaml_struct = convert_structure(xml_struct)
    % Recursively convert XML structure to clean YAML structure
    
    yaml_struct = struct();
    
    if ~isstruct(xml_struct)
        yaml_struct = xml_struct;
        return;
    end
    
    fields = fieldnames(xml_struct);
    
    for i = 1:length(fields)
        field = fields{i};
        value = xml_struct.(field);
        
        % Skip XML attributes (we'll handle them differently)
        if strcmp(field, 'Attributes')
            continue;
        end
        
        % Handle cell arrays (multiple elements with same name)
        if iscell(value)
            yaml_struct.(field) = {};
            for j = 1:length(value)
                yaml_struct.(field){j} = convert_element(value{j});
            end
        else
            yaml_struct.(field) = convert_element(value);
        end
    end
end

function converted = convert_element(element)
    % Convert a single XML element
    
    if ~isstruct(element)
        converted = element;
        return;
    end
    
    % Check if this is a simple text node
    if isfield(element, 'Text') && length(fieldnames(element)) == 1
        converted = parse_text_value(element.Text);
        return;
    end
    
    % Check if has Text and Attributes
    if isfield(element, 'Text') && isfield(element, 'Attributes')
        % Decide whether to keep as simple value or expand
        % For ESDC, we'll simplify to just the value with comments
        converted = parse_text_value(element.Text);
        return;
    end
    
    % Otherwise, recursively convert
    converted = convert_structure(element);
end

function value = parse_text_value(text)
    % Parse text value to appropriate type
    
    if isempty(text)
        value = '';
        return;
    end
    
    % Try to parse as number
    num = str2double(text);
    if ~isnan(num)
        value = num;
        return;
    end
    
    % Check for boolean
    if strcmpi(text, 'true')
        value = true;
        return;
    elseif strcmpi(text, 'false')
        value = false;
        return;
    end
    
    % Default: string
    value = text;
end

function convert_all_xml_files()
    % Batch convert all XML files in ESDC
    
    fprintf('\n=== Batch XML to YAML Conversion ===\n\n');
    
    % List of files to convert
    conversions = {
        'DCEP_IO_Def/Input/ESDC_Input.xml', 'Input/ESDC_Input.yaml';
        'DCEP_IO_Def/Input/ESDC_Simulation_parameters.xml', 'Input/ESDC_Simulation_parameters.yaml';
        'Database/ESDC_Reference_Data_Systems.xml', 'Database/ESDC_Reference_Data_Systems.yaml';
        'Database/ESDC_Reference_Data_Spacecrafts.xml', 'Database/ESDC_Reference_Data_Spacecrafts.yaml';
        'Database/model_DOF.xml', 'Database/model_DOF.yaml';
        'Database/ESDC_variable_attributes.xml', 'Database/ESDC_variable_attributes.yaml'
    };
    
    n_success = 0;
    n_failed = 0;
    
    for i = 1:size(conversions, 1)
        xml_file = conversions{i, 1};
        yaml_file = conversions{i, 2};
        
        if ~exist(xml_file, 'file')
            fprintf('⚠ Skipping (not found): %s\n', xml_file);
            continue;
        end
        
        try
            convert_xml_to_yaml(xml_file, yaml_file);
            n_success = n_success + 1;
        catch err
            fprintf('✗ Failed: %s\n  Error: %s\n\n', xml_file, err.message);
            n_failed = n_failed + 1;
        end
    end
    
    fprintf('=== Summary ===\n');
    fprintf('Successfully converted: %d\n', n_success);
    fprintf('Failed: %d\n\n', n_failed);
end