% ==================================================================
% convert_xml_to_yaml.m - Convert ESDC XML files to YAML
% Author: AstroEngy / CoPilot in semi Agentic Mode
% Date: 2025-10-30
%
% Converts XML files to YAML format, placing them in the same
% directory as the source XML file.
% ==================================================================

function convert_xml_to_yaml(xml_file, yaml_file)
    % Convert XML file to YAML format
    %
    % Usage:
    %   convert_xml_to_yaml('Database/file.xml', 'Database/file.yaml');
    %
    % Or use auto-naming:
    %   convert_xml_to_yaml('Database/file.xml');  % Creates Database/file.yaml
    
    fprintf('\n=== XML to YAML Converter ===\n\n');
    
    % Auto-generate YAML filename if not provided
    if nargin < 2
        [filepath, name, ~] = fileparts(xml_file);
        yaml_file = fullfile(filepath, [name '.yaml']);
    end
    
    fprintf('Input:  %s\n', xml_file);
    fprintf('Output: %s\n\n', yaml_file);
    
    % Check if xml2struct is available
    if ~exist('xml2struct', 'file')
        error('xml2struct function not found. Please ensure it is in your path.');
    end
    
    % Check if input file exists
    if ~exist(xml_file, 'file')
        error('Input XML file not found: %s', xml_file);
    end
    
    % Read XML
    fprintf('Reading XML...\n');
    try
        xml_data = xml2struct(xml_file);
    catch err
        error('Failed to parse XML file: %s\n%s', xml_file, err.message);
    end
    
    % Convert structure
    fprintf('Converting structure...\n');
    yaml_data = convert_structure(xml_data);
    
    % Ensure output directory exists
    [out_dir, ~, ~] = fileparts(yaml_file);
    if ~isempty(out_dir) && ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    
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
    
    if yaml_info.bytes < xml_info.bytes
        reduction = 100 * (1 - yaml_info.bytes / xml_info.bytes);
        fprintf('  Size reduction: %.1f%%\n\n', reduction);
    else
        increase = 100 * (yaml_info.bytes / xml_info.bytes - 1);
        fprintf('  Size increase: %.1f%%\n\n', increase);
    end
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
        % For ESDC, we'll simplify to just the value
        converted = parse_text_value(element.Text);
        return;
    end
    
    % Otherwise, recursively convert
    converted = convert_structure(element);
end

function value = parse_text_value(text)
    % Parse text value to appropriate type (Octave-compatible)
    if isempty(text)
        value = '';
        return;
    end

    % Convert any Java string objects to char
    if isobject(text) && ismethod(text, 'toCharArray')
        text = char(text);
    end

    % Collapse multi-line strings: replace newlines/tabs with spaces
    % (XML source fields sometimes contain embedded newlines)
    text = strrep(text, sprintf('\r\n'), ' ');
    text = strrep(text, sprintf('\n'), ' ');
    text = strrep(text, sprintf('\r'), ' ');
    text = strrep(text, sprintf('\t'), ' ');

    % Collapse multiple spaces into a single space
    while ~isempty(strfind(text, '  '))
        text = strrep(text, '  ', ' ');
    end
    text = strtrim(text);

    % Try to parse as number
    num = str2double(text);
    if ~isnan(num)
        value = num;
        return;
    end

    % Boolean
    if strcmpi(text, 'true')
        value = true;
        return;
    elseif strcmpi(text, 'false')
        value = false;
        return;
    end

    % Null markers
    if strcmpi(text, 'null') || strcmp(text, '~')
        value = [];
        return;
    end

    % Default: string
    value = text;
end
