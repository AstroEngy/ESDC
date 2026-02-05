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