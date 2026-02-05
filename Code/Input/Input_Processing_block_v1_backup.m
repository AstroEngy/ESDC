function [scaling_model_struct] = update_scaling_model(force_update_flag)
  disp('Database check:');
  %System scaling
  update_system_scaling(force_update_flag); %generates .csv look-up tables for component data from database
  %[data] = read_reference_data();    
  %update_generic_component_scaling_model(data);  

  %SC data scaling
  update_SC_scaling(force_update_flag); %generates .csv look-up tables for spacecraft data
  % [data] = read_reference_spacecraft_data();     %for debugging
  % update_generic_spacecraft_scaling_model(data);

end

function[] = update_SC_scaling(force_update)

    make_update = 0;
    if exist("Database/ESDC_Reference_Data_Spacecrafts_hash");
    hash_file = fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "r");
    hash_val = fgetl(hash_file);
    fclose(hash_file);
    current_hash = hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml'));
      if (hash_val == current_hash)
      disp('No updates to spacecraft database detected.');
        %return;
      else
      disp('Updates to spacecraft database detected.');
        [data] = read_reference_spacecraft_data();                    % add output here
        hash_file= fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "w");
        fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml')));
        fclose(hash_file);
        update_generic_spacecraft_scaling_model(data);
        disp('Updates to S/C db complete.');
      end
    else
      disp('No spacecraft database hash file found');
      disp('Creating hash file');
      hash_file= fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "a");
      disp('Write hash');
      fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml')));
      fclose(hash_file);
      make_update = 1;
    end
    
    if (force_update)
      disp('Forcing Spacecraft Database Update');
    end
    if (make_update | force_update)
      [data] = read_reference_spacecraft_data();
      update_generic_spacecraft_scaling_model(data);
    end
end

function [] =  update_generic_spacecraft_scaling_model(data)
  
    exclusion_list =    {'name', 'launch_year', 'source', 'orbit_type','TRL','name_long', 'comment'};  % list of xml field names that are not to be correlated 
    disp('Updating spacecraft scaling models');
    % Correct field name and provide fallback if reader used alternate key
    if isfield(data, 'reference_data_spacecraft')
      scdata = data.reference_data_spacecraft{1,1}.spacecraft;
    elseif isfield(data, 'reference_data_spracecraft')  % fallback for legacy typo
      scdata = data.reference_data_spracecraft{1,1}.spacecraft;
    else
      error('update_generic_spacecraft_scaling_model: missing field ''reference_data_spacecraft'' in input data');
    end

    % Normalize input to a cell array of structs for uniform processing
    if iscell(scdata)
      rawEntries = scdata(:);
    elseif isstruct(scdata)
      % convert struct array to cell array of single-element structs
      rawEntries = num2cell(scdata(:));
    else
      error('update_generic_spacecraft_scaling_model: unexpected spacecraft data type');
    end

    % Collect union of all field names across entries
    allFieldNames = {};
    for i = 1:numel(rawEntries)
      if isempty(rawEntries{i})
        continue;
      end
      fn = fieldnames(rawEntries{i});
      allFieldNames = [allFieldNames; fn];
    end
    allFieldNames = unique(allFieldNames);

   

    % determine different cases of orbit types
    distinct_orbit_cases  = {};
    for i=1:numel(data)
      if isfield(data(i), 'orbit_type')
        distinct_orbit_cases{i}=data(i).orbit_type;
      else
        distinct_orbit_cases{i} = '';
      end
    end
    distinct_orbit_cases = unique(distinct_orbit_cases);

    % determine number of potentially correlatable fields  
    all_fields = {};
    for i=1:numel(data)
      case_fields = fieldnames(data(i));
      all_fields = [all_fields; case_fields];
    end
    all_fields = unique(all_fields);

    to_correlate = {'m_total','m_payload','p_total','p_payload'}; 
    for i=1: numel(distinct_orbit_cases);
      for j=1:numel(to_correlate)                                                                               
       for k=1:numel(all_fields)
         %strcmp(all_fields{1,k},exclusion_list)
         if sum(strcmp(all_fields{1,k},exclusion_list))  % exclusion from numerical correlation
           %just skip
         else
          update_generic_spacecraft_system_scaling_a_to_b(data,char(distinct_orbit_cases{i}),char(to_correlate{1,j}),char(all_fields{1,k}));
         end
       end
      end
    end
  
   disp('Updating Spacecraft system scalings complete');
end



