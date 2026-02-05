function [] = update_generic_spacecraft_system_scaling_a_to_b(data, orbit_type, field_x, field_y, debug_flag)
    % Update generic spacecraft system scaling data from parameter A to parameter B
    %
    % Inputs:
    %   data        - Array of spacecraft system data (cell array or struct array)
    %   orbit_type  - String specifying orbit type to filter (e.g., 'LEO', 'GEO')
    %   field_x     - String name of independent parameter field (e.g., 'mass')
    %   field_y     - String name of dependent parameter field (e.g., 'power')
    %   debug_flag  - Optional flag (1 = enable debug output, 0 = disable, default: 0)
    %
    % Output:
    %   Writes CSV file to Database/Scaling/ directory
    
    % Set default debug flag if not provided
    if nargin < 5
        debug_flag = 0;
    end
    
    % Define output path for scaling database
    scaling_path = "Database/Scaling/";
    
    % Validate inputs
    if isempty(data)
        if debug_flag
            fprintf('WARNING: Empty data array provided\n');
        end
        return;
    end
    
    if debug_flag
        fprintf('\n=== DEBUG: update_generic_spacecraft_system_scaling_a_to_b ===\n');
        fprintf('Processing %d spacecraft entries\n', numel(data));
        fprintf('Data type: %s\n', class(data));
        if isnumeric(orbit_type)
            fprintf('Orbit type filter: %d (numeric)\n', orbit_type);
        else
            fprintf('Orbit type filter: %s (string)\n', orbit_type);
        end
        fprintf('X parameter: %s\n', field_x);
        fprintf('Y parameter: %s\n', field_y);
        fprintf('============================================\n\n');
    end
    
    % Initialize data collection arrays
    x_values = [];
    y_values = [];
    spacecraft_names = {};
    matched_count = 0;
    skipped_count = 0;
    
    % Iterate through all spacecraft data entries
    for i = 1:numel(data)
        % Get reference to current data entry (handle both cell and struct)
        if iscell(data)
            data_entry = data{i};
        else
            data_entry = data(i);
        end
        
        % Check required fields
        has_orbit_type = isfield(data_entry, 'orbit_type');
        has_x_field = isfield(data_entry, field_x);
        has_y_field = isfield(data_entry, field_y);
        
        if ~has_orbit_type
            skipped_count = skipped_count + 1;
            if debug_flag && skipped_count <= 3
                fprintf('  [Skip %d] Entry %d: missing orbit_type field\n', skipped_count, i);
            end
            continue;
        end
        
        % Check orbit type match (handle both numeric and string)
        if isnumeric(data_entry.orbit_type) && isnumeric(orbit_type)
            orbit_match = (data_entry.orbit_type == orbit_type);
        elseif isnumeric(data_entry.orbit_type) && ischar(orbit_type)
            orbit_match = strcmp(num2str(data_entry.orbit_type), orbit_type);
        elseif ischar(data_entry.orbit_type) && isnumeric(orbit_type)
            orbit_match = strcmp(data_entry.orbit_type, num2str(orbit_type));
        else
            orbit_match = strcmp(data_entry.orbit_type, orbit_type);
        end
        
        % Check for non-empty values
        x_nonempty = has_x_field && ~isempty(data_entry.(field_x));
        y_nonempty = has_y_field && ~isempty(data_entry.(field_y));
        
        % Include data point if all conditions are met
        if orbit_match && x_nonempty && y_nonempty
            % Check if values are numeric
            x_value = data_entry.(field_x);
            y_value = data_entry.(field_y);
            
            x_is_numeric = isnumeric(x_value);
            y_is_numeric = isnumeric(y_value);
            
            % Skip if non-numeric
            if ~x_is_numeric || ~y_is_numeric
                skipped_count = skipped_count + 1;
                if debug_flag && skipped_count <= 3
                    fprintf('  [Skip %d] Entry %d: Non-numeric field(s) - %s=%s, %s=%s\n', ...
                            skipped_count, i, field_x, class(x_value), field_y, class(y_value));
                end
                continue;
            end
            
            % Check for size mismatch
            if numel(x_value) ~= numel(y_value)
                skipped_count = skipped_count + 1;
                if debug_flag
                    fprintf('  [Skip %d] Entry %d: Size mismatch - %s has %d elements, %s has %d elements\n', ...
                            skipped_count, i, field_x, numel(x_value), field_y, numel(y_value));
                end
                continue;
            end
            
            matched_count = matched_count + 1;
            
            % Extract values
            x_values = [x_values x_value(:)'];  % Ensure row vector
            y_values = [y_values y_value(:)'];  % Ensure row vector
            
            % Extract spacecraft name if available
            if isfield(data_entry, "name")
                if iscell(data_entry.name)
                    spacecraft_names{1, numel(x_values)} = data_entry.name{1};
                else
                    spacecraft_names{1, numel(x_values)} = data_entry.name;
                end
            else
                spacecraft_names{1, numel(x_values)} = sprintf('Unnamed_%d', i);
            end
            
            if debug_flag && matched_count <= 10
                fprintf('  [%d] Match: %s, %s=%.4g, %s=%.4g\n', ...
                        matched_count, spacecraft_names{end}, ...
                        field_x, x_values(end), field_y, y_values(end));
            end
        else
            skipped_count = skipped_count + 1;
            
            if debug_flag && skipped_count <= 3
                fprintf('  [Skip %d] Entry %d: orbit=%s (match=%d), has_%s=%d (nonempty=%d), has_%s=%d (nonempty=%d)\n', ...
                        skipped_count, i, ...
                        data_entry.orbit_type, orbit_match, ...
                        field_x, has_x_field, x_nonempty, ...
                        field_y, has_y_field, y_nonempty);
            end
        end
    end
    
    % Generate output filename
    % Convert orbit_type to string for filename
    if isnumeric(orbit_type)
        orbit_type_str = num2str(orbit_type);
    else
        orbit_type_str = orbit_type;
    end
    filename = strcat(scaling_path, "scaling_spacecraft_", orbit_type_str, ...
                     "_parameter_", field_x, "_to_", field_y, ".csv");
    
    % Write data to file if valid data points were found
    if numel(x_values) > 0 && numel(y_values) > 0
        if debug_flag
            fprintf('\n--- Writing Results ---\n');
            fprintf('Total matched entries: %d\n', matched_count);
            fprintf('Total skipped entries: %d\n', skipped_count);
            fprintf('Output file: %s\n', filename);
            fprintf('Data range: %s [%.4g to %.4g], %s [%.4g to %.4g]\n', ...
                    field_x, min(x_values), max(x_values), ...
                    field_y, min(y_values), max(y_values));
        end
        
        % Write to CSV file (padbit=0 means no padding)
        write_selected_data_to_file(x_values, y_values, filename, 0);
        
        if debug_flag
            fprintf('File written successfully!\n');
            fprintf('=== END DEBUG ===\n\n');
        end
    else
        if debug_flag
            fprintf('\nWARNING: No valid data points found!\n');
            fprintf('Total entries processed: %d\n', numel(data));
            fprintf('Matched entries: %d\n', matched_count);
            fprintf('Skipped entries: %d\n', skipped_count);
            fprintf('=== END DEBUG ===\n\n');
        else
            warning('update_generic_spacecraft_system_scaling_a_to_b:noData', ...
                    'No valid data points found for orbit_type=%s, %s to %s', ...
                    orbit_type, field_x, field_y);
        end
    end
end