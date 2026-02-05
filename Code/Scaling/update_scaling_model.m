% ============================================================================
% ESDC Scaling Model Generator - Refactored Version 2.0
% ============================================================================
% Generates scaling law correlations from spacecraft and system databases
% Output: Individual YAML files per correlation in Database/Scaling/
%
% ACCESSING MODEL DATA FROM OTHER CODE:
% ----------------------------------------------------------------------------
% 1. Load the scaling index to discover all available correlations:
%    index = read_file_auto('Database/Scaling/scaling_index.yaml');
%
% 2. Load a specific correlation file:
%    corr = read_file_auto('Database/Scaling/spacecraft/LEO_mass_total_to_power_total.yaml');
%
% 3. Access correlation data fields:
%    - corr.correlation.category       % Orbit type or system category
%    - corr.correlation.x_parameter    % Independent variable name
%    - corr.correlation.y_parameter    % Dependent variable name
%    - corr.data.x                     % Array of x data points
%    - corr.data.y                     % Array of y data points
%    - corr.data.names                 % Spacecraft/component names
%    - corr.fit.coefficients           % Polynomial coefficients [a_n, ..., a_1, a_0]
%    - corr.fit.degree                 % Polynomial degree
%    - corr.fit.r_squared              % Goodness of fit (0-1)
%    - corr.fit.x_fit, y_fit           % Smooth curve points for plotting
%
% 4. Evaluate the fitted model at a new point:
%    y_predicted = polyval(corr.fit.coefficients, x_new);
%
% 5. Example usage:
%    corr = read_file_auto('Database/Scaling/spacecraft/LEO_mass_total_to_power_total.yaml');
%    mass = 500;  % kg
%    power_estimate = polyval(corr.fit.coefficients, mass);  % W
% ============================================================================

function [scaling_model] = update_scaling_model(force_update_flag)
  % Main entry point for scaling model generation
  %
  % Input:
  %   force_update_flag - If true, regenerate all correlations regardless of database changes
  %
  % Output:
  %   scaling_model - Structure containing paths to generated correlation files
  
  disp('=== ESDC Scaling Model Generator v2.0 ===');
  disp('');
  
  % Check if update is needed
  if ~force_update_flag && ~database_changed()
    disp('No database changes detected. Skipping update.');
    disp('Use force_update=true to regenerate.');
    scaling_model = load_scaling_index();
    return;
  end
  
  % Initialize
  scaling_model = struct();
  scaling_model.version = '2.0';
  scaling_model.generated = datestr(now, 'yyyy-mm-dd HH:MM:SS');
  
  % Process spacecraft database
  disp('Processing spacecraft database...');
  try
    spacecraft_db = read_database('Spacecrafts');
    sc_files = generate_spacecraft_correlations(spacecraft_db);
    scaling_model.spacecraft = sc_files;
    fprintf('  Generated %d spacecraft correlations\n', length(sc_files));
  catch err
    warning('Spacecraft processing failed: %s', err.message);
    scaling_model.spacecraft = {};
  end
  
  % Process systems database
  disp('Processing systems database...');
  try
    systems_db = read_database('Systems');
    sys_files = generate_systems_correlations(systems_db);
    scaling_model.systems = sys_files;
    fprintf('  Generated %d system correlations\n', length(sys_files));
  catch err
    warning('Systems processing failed: %s', err.message);
    scaling_model.systems = {};
  end
  
  % Save index file
  save_scaling_index(scaling_model);
  
  % Update hash files
  update_hash_files();
  
  disp('');
  disp('=== Scaling model generation complete ===');
  disp('');
end


% ============================================================================
% DATABASE MANAGEMENT
% ============================================================================

function changed = database_changed()
  % Check if either database has changed since last processing
  sc_changed = check_hash('Database/ESDC_Reference_Data_Spacecrafts_hash', ...
                          'Database/ESDC_Reference_Data_Spacecrafts.xml');
  sys_changed = check_hash('Database/ESDC_Reference_Data_Systems_hash', ...
                           'Database/ESDC_Reference_Data_Systems.xml');
  changed = sc_changed || sys_changed;