function [] = update_system_scaling(force_update)
  make_update = 0;
  %%DEBUG block:  Always do system scaling
  %data= read_reference_data(); 
  %update_generic_component_scaling_model(data); 
  
  if exist("Database/ESDC_Reference_Data_Systems_hash")
    hash_file = fopen('Database/ESDC_Reference_Data_Systems_hash', "r");
    hash_val = fgetl(hash_file);
    fclose(hash_file);
    current_hash = hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml'));
    if (hash_val == current_hash)
      disp('No updates to database detected.');
      else
      disp('Updates to database detected.');
        [data] = read_reference_data();                    % add output here
        hash_file= fopen('Database/ESDC_Reference_Data_Systems_hash', "w");
        fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml')));
        fclose(hash_file);
        update_generic_component_scaling_model(data);
        disp('Updates complete.');
      end
  else
    disp('No database hash file found');
    disp('Creating hash file');
    hash_file= fopen('Database/ESDC_Reference_Data_Systems_hash', "a");
    disp('Write hash');
    fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml')));
    fclose(hash_file);
    make_update= 1;
  end
  if force_update
    disp('Forcing Component Database Update');
  end
  if (make_update | force_update)
    [data] = read_reference_data();
    update_generic_component_scaling_model(data);
  end
end

function [] =  update_generic_component_scaling_model(data)
disp('Starting updating of scaling data');
disp('');
system_type_names=fieldnames(data.reference_data); % System loop - e.g. propulsion, power etc.
%disp(system_type_names)
for k=1:numel(system_type_names)
  
  technology_type_names=fieldnames(data.reference_data.(char(system_type_names(k))));
  for i=1:numel(technology_type_names)                    % Technology loop - e.g. arcjet, GIT etc.

    %disp(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))))
    %disp(system_type_names(k))
    %disp(technology_type_names(i))
    %disp(data.reference_data.(char(system_type_names(k))))
    component_type_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i)))); %bug here , when updating DB, probably because tech types dont exist?
    for j=1:numel(component_type_names)                   % Component loop - e.g. thruster, ppu, solar cell, etc.
      if not(isstruct(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j))))) % HERE single field will not be considered
        parameter_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j))){1,i});
      else
        parameter_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j))));
      end
      
      if strcmp(parameter_names,"system") 
        break;
      end
        for l=1:numel(parameter_names)                      % Parameter loop - e.g. mass, power, etc 
          if strcmp(char(component_type_names(j)),'thruster')     % Case distinction of scaling parameters of thrusters being propellant dependent
          update_generic_component_scaling_a_to_b(data,char(system_type_names(k)),char(technology_type_names(i)),char(component_type_names(j)),'mass',char(parameter_names(l)), 'propellant');
          else                                                    % Generic correlation of two parameters
          update_generic_component_scaling_a_to_b(data,char(system_type_names(k)),char(technology_type_names(i)),char(component_type_names(j)),'mass',char(parameter_names(l)));
          end
        
        end

    end
  end
  
%update_generic_component_scaling_a_to_b(data,'propulsion_system','arcjet','ppu','mass','power')
end
disp('');
disp('Updating scaling data complete');
disp('');

end



function [] = update_generic_spacecraft_scaling_a_to_b (data, orbit_type, field_x, field_y)

  path = "Database/Scaling/";             %new path set to output /Scaling/Model/System
  
  x = [];
  y = [];
  name = {};

  %Data vector creation here
  for i = 1:numel(data)
        if strcmp(data(i).orbit_type, orbit_type) && isfield(data(i), field_x) && isfield(data(i), field_y) && ~isempty(data(i).(field_x)) && ~isempty(data(i).(field_y))
              x = [x data(i).(field_x)];
              y = [y data(i).(field_y)];
              if isfield(data(i), "name")
                name{1, numel(x)} = data(i).name;
              else
                name{1, numel(x)} = {};
              end
        end
  end
  
   filename = strcat(path, "scaling_spacecraft_", orbit_type, "_parameter_", field_x, "_to_", field_y, ".csv");
   if numel(x) > 0 && numel(y) > 0
    write_selected_data_to_file(x, y, filename, 0); % TODO param names here
   end
end

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
                    fprintf('About to write %d data points (x: %d, y: %d) to file\n', numel(x_values), numel(x_values), numel(y_values));
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
                fprintf('About to write %d data points (x: %d, y: %d) to file\n', numel(x_values), numel(x_values), numel(y_values));
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

