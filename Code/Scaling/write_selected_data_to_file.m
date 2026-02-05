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


