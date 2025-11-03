% ==================================================================
% esdc_yaml.m - Lightweight YAML parser for ESDC
% Author: AstroEngy
% Date: 2025-10-30
% Compatible with Octave 4.0+
%
% Uses recursive descent parser for robust nested structure handling
% ==================================================================

classdef esdc_yaml
    methods (Static)
        function data = read(filename)
            % Read YAML file and parse to Octave structure
            
            if ~exist(filename, 'file')
                error('ESDC:FileNotFound', 'File not found: %s', filename);
            end
            
            fid = fopen(filename, 'r');
            lines = {};
            while ~feof(fid)
                lines{end+1} = fgetl(fid);
            end
            fclose(fid);
            
            try
                data = esdc_yaml.parse_lines(lines);
            catch err
                error('ESDC:YAMLParseError', ...
                      'Failed to parse YAML file %s:\n%s', filename, err.message);
            end
        end
        
        function write(filename, data, varargin)
            % Write Octave structure to YAML file
            
            p = inputParser();
            addParameter(p, 'indent', 2, @isnumeric);
            addParameter(p, 'header', true, @islogical);
            parse(p, varargin{:});
            
            fid = fopen(filename, 'w');
            
            if p.Results.header
                fprintf(fid, '# ESDC YAML Data File\n');
                fprintf(fid, '# Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
                fprintf(fid, '# Octave %s\n\n', version);
            end
            
            esdc_yaml.write_recursive(fid, data, 0, p.Results.indent);
            fclose(fid);
            
            fprintf('Written: %s\n', filename);
        end
        
        function data = parse_lines(lines)
            % Main entry point - parse all lines
            [data, ~] = esdc_yaml.parse_block(lines, 1, -1);
        end
        
        function [result, next_line] = parse_block(lines, start_line, parent_indent)
            % Parse a block (struct) of YAML
            result = struct();
            i = start_line;
            
            while i <= length(lines)
                line = lines{i};
                trimmed = strtrim(line);
                
                % Skip empty lines and comments
                if isempty(trimmed) || (length(trimmed) > 0 && trimmed(1) == '#')
                    i = i + 1;
                    continue;
                end
                
                indent = esdc_yaml.get_indent_level(line);
                
                % Return if we've dedented back to parent level
                if indent <= parent_indent && parent_indent >= 0
                    next_line = i;
                    return;
                end
                
                % Remove inline comments
                line = esdc_yaml.remove_inline_comment(strtrim(line));
                
                if isempty(strtrim(line))
                    i = i + 1;
                    continue;
                end
                
                % Handle key-value pairs
                if esdc_yaml.str_contains(line, ':')
                    [key, value_str] = esdc_yaml.parse_key_value(line);
                    
                    if isempty(value_str)
                        % Check next line to determine if list or nested struct
                        if i < length(lines)
                            next_line_text = lines{i+1};
                            next_trimmed = strtrim(next_line_text);
                            next_indent = esdc_yaml.get_indent_level(next_line_text);
                            
                            if ~isempty(next_trimmed) && next_trimmed(1) ~= '#' && next_indent > indent
                                if length(next_trimmed) >= 2 && strcmp(next_trimmed(1:2), '- ')
                                    % It's a list
                                    [result.(key), i] = esdc_yaml.parse_list(lines, i+1, indent);
                                else
                                    % It's a nested struct
                                    [result.(key), i] = esdc_yaml.parse_block(lines, i+1, indent);
                                end
                            else
                                % Empty value
                                result.(key) = struct();
                                i = i + 1;
                            end
                        else
                            % End of file
                            result.(key) = struct();
                            i = i + 1;
                        end
                    else
                        % Simple scalar value
                        result.(key) = esdc_yaml.parse_value(value_str);
                        i = i + 1;
                    end
                else
                    % Skip unrecognized lines
                    i = i + 1;
                end
            end
            
            next_line = i;
        end
        
        function [result, next_line] = parse_list(lines, start_line, parent_indent)
            % Parse a list (array) of YAML
            result = {};
            i = start_line;
            
            while i <= length(lines)
                line = lines{i};
                trimmed = strtrim(line);
                
                % Skip empty and comments
                if isempty(trimmed) || (length(trimmed) > 0 && trimmed(1) == '#')
                    i = i + 1;
                    continue;
                end
                
                indent = esdc_yaml.get_indent_level(line);
                
                % Return if dedented
                if indent <= parent_indent
                    next_line = i;
                    return;
                end
                
                line = esdc_yaml.remove_inline_comment(strtrim(line));
                
                if isempty(strtrim(line))
                    i = i + 1;
                    continue;
                end
                
                % List item
                if length(line) >= 2 && strcmp(line(1:2), '- ')
                    item_line = strtrim(line(3:end));
                    
                    if esdc_yaml.str_contains(item_line, ':')
                        % Object in list
                        [item, i] = esdc_yaml.parse_list_object(lines, i, indent);
                        result{end+1} = item;
                    else
                        % Scalar in list
                        result{end+1} = esdc_yaml.parse_value(item_line);
                        i = i + 1;
                    end
                else
                    % Not a list item, return
                    break;
                end
            end
            
            next_line = i;
        end
        
        function [result, next_line] = parse_list_object(lines, start_line, parent_indent)
            % Parse an object within a list
            result = struct();
            line = lines{start_line};
            trimmed_line = strtrim(line);  % Strip whitespace first
            
            % Remove '- ' prefix
            if length(trimmed_line) >= 2 && strcmp(trimmed_line(1:2), '- ')
                item_line = strtrim(trimmed_line(3:end));
            else
                item_line = trimmed_line;
            end
            
            % Parse first key-value on same line as '-'
            [key, value_str] = esdc_yaml.parse_key_value(item_line);
            
            if ~isempty(value_str)
                result.(key) = esdc_yaml.parse_value(value_str);
            else
                result.(key) = struct();
            end
            
            i = start_line + 1;
            
            % The indent level we expect for continuation of this object
            expected_indent = parent_indent + 1;
            
            % Parse additional fields on subsequent lines
            while i <= length(lines)
                line = lines{i};
                trimmed = strtrim(line);
                
                if isempty(trimmed) || (length(trimmed) > 0 && trimmed(1) == '#')
                    i = i + 1;
                    continue;
                end
                
                indent = esdc_yaml.get_indent_level(line);
                
                % Check if this is another list item (dedented to list level)
                if indent == parent_indent && length(trimmed) >= 2 && strcmp(trimmed(1:2), '- ')
                    % This is the next list item, stop parsing this object
                    break;
                end
                
                % Check if we've dedented past this object
                if indent < expected_indent
                    break;
                end
                
                % If indented at exactly the expected level, it's a continuation of this object
                if indent == expected_indent
                    line = esdc_yaml.remove_inline_comment(strtrim(line));
                    
                    if isempty(strtrim(line))
                        i = i + 1;
                        continue;
                    end
                    
                    % Additional key-value pairs in the object
                    if esdc_yaml.str_contains(line, ':')
                        [key2, value_str2] = esdc_yaml.parse_key_value(line);
                        
                        if ~isempty(value_str2)
                            result.(key2) = esdc_yaml.parse_value(value_str2);
                            i = i + 1;
                        else
                            % Nested structure in list object
                            if i < length(lines)
                                next_line_text = lines{i+1};
                                next_indent = esdc_yaml.get_indent_level(next_line_text);
                                
                                if next_indent > indent
                                    [result.(key2), i] = esdc_yaml.parse_block(lines, i+1, indent);
                                else
                                    result.(key2) = struct();
                                    i = i + 1;
                                end
                            else
                                result.(key2) = struct();
                                i = i + 1;
                            end
                        end
                    else
                        i = i + 1;
                    end
                else
                    % Indented more - nested structure
                    break;
                end
            end
            
            next_line = i;
        end
        
        function [key, value] = parse_key_value(line)
            % Parse "key: value" line
            colon_pos = strfind(line, ':');
            if isempty(colon_pos)
                key = '';
                value = '';
                return;
            end
            
            key = strtrim(line(1:colon_pos(1)-1));
            
            if colon_pos(1) == length(line)
                value = '';
            else
                value = strtrim(line(colon_pos(1)+1:end));
            end
        end
        
        function value = parse_value(str)
            % Parse scalar value (number, string, boolean, array)
            str = strtrim(str);
            
            if isempty(str)
                value = '';
                return;
            end
            
            % Inline array: [1, 2, 3]
            if length(str) > 1 && str(1) == '[' && str(end) == ']'
                array_str = str(2:end-1);
                parts = strsplit(array_str, ',');
                value = [];
                is_numeric = true;
                
                for i = 1:length(parts)
                    item = strtrim(parts{i});
                    num = str2double(item);
                    if ~isnan(num)
                        value(end+1) = num;
                    else
                        is_numeric = false;
                        break;
                    end
                end
                
                if ~is_numeric
                    % String array
                    value = {};
                    for i = 1:length(parts)
                        value{i} = strtrim(parts{i});
                    end
                end
                return;
            end
            
            % Remove quotes
            if (length(str) >= 2 && str(1) == '"' && str(end) == '"') || ...
               (length(str) >= 2 && str(1) == '''' && str(end) == '''')
                value = str(2:end-1);
                return;
            end
            
            % Try number
            num = str2double(str);
            if ~isnan(num)
                value = num;
                return;
            end
            
            % Boolean
            if strcmpi(str, 'true')
                value = true;
                return;
            elseif strcmpi(str, 'false')
                value = false;
                return;
            end
            
            % Null
            if strcmpi(str, 'null') || strcmpi(str, '~')
                value = [];
                return;
            end
            
            % String
            value = str;
        end
        
        function level = get_indent_level(line)
            % Count leading spaces (assuming 2-space indent)
            level = 0;
            for i = 1:length(line)
                if line(i) == ' '
                    level = level + 1;
                else
                    break;
                end
            end
            level = floor(level / 2);
        end
        
        function line = remove_inline_comment(line)
            % Remove # comments (but not inside strings)
            in_string = false;
            quote_char = '';
            
            for i = 1:length(line)
                c = line(i);
                
                if (c == '"' || c == '''') && (i == 1 || line(i-1) ~= '\')
                    if ~in_string
                        in_string = true;
                        quote_char = c;
                    elseif c == quote_char
                        in_string = false;
                    end
                end
                
                if c == '#' && ~in_string
                    line = strtrim(line(1:i-1));
                    return;
                end
            end
        end
        
        function result = str_contains(str, pattern)
            % Compatible alternative to contains() for Octave 4.x
            result = ~isempty(strfind(str, pattern));
        end
        
        function write_recursive(fid, data, level, indent_size)
            % Recursively write structure to YAML
            indent = repmat(' ', 1, level * indent_size);
            
            if isstruct(data)
                fields = fieldnames(data);
                
                for i = 1:length(fields)
                    key = fields{i};
                    value = data.(key);
                    
                    fprintf(fid, '%s%s:', indent, key);
                    
                    if isstruct(value)
                        fprintf(fid, '\n');
                        esdc_yaml.write_recursive(fid, value, level + 1, indent_size);
                    elseif iscell(value)
                        fprintf(fid, '\n');
                        esdc_yaml.write_list(fid, value, level + 1, indent_size);
                    else
                        fprintf(fid, ' ');
                        esdc_yaml.write_value(fid, value);
                        fprintf(fid, '\n');
                    end
                end
            end
        end
        
        function write_list(fid, list, level, indent_size)
            % Write array/list
            indent = repmat(' ', 1, level * indent_size);
            
            for i = 1:length(list)
                item = list{i};
                fprintf(fid, '%s- ', indent);
                
                if isstruct(item)
                    fields = fieldnames(item);
                    if ~isempty(fields)
                        first_key = fields{1};
                        first_val = item.(first_key);
                        fprintf(fid, '%s:', first_key);
                        
                        if isstruct(first_val) || iscell(first_val)
                            fprintf(fid, '\n');
                            esdc_yaml.write_recursive(fid, first_val, level + 1, indent_size);
                        else
                            fprintf(fid, ' ');
                            esdc_yaml.write_value(fid, first_val);
                            fprintf(fid, '\n');
                        end
                        
                        for j = 2:length(fields)
                            key = fields{j};
                            val = item.(key);
                            fprintf(fid, '%s  %s:', indent, key);
                            
                            if isstruct(val) || iscell(val)
                                fprintf(fid, '\n');
                                esdc_yaml.write_recursive(fid, val, level + 1, indent_size);
                            else
                                fprintf(fid, ' ');
                                esdc_yaml.write_value(fid, val);
                                fprintf(fid, '\n');
                            end
                        end
                    end
                else
                    esdc_yaml.write_value(fid, item);
                    fprintf(fid, '\n');
                end
            end
        end
        
        function write_value(fid, value)
            % Write scalar value
            if ischar(value)
                needs_quotes = esdc_yaml.str_contains(value, ':') || ...
                              esdc_yaml.str_contains(value, '#') || ...
                              esdc_yaml.str_contains(value, '-') || ...
                              esdc_yaml.str_contains(value, '[') || ...
                              esdc_yaml.str_contains(value, '{');
                
                if needs_quotes
                    fprintf(fid, '"%s"', value);
                else
                    fprintf(fid, '%s', value);
                end
            elseif isnumeric(value)
                if isscalar(value)
                    fprintf(fid, '%g', value);
                else
                    fprintf(fid, '[');
                    for i = 1:length(value)
                        fprintf(fid, '%g', value(i));
                        if i < length(value)
                            fprintf(fid, ', ');
                        end
                    end
                    fprintf(fid, ']');
                end
            elseif islogical(value)
                if value
                    fprintf(fid, 'true');
                else
                    fprintf(fid, 'false');
                end
            elseif isempty(value)
                fprintf(fid, 'null');
            end
        end
    end
end