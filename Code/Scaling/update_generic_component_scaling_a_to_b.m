function [] = update_generic_component_scaling_a_to_b(db_data, system_type, technology_type, component_type, field_x, field_y, varargin)
    % Update generic component scaling data from parameter A to parameter B
    %
    % Inputs:
    %   db_data         - Database structure containing reference data
    %   system_type     - String specifying system type (e.g., 'propulsion_system')
    %   technology_type - String specifying technology type (e.g., 'electric_propulsion')
    %   component_type  - String specifying component type (e.g., 'PPU', 'thruster')
    %   field_x         - String name of independent parameter field (e.g., 'mass')
    %   field_y         - String name of dependent parameter field (e.g., 'power')
    %   varargin        - Optional additional dimension field (e.g., 'propellant')
    %                     If provided, creates separate scaling files for each unique value
    %
    % Output:
    %   Writes CSV file(s) to Database/Scaling/ directory
    
    % Parse optional debug flag from varargin
    debug_flag = 0;
    add_dim = '';
    
    if nargin >= 7
        if ischar(varargin{1}) || isstring(varargin{1})
            add_dim = char(varargin{1});
        end
        if nargin >= 8 && isnumeric(varargin{2})
            debug_flag = varargin{2};
        end
    end
    
    % Exclusion of certain y-fields that cannot be sorted (non-numeric)
    excluded_fields = {'type', 'name', 'source', 'propellant'};
    if any(strcmp(field_y, excluded_fields))
        if debug_flag
            fprintf('INFO: Skipping non-numeric field_y: %s\n', field_y);
        end
        return;
    end
    
    % Skip if x and y fields are identical
    if strcmp(field_x, field_y)
        if debug_flag
            fprintf('INFO: Skipping identical fields: %s = %s\n', field_x, field_y);
        end
        return;
    end
    
    % Define output path for scaling database
    scaling_path = "Database/Scaling/";

    % ====================================================================
    % CASE 1: ADDITIONAL SUB-DIMENSION (e.g., propellant type)
    % Creates separate scaling files for each unique value of add_dim field
    % ====================================================================
    if ~isempty(add_dim)
        if debug_flag
            fprintf('\n=== DEBUG: update_generic_component_scaling_a_to_b ===\n');
            fprintf('Mode: Additional dimension processing\n');
            fprintf('System: %s / %s / %s\n', system_type, technology_type, component_type);
            fprintf('Parameters: %s -> %s\n', field_x, field_y);
            fprintf('Additional dimension: %s\n', add_dim);
            fprintf('======================================================\n\n');
        end
        
        % Count number of component entries in database
        n_entries = numel(db_data.reference_data.(system_type).(technology_type).(component_type));
        
        if debug_flag
            fprintf('Found %d component entries (numel result)\n', n_entries);
            fprintf('Data structure class: %s\n', class(db_data.reference_data.(system_type).(technology_type).(component_type)));
        end
        
        % Collect all distinct values of the additional dimension field
        distinct_values = {};
        for i = 1:n_entries
            if n_entries == 1
                data_entry = db_data.reference_data.(system_type).(technology_type).(component_type);
            else
                data_entry = db_data.reference_data.(system_type).(technology_type).(component_type){1, i};
            end
            
            if isfield(data_entry, add_dim)
                distinct_values{i} = data_entry.(add_dim);
            end
        end
        
        % Get unique values
        distinct_values = unique(distinct_values);
        
        if debug_flag
            fprintf('Found %d distinct %s values: %s\n', ...
                    numel(distinct_values), add_dim, strjoin(distinct_values, ', '));
        end
        
        % Process each distinct value separately
        for j = 1:numel(distinct_values)
            current_value = distinct_values{j};
            
            if debug_flag
                fprintf('\n--- Processing %s = %s ---\n', add_dim, current_value);
            end
            
            x_values = [];
            y_values = [];
            matched_count = 0;
            
            % Collect data for current additional dimension value
            for i = 1:n_entries
                if n_entries == 1
                    data_entry = db_data.reference_data.(system_type).(technology_type).(component_type);
                else
                    data_entry = db_data.reference_data.(system_type).(technology_type).(component_type){1, i};
                end
                
                % Check if entry has required fields and matches current dimension value
                has_x = isfield(data_entry, field_x);
                has_y = isfield(data_entry, field_y);
                has_dim = isfield(data_entry, add_dim);
                matches_dim = has_dim && strcmp(data_entry.(add_dim), current_value);
                
                if has_x && has_y && matches_dim
                    % Check field values before collecting
                    x_value = data_entry.(field_x);
                    y_value = data_entry.(field_y);
                    
                    % Check if values are numeric
                    x_is_numeric = isnumeric(x_value);
                    y_is_numeric = isnumeric(y_value);
                    
                    % Skip if either field is non-numeric
                    if ~x_is_numeric || ~y_is_numeric
                        if debug_flag && matched_count == 0
                            fprintf('  *** Skipping non-numeric field(s): %s=%s, %s=%s ***\n', ...
                                    field_x, class(x_value), field_y, class(y_value));
                        end
                        continue;  % Skip this entry
                    end
                    
                    % Get dimensions
                    x_numel = numel(x_value);
                    y_numel = numel(y_value);
                    
                    % Detect array mismatch issue
                    if x_numel ~= y_numel
                        if debug_flag
                            fprintf('  *** MISMATCH in entry %d: %s has %d elements, %s has %d elements ***\n', ...
                                    i, field_x, x_numel, field_y, y_numel);
                            fprintf('  *** Skipping this entry ***\n');
                        end
                        continue;  % Skip this entry
                    end
                    
                    % Warn if array values detected
                    if x_numel > 1 && debug_flag && matched_count == 0
                        fprintf('\n*** INFO: Found array values with %d elements each ***\n', x_numel);
                    end
                    
                    matched_count = matched_count + 1;
                    x_values = [x_values x_value(:)'];  % Ensure row vector
                    y_values = [y_values y_value(:)'];  % Ensure row vector
                    
                    if debug_flag && matched_count <= 5
                        fprintf('  [%d] %s=%.4g, %s=%.4g\n', ...
                                matched_count, field_x, x_values(end), field_y, y_values(end));
                    end
                end
            end
            
            % Generate filename for this specific dimension value
            filename = strcat(scaling_path, "scaling_", system_type, "_", technology_type, "_", ...
                             component_type, "_with_", add_dim, "_", char(current_value), ...
                             "_", field_x, "_to_", field_y, ".csv");
            
            % Write data if valid and non-cell arrays
            is_valid_data = ~isempty(x_values) && ~isempty(y_values) && ...
                           ~iscell(x_values) && ~iscell(y_values);
            
            if is_valid_data
                if debug_flag
                    fprintf('About to write %d data points to file\n', numel(x_values));
                    fprintf('About to write %d data points to file\n', numel(y_values));
                    fprintf('Filename: %s\n', filename);
                end
                write_selected_data_to_file(x_values, y_values, filename, 0);
            else
                if debug_flag
                    fprintf('No valid data for %s = %s\n', add_dim, current_value);
                end
            end
        end
        
        if debug_flag
            fprintf('\n=== END DEBUG ===\n\n');
        end
        
    % ====================================================================
    % CASE 2: GENERIC PROCESSING (no additional dimension)
    % Creates single scaling file for all matching components
    % ====================================================================
    else
        if debug_flag
            fprintf('\n=== DEBUG: update_generic_component_scaling_a_to_b ===\n');
            fprintf('Mode: Generic processing\n');
            fprintf('System: %s / %s / %s\n', system_type, technology_type, component_type);
            fprintf('Parameters: %s -> %s\n', field_x, field_y);
            fprintf('======================================================\n\n');
        end
        
        x_values = [];
        y_values = [];
        matched_count = 0;
        skipped_count = 0;
        
        % Count number of component entries in database
        n_entries = numel(db_data.reference_data.(system_type).(technology_type).(component_type));
        
        if debug_flag
            fprintf('Processing %d component entries (numel result)\n', n_entries);
            fprintf('Data structure class: %s\n', class(db_data.reference_data.(system_type).(technology_type).(component_type)));
            if iscell(db_data.reference_data.(system_type).(technology_type).(component_type))
                fprintf('Data is a CELL ARRAY\n');
            elseif isstruct(db_data.reference_data.(system_type).(technology_type).(component_type))
                fprintf('Data is a STRUCT\n');
                if n_entries > 1
                    fprintf('Data is a STRUCT ARRAY with %d elements\n', n_entries);
                end
            end
        end
        
        % Iterate through all component entries
        for i = 1:n_entries
            % Get reference to current data entry
            if n_entries == 1
                data_entry = db_data.reference_data.(system_type).(technology_type).(component_type);
            else
                data_entry = db_data.reference_data.(system_type).(technology_type).(component_type){1, i};
            end
            
            if debug_flag && i <= 3
                fprintf('\n[Entry %d/%d]\n', i, n_entries);
                fprintf('  Entry class: %s\n', class(data_entry));
                fprintf('  Is struct: %d, Is cell: %d\n', isstruct(data_entry), iscell(data_entry));
                if isstruct(data_entry)
                    fprintf('  Struct has %d elements\n', numel(data_entry));
                    if isfield(data_entry, 'name')
                        if iscell(data_entry.name)
                            fprintf('  Name: %s\n', data_entry.name{1});
                        else
                            fprintf('  Name: %s\n', data_entry.name);
                        end
                    end
                end
            end
            
            % Check if entry has required fields
            has_x = isfield(data_entry, field_x);
            has_y = isfield(data_entry, field_y);
            
            if has_x && has_y
                % CRITICAL: Check if the field values are numeric (not struct, cell, or string)
                x_value = data_entry.(field_x);
                y_value = data_entry.(field_y);
                
                % Check if values are numeric
                x_is_numeric = isnumeric(x_value);
                y_is_numeric = isnumeric(y_value);
                
                if debug_flag && i <= 3
                    fprintf('  %s: %s (size: [%d %d], numel: %d)', ...
                            field_x, class(x_value), size(x_value, 1), size(x_value, 2), numel(x_value));
                    if ~x_is_numeric
                        fprintf(' [NON-NUMERIC]');
                    end
                    fprintf('\n');
                    
                    fprintf('  %s: %s (size: [%d %d], numel: %d)', ...
                            field_y, class(y_value), size(y_value, 1), size(y_value, 2), numel(y_value));
                    if ~y_is_numeric
                        fprintf(' [NON-NUMERIC]');
                    end
                    fprintf('\n');
                end
                
                % Skip if either field is non-numeric
                if ~x_is_numeric || ~y_is_numeric
                    if debug_flag
                        fprintf('  *** Skipping entry %d: Non-numeric field(s) detected ***\n', i);
                        if ~x_is_numeric
                            fprintf('      %s is %s (not numeric)\n', field_x, class(x_value));
                        end
                        if ~y_is_numeric
                            fprintf('      %s is %s (not numeric)\n', field_y, class(y_value));
                        end
                    end
                    skipped_count = skipped_count + 1;
                    continue;  % Skip this entry
                end
                
                % Get dimensions
                x_numel = numel(x_value);
                y_numel = numel(y_value);
                
                % Detect array mismatch issue
                if x_numel ~= y_numel
                    if debug_flag
                        fprintf('  *** MISMATCH in entry %d: %s has %d elements, %s has %d elements ***\n', ...
                                i, field_x, x_numel, field_y, y_numel);
                        fprintf('  *** Skipping this entry to avoid data corruption ***\n');
                    end
                    skipped_count = skipped_count + 1;
                    continue;  % Skip this entry
                end
                
                % Warn if array values detected
                if x_numel > 1 && debug_flag && matched_count == 0
                    fprintf('\n*** INFO: Entry %d contains array values (not scalars) ***\n', i);
                    fprintf('*** %s and %s each have %d elements ***\n', field_x, field_y, x_numel);
                    fprintf('*** All %d pairs will be added to the dataset ***\n\n', x_numel);
                end
                
                matched_count = matched_count + 1;
                
                % Extract and collect data values
                x_values = [x_values x_value(:)'];  % Ensure row vector
                y_values = [y_values y_value(:)'];  % Ensure row vector
                
                if debug_flag && matched_count <= 10
                    fprintf('  [%d] %s=%.4g, %s=%.4g\n', ...
                            matched_count, field_x, x_values(end), field_y, y_values(end));
                end
            else
                skipped_count = skipped_count + 1;
                
                if debug_flag && skipped_count <= 3
                    fprintf('  [Skip %d] Entry %d: has_%s=%d, has_%s=%d\n', ...
                            skipped_count, i, field_x, has_x, field_y, has_y);
                end
            end
        end
        
        % Generate output filename
        filename = strcat(scaling_path, "scaling_", system_type, "_", technology_type, "_", ...
                         component_type, "_", field_x, "_to_", field_y, ".csv");
        
        % Validate data before writing
        is_valid_data = ~isempty(x_values) && ~isempty(y_values) && ...
                       ~iscell(x_values) && ~iscell(y_values);
        
        if is_valid_data
            if debug_flag
                fprintf('\n--- Writing Results ---\n');
                fprintf('Total matched entries: %d\n', matched_count);
                fprintf('Total skipped entries: %d\n', skipped_count);
                fprintf('Output file: %s\n', filename);
                fprintf('Data range: %s [%.4g to %.4g], %s [%.4g to %.4g]\n', ...
                        field_x, min(x_values), max(x_values), ...
                        field_y, min(y_values), max(y_values));
            end
            if debug_flag
                fprintf('About to write %d data points to file\n', numel(x_values));
                fprintf('About to write %d data points to file\n', numel(y_values));
                fprintf('Filename: %s\n', filename);
            end
            write_selected_data_to_file(x_values, y_values, filename, 0);
            
            if debug_flag
                fprintf('File written successfully!\n');
                fprintf('=== END DEBUG ===\n\n');
            end
        else
            if debug_flag
                fprintf('\nWARNING: No valid data points found!\n');
                fprintf('Total entries processed: %d\n', n_entries);
                fprintf('Matched entries: %d\n', matched_count);
                fprintf('Skipped entries: %d\n', skipped_count);
                fprintf('Data is cell array: x=%d, y=%d\n', iscell(x_values), iscell(y_values));
                fprintf('=== END DEBUG ===\n\n');
            else
                warning('update_generic_component_scaling_a_to_b:noData', ...
                        'No valid data for %s/%s/%s: %s to %s', ...
                        system_type, technology_type, component_type, field_x, field_y);
            end
        end
    end
end