function [] = write_selected_data_to_file(x, y, filename, padbit)
    % Write selected data and fitted curve to file
    % Inputs:
    %   x, y      - Input data arrays
    %   filename  - Output file path
    %   padbit    - Padding parameter for data sorting
    
    % Input validation
    if isempty(x) || isempty(y)
        error('write_selected_data_to_file:emptyData', 'Input data x and y cannot be empty');
    end
    
    if isempty(filename) || ~ischar(filename)
        error('write_selected_data_to_file:invalidFilename', 'Filename must be a non-empty string');
    end
    
    % Clean filename (remove trailing/leading whitespace)
    filename = strtrim(filename);
    
    % Ensure directory exists
    [filepath, ~, ~] = fileparts(filename);
    if ~isempty(filepath) && ~exist(filepath, 'dir')
        mkdir(filepath);
        fprintf('Created directory: %s\n', filepath);
    end
    
    % Sort and organize data (returns Nx2 matrix: [x, y])
    sorted_data = sort_data_to_x(x, y, padbit);
    
    % Handle single data point case - use linear scaling
    LINEAR_SCALE_FACTOR = 2.0;
    if size(sorted_data, 1) == 1
        % Add a second point using linear scaling
        sorted_data = [sorted_data; sorted_data(1,1) * LINEAR_SCALE_FACTOR, sorted_data(1,2) * LINEAR_SCALE_FACTOR];
    end
    
    % Validate sorted data before proceeding
    if isempty(sorted_data)
        error('write_selected_data_to_file:noData', 'No data available after sorting');
    end
    
    % Ensure sorted_data is Nx2 (each row is [x, y])
    if size(sorted_data, 2) ~= 2
        error('write_selected_data_to_file:invalidFormat', ...
              'sorted_data must be Nx2 matrix, got %dx%d', size(sorted_data, 1), size(sorted_data, 2));
    end
    
    % Fit curve to data
    fitted_data = data_fitting(sorted_data);
    
    % Transpose fitted_data if needed (should be Nx2, not 2xN)
    if size(fitted_data, 1) < size(fitted_data, 2)
        fitted_data = fitted_data';
    end
    
    % Check for invalid data that would cause dlmwrite to fail
    if any(isnan(sorted_data(:))) || any(isinf(sorted_data(:)))
        error('write_selected_data_to_file:invalidData', ...
              'sorted_data contains NaN or Inf values for file: %s', filename);
    end
    
    if any(isnan(fitted_data(:))) || any(isinf(fitted_data(:)))
        error('write_selected_data_to_file:invalidData', ...
              'fitted_data contains NaN or Inf values for file: %s', filename);
    end
    
    if ~isnumeric(sorted_data) || ~isnumeric(fitted_data)
        error('write_selected_data_to_file:invalidData', ...
              'Data must be numeric. sorted_data: %s, fitted_data: %s', ...
              class(sorted_data), class(fitted_data));
    end
    
    % Write data to file with error handling
    try
        % Delete existing file to avoid append issues
        if exist(filename, 'file')
            delete(filename);
        end
        
        dlmwrite(filename, sorted_data, ',', 'precision', '%.6f');
        dlmwrite(filename, fitted_data, ',', '-append', 'precision', '%.6f');
    catch ME
        fprintf('\n=== ERROR DETAILS ===\n');
        fprintf('Filename: "%s"\n', filename);
        fprintf('Filename length: %d\n', length(filename));
        fprintf('Directory exists: %d\n', exist(filepath, 'dir'));
        fprintf('Error identifier: %s\n', ME.identifier);
        fprintf('Error message: %s\n', ME.message);
        fprintf('sorted_data size: [%d x %d]\n', size(sorted_data));
        fprintf('fitted_data size: [%d x %d]\n', size(fitted_data));
        fprintf('=== END ERROR DETAILS ===\n\n');
        
        error('write_selected_data_to_file:fileWriteError', ...
              'Failed to write to file %s: %s', filename, ME.message);
    end
    
    % Generate visualization
    try
        fprintf('DEBUG: Attempting to generate graph for %s\n', filename);
        make_makeshift_graph(filename, sorted_data, fitted_data);
        fprintf('DEBUG: Graph generated successfully\n');
    catch ME
        fprintf('WARNING: Graph generation failed for %s\n', filename);
        fprintf('  Error: %s\n', ME.message);
        fprintf('  Identifier: %s\n', ME.identifier);
        % Continue execution even if graph fails
    end
    
    % Display confirmation message
    fprintf('%s updated\n', filename);
end