end

function changed = check_hash(hash_file, data_file)
  % Check if data file hash matches stored hash
  if ~exist(hash_file, 'file')
    changed = true;
    return;
  end
  
  fid = fopen(hash_file, 'r');
  stored_hash = fgetl(fid);
  fclose(fid);
  
  current_hash = hash('md5', fileread(data_file));
  changed = ~strcmp(stored_hash, current_hash);
end

function update_hash_files()
  % Update hash files for both databases
  write_hash('Database/ESDC_Reference_Data_Spacecrafts_hash', ...
             'Database/ESDC_Reference_Data_Spacecrafts.xml');
  write_hash('Database/ESDC_Reference_Data_Systems_hash', ...
             'Database/ESDC_Reference_Data_Systems.xml');
end

function write_hash(hash_file, data_file)
  % Write MD5 hash of data file
  fid = fopen(hash_file, 'w');
  fprintf(fid, '%s', hash('md5', fileread(data_file)));
  fclose(fid);
end

function database = read_database(db_type)
  % Read and return database structure
  %
  % Input:
  %   db_type - 'Spacecrafts' or 'Systems'
  %
  % Output:
  %   database - Parsed database structure
  
  if strcmp(db_type, 'Spacecrafts')
    disp('  Reading spacecraft reference database...');
    database = read_file_auto('Database/ESDC_Reference_Data_Spacecrafts');
  else
    disp('  Reading systems reference database...');
    database = read_file_auto('Database/ESDC_Reference_Data_Systems');
  end
  
  disp('  Database loaded successfully');
end


% ============================================================================
% SPACECRAFT CORRELATIONS
% ============================================================================

function files = generate_spacecraft_correlations(database)
  % Generate all spacecraft parameter correlations
  %
  % Input:
  %   database - Spacecraft database structure
  %
  % Output:
  %   files - Cell array of generated file paths
  
  files = {};
  
  % Extract spacecraft data structure
  disp('  Extracting spacecraft data structure...');
  
  if ~isfield(database, 'reference_data_spacecraft')
    warning('Cannot find reference_data_spacecraft in database. Available fields:');
    disp(fieldnames(database));
    return;
  end
  
  ref_data = database.reference_data_spacecraft;
  
  % Handle different nesting levels
  if iscell(ref_data)
    if isfield(ref_data{1}, 'spacecraft')
      sc_data = ref_data{1}.spacecraft;
    else
      sc_data = ref_data;
    end
  elseif isstruct(ref_data)
    if isfield(ref_data, 'spacecraft')
      sc_data = ref_data.spacecraft;
    else
      sc_data = ref_data;
    end
  else
    warning('Unexpected spacecraft data structure type: %s', class(ref_data));
    return;
  end
  
  % Normalize to cell array
  if ~iscell(sc_data)
    if isstruct(sc_data)
      sc_data = num2cell(sc_data(:));
    else
      warning('Cannot convert spacecraft data to cell array');
      return;
    end
  end
  
  fprintf('  Found %d spacecraft entries\n', length(sc_data));
  
  % Get all unique orbit types
  orbit_types = get_unique_values(sc_data, 'orbit_type');
  fprintf('  Found %d unique orbit types: %s\n', length(orbit_types), strjoin(orbit_types, ', '));
  
  % Define parameters to correlate (matching YAML field names)
  x_params = {'mass_total', 'mass_payload', 'power_total'};
  
  % Get all available numeric fields
  y_params = get_numeric_fields(sc_data, ...
    {'name', 'launch_year', 'source', 'orbit_type', 'TRL', 'name_long', 'comment', ...
     'size_x', 'size_y', 'size_h'});  % Exclude size fields as they need special handling
  
  % Filter out fraction fields for x-params (they should only be y-params)
  y_params_filtered = {};
  for i = 1:length(y_params)
    param = y_params{i};
    % Skip if it's a fraction field and starts with 'fraction_'
    if ~any(strcmp(param, x_params))
      y_params_filtered{end+1} = param;
    end
  end
  y_params = y_params_filtered;
  
  fprintf('  Found %d numeric fields to correlate: %s\n', length(y_params), strjoin(y_params, ', '));
  
  % Generate correlations for each orbit type
  correlation_count = 0;
  for i = 1:length(orbit_types)
    orbit = orbit_types{i};
    if isempty(orbit), continue; end
    
    for j = 1:length(x_params)
      for k = 1:length(y_params)
        x_param = x_params{j};
        y_param = y_params{k};
        
        % Skip if same parameter
        if strcmp(x_param, y_param), continue; end
        
        % Extract data pairs
        [x, y, names, sources] = extract_spacecraft_data(sc_data, orbit, x_param, y_param);
        
        if length(x) >= 2  % Need at least 2 points
          try
            filename = save_correlation_yaml(orbit, x_param, y_param, x, y, names, sources, 'spacecraft');
            files{end+1} = filename;
            correlation_count = correlation_count + 1;
          catch err
            warning('Failed to generate %s/%s->%s: %s', orbit, x_param, y_param, err.message);
          end
        end
      end
    end
  end
  
  fprintf('  Successfully generated %d spacecraft correlations\n', correlation_count);
