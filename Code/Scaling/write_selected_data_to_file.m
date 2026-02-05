## -*- texinfo -*-
## @deftypefn {} {} write_selected_data_to_file (@var{x}, @var{y}, @var{filename}, @var{padbit})
## @deftypefnx {} {} write_selected_data_to_file (@var{x}, @var{y}, @var{filename}, @var{padbit}, @var{debug_mode})
## Write scaled data and fitted curve to CSV file with visualization.
##
## Processes x-y data pairs by sorting, fitting a polynomial curve, and writing
## both the raw data and fitted curve to a comma-separated value (CSV) file.
## Also generates a visualization graph of the data and fit.
##
## @strong{Inputs:}
## @table @var
## @item x
## Numeric vector or array of independent variable values (e.g., mass, power).
## Must have the same number of elements as @var{y}. Non-empty.
##
## @item y
## Numeric vector or array of dependent variable values corresponding to @var{x}.
## Must have the same number of elements as @var{x}. Non-empty.
##
## @item filename
## String specifying the output CSV file path (absolute or relative).
## If the file exists, it will be overwritten.
##
## @item padbit
## Logical flag (0 or 1) controlling zero-padding behavior:
## @itemize
## @item 0 - Use data as-is without padding
## @item 1 - Prepend a zero x-value point with the first y-value
## @end itemize
##
## @item debug_mode
## Optional logical flag (0 or 1) to enable detailed debug output.
## Default is 0 (off).
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Creates or overwrites the specified CSV file with two sections:
##   - Raw data sorted by x-values (2 rows: y-values, x-values)
##   - Fitted curve data with 100 interpolated points (2 rows: y-fit, x-fit)
## @item Displays confirmation message to console showing updated filename
## @item Generates a visualization graph via make_makeshift_graph()
## @end itemize
##
## @strong{Assumptions and Special Cases:}
## @itemize
## @item If only a single data point is provided, it is duplicated with doubled
##   x and y values to enable fitting (creates linear scaling).
## @item Data is automatically sorted by x-values before processing.
## @item Polynomial fitting degree is automatically determined by data_fitting().
## @item CSV format uses comma delimiters with two row blocks (data, then fit).
## @end itemize
##
## @strong{Error Conditions:}
## @itemize
## @item Fails if @var{x} and @var{y} have different lengths
## @item Fails if @var{filename} path is invalid or not writable
## @item May produce unexpected results if @var{x} or @var{y} contain NaN or Inf
## @end itemize
##
## @strong{Example:}
## @example
## x = [1, 2, 3, 4, 5];
## y = [2.1, 4.0, 5.9, 8.2, 10.1];
## write_selected_data_to_file(x, y, 'scaling_data.csv', 0);
## @end example
##
## @seealso{sort_data_to_x, data_fitting, make_makeshift_graph, dlmwrite}
## @end deftypefn

function [] = write_selected_data_to_file(x,y,filename, padbit, debug_mode)

    % Handle optional debug_mode parameter (default: off)
    if nargin < 5
        debug_mode = 0;
    end

    % Sort data according to x-values and apply optional zero-padding
    [data] = sort_data_to_x(x,y,padbit);

    % Handle single data point case: duplicate with doubled values to enable fitting
    % This creates a minimal linear scaling relationship from the single point
    if size(data,2)==1
      data = [data(:,1), 2.*data(:,1)];
    end

    % Perform polynomial curve fitting to the sorted data
    % Automatically selects optimal polynomial degree (1st to 3rd order)
    [data_fit] = data_fitting(data);

    % ===== DEBUG OUTPUT (if enabled) =====
    if debug_mode
        disp('=== DEBUG: write_selected_data_to_file ===');
        disp(['Filename: ', filename]);
        disp(['data size: ', num2str(size(data))]);
        disp(['data class: ', class(data)]);
        disp(['data_fit size: ', num2str(size(data_fit))]);
        disp(['data_fit class: ', class(data_fit)]);
    end
    
    % Write processed data to CSV file in two blocks:
    % Block 1: Raw sorted data (2 rows: y-values, x-values)
    % Block 2: Fitted curve with 100 interpolated points (appended)
    
    % Validate data before writing to avoid dlmwrite errors
    if isempty(data) || any(~isfinite(data(:)))
        if debug_mode
            disp('ERROR: data is empty or contains NaN/Inf');
            disp(data);
        end
        error('write_selected_data_to_file: data contains empty, NaN, or Inf values');
    end
    
    if isempty(data_fit) || any(~isfinite(data_fit(:)))
        warning('write_selected_data_to_file: data_fit contains invalid values, skipping file write');
        disp(strcat(filename, " skipped due to invalid fit data"));
        if debug_mode
            disp('data_fit contains:');
            disp(data_fit);
        end
        return;
    end
    
    % Ensure data_fit is a valid 2D matrix
    if ndims(data_fit) ~= 2 || size(data_fit,1) ~= 2
        warning('write_selected_data_to_file: data_fit has unexpected dimensions');
        disp(strcat(filename, " skipped due to invalid fit dimensions"));
        if debug_mode
            disp(['Expected: 2xN, Got: ', num2str(size(data_fit))]);
        end
        return;
    end
    
    % Additional validation: check filename is string and valid
    if ~ischar(filename) && ~isstring(filename)
        error('write_selected_data_to_file: filename is not a string');
    end
    
    % Extract directory from filename and ensure it exists
    [file_dir, ~, ~] = fileparts(filename);
    if ~isempty(file_dir) && ~exist(file_dir, 'dir')
        if debug_mode
            disp(['Creating directory: ', file_dir]);
        end
        mkdir(file_dir);
    end
    
    % Debug: Show actual data content
    if debug_mode
        disp('Data matrix content:');
        disp(data);
        disp('Data_fit first 5 columns:');
        disp(data_fit(:,1:min(5,size(data_fit,2))));
        disp('About to write data matrix:');
        disp(['  First write: data (', num2str(size(data)), ')']);
    end
    
    % Write using default delimiter (comma) - simplest form
    try
        dlmwrite(filename, data);
        if debug_mode
            disp('  First write successful');
        end
    catch err
        if debug_mode
            disp('ERROR in first dlmwrite:');
            disp(err.message);
            disp(['Error identifier: ', err.identifier]);
        end
        rethrow(err);
    end
    
    if debug_mode
        disp(['  Second write: data_fit (', num2str(size(data_fit)), ')']);
    end
    try
        dlmwrite(filename, data_fit, '-append');
        if debug_mode
            disp('  Second write successful');
        end
    catch err
        if debug_mode
            disp('ERROR in second dlmwrite:');
            disp(err.message);
            disp(['Error identifier: ', err.identifier]);
        end
        rethrow(err);
    end

    % Generate visualization graph showing both raw data points and fitted curve
    make_makeshift_graph(filename, data, data_fit);

    % Display confirmation message to console
    disp(strcat(filename, " updated"));

end