function [data] = sort_data_to_x(x, y, padbit, debug_flag)
    % Sort data according to x values and return as matrix
    % Inputs:
    %   x          - Array of x values to sort by
    %   y          - Array of y values (same length as x)
    %   padbit     - Flag (1 = pad with zero case, 0 = no padding)
    %   debug_flag - Optional flag (1 = enable debug output, 0 = disable, default: 0)
    % Output:
    %   data       - Nx2 matrix [x_sorted, y_sorted] where each row is [x, y]
    
    % Set default debug flag if not provided
    if nargin < 4
        debug_flag = 0;
    end
    
    % Debug: Display input information (only if debug_flag is enabled)
    if debug_flag
        fprintf('\n=== DEBUG: sort_data_to_x ===\n');
        fprintf('x size: [%d x %d], numel: %d\n', size(x, 1), size(x, 2), numel(x));
        fprintf('y size: [%d x %d], numel: %d\n', size(y, 1), size(y, 2), numel(y));
        fprintf('x class: %s\n', class(x));
        fprintf('y class: %s\n', class(y));
        fprintf('padbit: %d\n', padbit);
        fprintf('x values: ');
        disp(x);
        fprintf('y values: ');
        disp(y);
        fprintf('=== END DEBUG ===\n\n');
    end
    
    % Validate inputs
    if numel(x) ~= numel(y)
        error('sort_data_to_x:sizeMismatch', ...
              'x and y must have the same number of elements (x: %d, y: %d)', ...
              numel(x), numel(y));
    end
    
    if isempty(x) || isempty(y)
        error('sort_data_to_x:emptyData', ...
              'x and y cannot be empty');
    end
    
    % Sort data by x values
    [sorted_x, sort_index] = sort(x);
    sorted_y = y(sort_index);
    
    % Apply padding if requested (add zero case at beginning)
    if padbit == 1
        sorted_x = [0, sorted_x];
        sorted_y = [sorted_y(1), sorted_y];
    end
    
    % Return as Nx2 matrix (x in first column, y in second column)
    % This creates proper CSV format: x,y on each row
    data = [sorted_x(:), sorted_y(:)];
end

function [] = make_makeshift_graph(filename_old, data, data_fit)
    % Generate and save a scaling law visualization plot
    %
    % Inputs:
    %   filename_old - Original CSV filename (e.g., 'Database/Scaling/scaling_spacecraft_LEO_parameter_mass_to_power.csv')
    %   data         - Nx2 matrix of actual data points [x, y]
    %   data_fit     - Nx2 matrix of fitted curve points [x, y]
    %
    % Output:
    %   Saves PNG file to Output/ directory
    
    % Generate output filename
    filename = strrep(filename_old, '.csv', '.png');
    filename = strrep(filename, 'Database/Scaling/', 'Output/');
    
    % Ensure Output directory exists
    [output_dir, ~, ~] = fileparts(filename);
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
        fprintf('Created output directory: %s\n', output_dir);
    end
    
    % Extract title from filename (remove path and extension)
    title_text = filename_old(8:end-4);
    
    % Only create graphs for spacecraft data (components can be added later)
    if ~isempty(strfind(filename_old, 'spacecraft'))
        % Parse filename to extract metadata
        underscore_positions = strfind(filename_old, '_');
        param_position = strfind(filename_old, 'parameter');
        to_position = strfind(filename_old, '_to_');
        
        % Extract orbit type (between 2nd underscore and "parameter")
        orbit_type = filename_old(underscore_positions(2)+1 : param_position-2);
        
        % Extract x-axis parameter name
        param_x = filename_old(param_position+10 : to_position-1);
        unit_x = get_parameter_unit(param_x);
        
        % Capitalize first letter of x parameter if it's 'p'
        if strcmp(param_x(1), 'p')
            param_x(1) = 'P';
        end
        
        % Extract y-axis parameter name
        param_y = filename_old(to_position+4 : end-4);
        unit_y = get_parameter_unit(param_y);
        
        % Capitalize first letter of y parameter if it's 'p'
        if strcmp(param_y(1), 'p')
            param_y(1) = 'P';
        end
        
        % Format parameter names (replace underscores with spaces)
        param_x = strrep(param_x, '_', ' ');
        param_y = strrep(param_y, '_', ' ');
        
        % Create axis labels with units
        xlabel_text = strcat(param_x, unit_x);
        ylabel_text = strcat(param_y, unit_y);
        
        % Create annotation with orbit type
        annotation_text = strcat('Orbit type: ', orbit_type);
        
        % Clean title for display
        display_title = erase(filename, "Output/");
        
        % Create figure (invisible to avoid popup during batch processing)
        fig_handle = figure('Name', display_title, 'visible', 'off');
        set(0, 'CurrentFigure', fig_handle);
        hold on;
        
        % Add annotation box with orbit type
        annotation('textbox', [0.15, 0.9, 0.3, 0.08], ...
                   'String', annotation_text, ...
                   'FitBoxToText', 'on', ...
                   'EdgeColor', 'white', ...
                   'FontSize', 16);
        
        % Set axis labels
        xlabel(xlabel_text, 'FontSize', 16);
        ylabel(ylabel_text, 'FontSize', 16);
        
        % Plot actual data points (black asterisks)
        plot(data(:,1), data(:,2), '*k', 'MarkerSize', 12);
        
        % Plot fitted curve (black line)
        plot(data_fit(:,1), data_fit(:,2), '-k', 'LineWidth', 2);
        
        % Save figure to PNG file
        saveas(fig_handle, filename, 'png');
        
        hold off;
        close(fig_handle);
    end