end

function [x, y, names, sources] = extract_spacecraft_data(sc_data, orbit_type, x_param, y_param)
  % Extract data pairs for spacecraft correlation
  x = [];
  y = [];
  names = {};
  sources = {};
  
  matched = 0;
  skipped = 0;
  
  for i = 1:length(sc_data)
    entry = sc_data{i};
    if isempty(entry)
      skipped = skipped + 1;
      continue;
    end
    
    % Check orbit type match
    if ~isfield(entry, 'orbit_type')
      skipped = skipped + 1;
      continue;
    end
    
    % Handle both string and numeric orbit types
    entry_orbit = entry.orbit_type;
    if isnumeric(entry_orbit)
      entry_orbit = num2str(entry_orbit);
    end
    if isnumeric(orbit_type)
      orbit_type = num2str(orbit_type);
    end
    
    if ~strcmp(entry_orbit, orbit_type)
      continue;
    end
    
    % Check if both parameters exist and are numeric
    if ~isfield(entry, x_param) || ~isfield(entry, y_param)
      skipped = skipped + 1;
      continue;
    end
    
    x_val = entry.(x_param);
    y_val = entry.(y_param);
    
    if ~isnumeric(x_val) || ~isnumeric(y_val) || isempty(x_val) || isempty(y_val)
      skipped = skipped + 1;
      continue;
    end
    
    if numel(x_val) ~= numel(y_val)
      skipped = skipped + 1;
      continue;
    end
    
    % Collect data
    x = [x, x_val(:)'];
    y = [y, y_val(:)'];
    matched = matched + 1;
    
    if isfield(entry, 'name')
      if iscell(entry.name)
        names{end+1} = entry.name{1};
      else
        names{end+1} = entry.name;
      end
    else
      names{end+1} = sprintf('SC_%d', i);
    end
    
    if isfield(entry, 'source')
      if iscell(entry.source)
        sources{end+1} = entry.source{1};
      else
        sources{end+1} = entry.source;
      end
    else
      sources{end+1} = 'Unknown';
    end
  end
  
  % Debug output for problematic cases
  if matched == 0 && skipped > 0
    fprintf('      [DEBUG] %s: %s->%s: matched=%d, skipped=%d\n', ...
            orbit_type, x_param, y_param, matched, skipped);
  end
end


% ============================================================================
% SYSTEMS CORRELATIONS
% ============================================================================

function files = generate_systems_correlations(database)
  % Generate all system/component parameter correlations
  %
  % Input:
  %   database - Systems database structure
  %
  % Output:
  %   files - Cell array of generated file paths
  
  files = {};
  
  if ~isfield(database, 'reference_data')
    error('Cannot find reference_data in systems database');
  end
  
  ref_data = database.reference_data;
  system_types = fieldnames(ref_data);
  
  % Process each system type
  for i = 1:length(system_types)
    sys_type = system_types{i};
    tech_types = fieldnames(ref_data.(sys_type));
    
    % Process each technology type
    for j = 1:length(tech_types)
      tech_type = tech_types{j};
      comp_types = fieldnames(ref_data.(sys_type).(tech_type));
      
      % Process each component type
      for k = 1:length(comp_types)
        comp_type = comp_types{k};
        
        % Skip non-component fields
        if strcmp(comp_type, 'requiredsystems')
          continue;
        end
        
        % Generate correlations for this component
        comp_files = process_component(ref_data.(sys_type).(tech_type).(comp_type), ...
                                       sys_type, tech_type, comp_type);
        files = [files, comp_files];
      end
    end
  end
end

function files = process_component(comp_data, sys_type, tech_type, comp_type)
  % Process a single component type and generate correlations
  files = {};
  
  % Normalize to cell array
  if ~iscell(comp_data)
    if isstruct(comp_data)
      comp_data = num2cell(comp_data(:));
    else
      return;  % Can't process
    end
  end
  
  % Check if we need to separate by propellant (for thrusters)
  if strcmp(comp_type, 'thruster')
    propellants = get_unique_values(comp_data, 'propellant');
    
    for i = 1:length(propellants)
      prop = propellants{i};
      if isempty(prop), continue; end
      
      prop_files = generate_component_correlations(comp_data, sys_type, tech_type, ...
                                                   comp_type, 'propellant', prop);
      files = [files, prop_files];
    end
  else
    % Generic component without sub-categorization
    files = generate_component_correlations(comp_data, sys_type, tech_type, comp_type);
  end
end

function files = generate_component_correlations(comp_data, sys_type, tech_type, comp_type, ...
                                                 sub_field, sub_value)
  % Generate correlations for a component with optional sub-categorization
  files = {};
  
  % Get all numeric fields (excluding metadata)
  params = get_numeric_fields(comp_data, ...
    {'type', 'name', 'source', 'propellant', 'TRL'});
  
  % Always use 'mass' as x-parameter when available
  x_param = 'mass';
  
  for i = 1:length(params)
    y_param = params{i};
    
    if strcmp(x_param, y_param), continue; end
    
    % Extract data
    if nargin >= 6
      [x, y, names, sources] = extract_component_data(comp_data, x_param, y_param, ...
                                                      sub_field, sub_value);
    else
      [x, y, names, sources] = extract_component_data(comp_data, x_param, y_param);
    end
    
    if length(x) >= 2
      try
        % Build category identifier
        if nargin >= 6
          category = sprintf('%s_%s_%s_%s', sys_type, tech_type, comp_type, sub_value);
        else
          category = sprintf('%s_%s_%s', sys_type, tech_type, comp_type);
        end
        
        filename = save_correlation_yaml(category, x_param, y_param, x, y, ...
                                        names, sources, 'systems');
        files{end+1} = filename;
      catch err
        warning('Failed to generate %s/%s->%s: %s', category, x_param, y_param, err.message);
      end
    end
  end
end

function [x, y, names, sources] = extract_component_data(comp_data, x_param, y_param, ...
                                                        sub_field, sub_value)
  % Extract data pairs for component correlation with optional filtering
  x = [];
  y = [];
  names = {};
  sources = {};
  
  for i = 1:length(comp_data)
    entry = comp_data{i};
    if isempty(entry), continue; end
    
    % Check sub-field filter if provided
    if nargin >= 5
      if ~isfield(entry, sub_field) || ~strcmp(entry.(sub_field), sub_value)
        continue;
      end
    end
    
    % Check if both parameters exist and are numeric
    if ~isfield(entry, x_param) || ~isfield(entry, y_param)
      continue;
    end
    
    x_val = entry.(x_param);
    y_val = entry.(y_param);
    
    if ~isnumeric(x_val) || ~isnumeric(y_val) || isempty(x_val) || isempty(y_val)
      continue;
    end
    
    if numel(x_val) ~= numel(y_val)
      continue;
    end
    
    % Collect data
    x = [x, x_val(:)'];
    y = [y, y_val(:)'];
    
    if isfield(entry, 'name')
      names{end+1} = entry.name;
    else
      names{end+1} = sprintf('Item_%d', i);
    end
    
    if isfield(entry, 'source')
      sources{end+1} = entry.source;
    else
      sources{end+1} = 'Unknown';
    end
  end
end


% ============================================================================
% UTILITY FUNCTIONS
% ============================================================================

function unique_vals = get_unique_values(data_array, field_name)
  % Get unique non-empty values of a field from cell array of structs
  unique_vals = {};
  
  for i = 1:length(data_array)
    entry = data_array{i};
    if isempty(entry), continue; end
    
    if isfield(entry, field_name)
      val = entry.(field_name);
      if ~isempty(val) && ~any(strcmp(unique_vals, val))
        unique_vals{end+1} = val;
      end
    end
  end
end

function numeric_fields = get_numeric_fields(data_array, exclusions)
  % Get list of fields that contain numeric data (excluding specified fields)
  numeric_fields = {};
  
  % Collect all field names
  all_fields = {};
  for i = 1:length(data_array)
    entry = data_array{i};
    if isempty(entry), continue; end
    
    fields = fieldnames(entry);
    all_fields = [all_fields; fields];
  end
  all_fields = unique(all_fields);
  
  % Check each field
  for i = 1:length(all_fields)
    field = all_fields{i};
    
    % Skip excluded fields
    if any(strcmp(field, exclusions))
      continue;
    end
    
    % Check if field contains numeric data in any entry
    is_numeric = false;
    for j = 1:length(data_array)
      entry = data_array{j};
      if isempty(entry), continue; end
      
      if isfield(entry, field)
        val = entry.(field);
        if isnumeric(val) && ~isempty(val)
          is_numeric = true;
          break;
        end
      end
    end
    
    if is_numeric
      numeric_fields{end+1} = field;
    end
  end
end


% ============================================================================
% CORRELATION STORAGE
% ============================================================================

function filename = save_correlation_yaml(category, x_param, y_param, x_data, y_data, ...
                                         names, sources, db_type)
  % Save correlation data and fit to individual YAML file
  %
  % Inputs:
  %   category - Category identifier (orbit type or system_tech_component)
  %   x_param, y_param - Parameter names
  %   x_data, y_data - Data arrays
  %   names, sources - Metadata arrays
  %   db_type - 'spacecraft' or 'systems'
  %
  % Output:
  %   filename - Path to saved file
  %
  % YAML File Structure (for external code access):
  % -----------------------------------------------
  % correlation:
  %   type: 'spacecraft' or 'systems'
  %   category: orbit type or system identifier
  %   x_parameter: independent variable name
  %   y_parameter: dependent variable name
  %   x_unit: unit string (e.g., '/ kg')
  %   y_unit: unit string (e.g., '/ W')
  % data:
  %   count: number of data points
  %   x: [x1, x2, ...] array
  %   y: [y1, y2, ...] array
  %   names: ['name1', 'name2', ...] array
  %   sources: ['source1', 'source2', ...] array
  % fit:
  %   type: 'polynomial'
  %   degree: polynomial order (1-3)
  %   coefficients: [a_n, ..., a_1, a_0] for y = a_n*x^n + ... + a_1*x + a_0
  %   r_squared: coefficient of determination (goodness of fit)
  %   rmse: root mean square error
  %   x_range: [min, max] of x data
  %   y_range: [min, max] of y data
  %   x_fit: smooth x array for plotting (100 points)
  %   y_fit: corresponding y values
  % metadata:
  %   generated: timestamp
  %   data_points_used: number of points
  
  % Sort data
  [x_sorted, idx] = sort(x_data);
  y_sorted = y_data(idx);
  names_sorted = names(idx);
  sources_sorted = sources(idx);
  
  % Handle single point case (add scaled duplicate)
  if length(x_sorted) == 1
    x_sorted = [x_sorted, x_sorted * 2];
    y_sorted = [y_sorted, y_sorted * 2];
    names_sorted{end+1} = [names_sorted{1}, ' (scaled)'];
    sources_sorted{end+1} = 'Extrapolated';
  end
  
  % Fit scaling law
  fit_result = fit_scaling_law(x_sorted, y_sorted);
  
  % Create correlation structure
  corr = struct();
  corr.correlation = struct();
  corr.correlation.type = db_type;
  corr.correlation.category = category;
  corr.correlation.x_parameter = x_param;
  corr.correlation.y_parameter = y_param;
  corr.correlation.x_unit = get_parameter_unit(x_param);
  corr.correlation.y_unit = get_parameter_unit(y_param);
  
  corr.data = struct();
  corr.data.count = length(x_sorted);
  corr.data.x = x_sorted;
  corr.data.y = y_sorted;
  corr.data.names = names_sorted;
  corr.data.sources = sources_sorted;
  
  corr.fit = fit_result;
  
  corr.metadata = struct();
  corr.metadata.generated = datestr(now, 'yyyy-mm-dd HH:MM:SS');
  corr.metadata.data_points_used = length(x_sorted);
  
  % Create directory structure
  base_path = 'Database/Scaling';
  if strcmp(db_type, 'spacecraft')
    output_dir = fullfile(base_path, 'spacecraft');
  else
    output_dir = fullfile(base_path, 'systems');
  end
  
  if ~exist(output_dir, 'dir')
    mkdir(output_dir);
  end
  
  % Generate filename
  filename = fullfile(output_dir, sprintf('%s_%s_to_%s.yaml', category, x_param, y_param));
  
  % Write YAML file
  write_yaml(filename, corr);
  
  % Generate visualization (optional, suppress errors)
  try
    generate_correlation_plot(filename, corr);
  catch
    % Silently continue if plotting fails
  end
end

function fit_result = fit_scaling_law(x_data, y_data)
  % Fit polynomial scaling law to data
  %
  % Inputs:
  %   x_data, y_data - Sorted data arrays
  %
  % Output:
  %   fit_result - Structure with fit parameters and curve
  
  % Prepare data as 2xN matrix for data_fitting function
  data = [y_data; x_data];  % Note: data_fitting expects [y; x] format
  
  % Call existing data_fitting function
  data_fit = data_fitting(data);
  
  % Extract fitted curve (data_fit is [y_fit; x_fit])
  x_fit = data_fit(2, :);
  y_fit = data_fit(1, :);
  
  % Determine polynomial degree used (by analyzing the fit)
  % For now, we'll estimate from curve complexity
  degree = estimate_poly_degree(x_data, y_data, x_fit, y_fit);
  
  % Fit polynomial to get coefficients
  if degree > 0
    coeffs = polyfit(x_data, y_data, degree);
  else
    coeffs = [mean(y_data)];
  end
  
  % Calculate R-squared
  y_mean = mean(y_data);
  ss_tot = sum((y_data - y_mean).^2);
  y_pred = polyval(coeffs, x_data);
  ss_res = sum((y_data - y_pred).^2);
  r_squared = 1 - (ss_res / ss_tot);
  
  % Calculate RMSE
  rmse = sqrt(mean((y_data - y_pred).^2));
  
  % Package results
  fit_result = struct();
  fit_result.type = 'polynomial';
  fit_result.degree = degree;
  fit_result.coefficients = coeffs;
  fit_result.r_squared = r_squared;
  fit_result.rmse = rmse;
  fit_result.x_range = [min(x_data), max(x_data)];
  fit_result.y_range = [min(y_data), max(y_data)];
  fit_result.x_fit = x_fit;
  fit_result.y_fit = y_fit;
end

function degree = estimate_poly_degree(x_data, y_data, x_fit, y_fit)
  % Estimate polynomial degree from fit quality
  % Simple heuristic based on data points
  n = length(x_data);
  
  if n <= 2
    degree = 1;
  elseif n <= 5
    degree = 2;
  else
    degree = 3;
  end
end

function write_yaml(filename, data_struct)
  % Write structure to YAML file
  % Simple YAML writer for basic structures
  
  fid = fopen(filename, 'w');
  write_yaml_recursive(fid, data_struct, 0);
  fclose(fid);
end

function write_yaml_recursive(fid, data, indent_level)
  % Recursively write YAML structure
  indent = repmat('  ', 1, indent_level);
  
  if isstruct(data)
    fields = fieldnames(data);
    for i = 1:length(fields)
      field = fields{i};
      value = data.(field);
      
      if isstruct(value)
        fprintf(fid, '%s%s:\n', indent, field);
        write_yaml_recursive(fid, value, indent_level + 1);
      elseif iscell(value)
        fprintf(fid, '%s%s:\n', indent, field);
        for j = 1:length(value)
          if ischar(value{j})
            fprintf(fid, '%s  - "%s"\n', indent, escape_yaml_string(value{j}));
          else
            fprintf(fid, '%s  - %s\n', indent, num2str(value{j}));
          end
        end
      elseif isnumeric(value)
        if length(value) == 1
          fprintf(fid, '%s%s: %g\n', indent, field, value);
        else
          fprintf(fid, '%s%s: [', indent, field);
          for j = 1:length(value)
            if j > 1, fprintf(fid, ', '); end
            fprintf(fid, '%g', value(j));
          end
          fprintf(fid, ']\n');
        end
      elseif ischar(value)
        fprintf(fid, '%s%s: "%s"\n', indent, field, escape_yaml_string(value));
      end
    end
  end
end

function escaped = escape_yaml_string(str)
  % Escape special characters in YAML strings
  escaped = strrep(str, '"', '\"');
  escaped = strrep(escaped, '\', '\\');
end

function generate_correlation_plot(filename, corr_data)
  % Generate visualization plot for correlation
  
  
  % Only generate plots for spacecraft data (can extend later)
  if ~strcmp(corr_data.correlation.type, 'spacecraft')
    return;
  end
  
  % Create output filename
  png_file = strrep(filename, '.yaml', '.png');
  png_file = strrep(png_file, 'Database/Scaling/', 'Output/');
  
  % Ensure output directory exists
  [out_dir, ~, ~] = fileparts(png_file);
  if ~exist(out_dir, 'dir')
    mkdir(out_dir);
  end
  
  % Create figure with publication-appropriate size (3.5" x 2.625" at 300 dpi)
  fig = figure('visible', 'off', 'Position', [100, 100, 1050, 787]);
  hold on;
  
  % Plot fit curve first (so it appears behind data points)
  plot(corr_data.fit.x_fit, corr_data.fit.y_fit, '-', 'Color', [0.3 0.3 0.3], ...
       'LineWidth', 1.2);
  
  % Plot data points with refined markers
  plot(corr_data.data.x, corr_data.data.y, 'o', 'MarkerSize', 6, ...
       'MarkerEdgeColor', 'k', 'MarkerFaceColor', [0.7 0.7 0.7], 'LineWidth', 0.8);
  
  % Labels (format parameter names for LaTeX)
  xlabel(sprintf('%s %s', format_parameter_for_latex(corr_data.correlation.x_parameter), corr_data.correlation.x_unit), ...
         'FontSize', 11, 'Interpreter', 'tex');
  ylabel(sprintf('%s %s', format_parameter_for_latex(corr_data.correlation.y_parameter), corr_data.correlation.y_unit), ...
         'FontSize', 11, 'Interpreter', 'tex');
  
  % Set axis properties for publication quality
  set(gca, 'FontSize', 10, 'LineWidth', 0.8, 'Box', 'on');
  grid on;
  set(gca, 'GridLineStyle', ':', 'GridAlpha', 0.3);
  
  % Annotation with refined styling
  ann_text = sprintf('Category: %s\nR^2 = %.3f\nn = %d', ...
                     strrep(corr_data.correlation.category, '_', '\_'), ...
                     corr_data.fit.r_squared, ...
                     corr_data.data.count);
  annotation('textbox', [0.17, 0.78, 0.3, 0.15], 'String', ann_text, ...
             'FitBoxToText', 'on', 'EdgeColor', [0.5 0.5 0.5], ...
             'BackgroundColor', [1 1 1], 'FontSize', 9, ...
             'LineWidth', 0.5, 'Margin', 5);
  
  % Save with high resolution for publication
  print(fig, png_file, '-dpng', '-r300');
  close(fig);
end

function unit = get_parameter_unit(parameter_name)
  % Determine unit for a parameter based on naming convention
  
  first_letter = parameter_name(1);
  
  switch first_letter
    case 'm'
      unit = '/ kg';
    case 'p'
      unit = '/ W';
    case 'f'
      unit = '/ -';
    case 's'
      unit = '/ m';
    case 'c'
      unit = '/ m/s';
    case 't'
      unit = '/ N';
    case 'v'
      unit = '/ V';
    case 'i'
      unit = '/ A';
    otherwise
      unit = '';
  end
end

function formatted = format_parameter_for_latex(parameter_name)
  % Format parameter name for proper LaTeX display
  % Converts underscores to proper subscript notation
  %
  % Examples:
  %   'power_total' -> 'power_{total}'
  %   'mass_payload' -> 'mass_{payload}'
  %   'fraction_propulsion_power' -> 'fraction_{propulsion\_power}'
  
  % Find first underscore
  underscore_pos = strfind(parameter_name, '_');
  
  if isempty(underscore_pos)
    % No underscores, return as-is
    formatted = parameter_name;
    return;
  end
  
  % Split at first underscore manually
  first_underscore = underscore_pos(1);
  main_part = parameter_name(1:first_underscore-1);
  subscript_part = parameter_name(first_underscore+1:end);
  
  % Escape remaining underscores in the subscript part
  subscript_part = strrep(subscript_part, '_', '\_');
  
  % Format as LaTeX subscript
  formatted = sprintf('%s_{%s}', main_part, subscript_part);
end


% ============================================================================
% INDEX FILE MANAGEMENT
% ============================================================================

function save_scaling_index(scaling_model)
  % Save index file cataloging all generated correlations
  
  index_file = 'Database/Scaling/scaling_index.yaml';
  write_yaml(index_file, scaling_model);
  disp('Scaling index saved');
end

function index = load_scaling_index()
  % Load scaling model index
  
  index_file = 'Database/Scaling/scaling_index.yaml';
  if exist(index_file, 'file')
    index = read_file_auto(index_file);
  else
    index = struct();
    index.spacecraft = {};
    index.systems = {};
  end
end


% ============================================================================
% DATA FITTING (UNCHANGED - Original Implementation)
% ============================================================================

function [data_fit] = data_fitting(data)
  % Original data fitting function - DO NOT MODIFY
  % THIS WILL BE REPLACED BY THE NEW SCALING LAW FITTING PROCEDURE
  
  threshold = 0.95;  % max 1-> perfect fit %TODO Simulation parameter

  % find best fitting polynominal fit for 1th 2nd and 3rd degree polynominal
  for i=1:4
    [trash_vals intp_data] = polyfit(data(2,:),data(1,:),i);
    normed_res(i)=intp_data.normr;
  end

  % norm residuals against different approaches
  if not(normed_res(1) == 0)
    for i=1:4
      normed_res_1(i) = normed_res(i)./normed_res(1);
    end

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

  % reconstruct function here for lookup table
  x_fit= linspace(data(2,1),data(2,end),100);
  
  for i=1:numel(x_fit)
    y_fit(i) =0;
    for j=1:numel(itp_func_coeffs)
      y_fit(i)=y_fit(i)+itp_func_coeffs(j)*x_fit(i)^(numel(itp_func_coeffs)-j);
    end
  end
  
  data_fit(1,:) = y_fit;
  data_fit(2,:) = x_fit;
endfunction