end


function unit = get_parameter_unit(parameter_name)
    % Determine the unit for a parameter based on its first letter
    %
    % Input:
    %   parameter_name - String name of the parameter
    %
    % Output:
    %   unit - String representing the unit (e.g., ' / kg', ' / W')
    
    % Take only the first letter for unit determination
    first_letter = parameter_name(1);
    
    switch first_letter
        case 'm'
            unit = ' / kg';  % Mass
        case 'p'
            unit = ' / W';   % Power
        case 'f'
            unit = ' / -';   % Dimensionless (factor)
        case 's'
            unit = ' / m';   % Size/dimension
        otherwise
            unit = '';       % No unit assigned
    end
end

function [database] = read_reference_data()
    disp('Reading Reference Data Input File');
    database = read_file_auto('Database/ESDC_Reference_Data_Systems');
    disp('Success');
    disp(' ');
    fflush(stdout);
end

function [spacecraft_parameters] = read_reference_spacecraft_data()
    disp('Reading Spacecraft Reference Database');
    
    try
        spacecraft_parameters = read_file_auto('Database/ESDC_Reference_Data_Spacecrafts');
        
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

function [data_fit] = data_fitting(data) % THIS WILL BE REPLACED BY THE NEW SCALING LAW FITTING PROCEDURE

  
      threshold = 0.95;  % max 1-> perfect fit %TODO Simulation parameter

    % find best fitting polynominal fit for 1th 2nd and 3rd degree polynominal
      %disp(data)
      for i=1:4
        [trash_vals intp_data] = polyfit(data(2,:),data(1,:),i);
        normed_res(i)=intp_data.normr;
      end
    %normed_res
    
    % norm residuals against different approaches
    if not(normed_res(1) == 0)
      for i=1:4
        normed_res_1(i) = normed_res(i)./normed_res(1);
      end

    %normed_res_1
      if min(normed_res_1)> threshold
        result=1;
      else
        result=0;
      end
    else
        result =0;
    endif

    if not(result || normed_res(2) == 0)
        for i=1:3
          normed_res_2(i) = normed_res(i)./normed_res(2);
        end
        
        if (min(normed_res_2)> threshold)
          result=2;
        end

    endif
 
    if not(result|| normed_res(3) == 0)
      
      for i=1:4           % check for fourth 
        normed_res_3(i) = normed_res(i)./normed_res(3);
      end
    
      if (min(normed_res_3)> threshold)  % reconsider here!!
        result=3;
      end
      
    end
    
    if result == 3
        [itp_func_coeffs intp_data] = polyfit(data(2,:),data(1,:),result);
        x_fit= linspace(data(2,1),data(2,end),100);
        
          for i=1:numel(x_fit)
              y_fit(i) =0;
            for j=1:numel(itp_func_coeffs)
              y_fit(i)=y_fit(i)+itp_func_coeffs(j)*x_fit(i)^(numel(itp_func_coeffs)-j);
            end
          end
          
          if min(y_fit) < min(data(1,:)) || max(y_fit) > max(data(1,:))
            result =1;
          end
          
    end
    
    if not(result)
        result=1;
    end
    
  [itp_func_coeffs intp_data] = polyfit(data(2,:),data(1,:),result);
  %end

  %reconstruct function here for lookup table genpath
  x_fit= linspace(data(2,1),data(2,end),100);
  

  for i=1:numel(x_fit)
    y_fit(i) =0;
      for j=1:numel(itp_func_coeffs)
        y_fit(i)=y_fit(i)+itp_func_coeffs(j)*x_fit(i)^(numel(itp_func_coeffs)-j);
      end
      
  end
  
%  figure;
%  hold on;
%
%    plot(data(2,:),data(1,:),'*')
%    plot(x_fit,y_fit,'-')

  data_fit(1,:) = y_fit;
  data_fit(2,:) = x_fit;
  
  
endfunction





