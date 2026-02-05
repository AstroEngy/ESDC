## -*- texinfo -*-
## @deftypefn {} {@var{data} =} sort_data_to_x (@var{x}, @var{y}, @var{padbit})
## Sort x-y data pairs by x-values and arrange into matrix format.
##
## Sorts paired x-y data according to x-values in ascending order and returns
## a 2-row matrix with y-values in the first row and corresponding x-values
## in the second row. Optionally prepends a zero-value data point for padding.
##
## @strong{Inputs:}
## @table @var
## @item x
## Numeric vector or array of independent variable values (e.g., mass, power).
## Must be numeric (not struct or cell). Should have the same number of elements
## as @var{y}. Units depend on the physical quantity being represented.
##
## @item y
## Numeric vector or array of dependent variable values corresponding to @var{x}.
## Must be numeric (not struct or cell). Should have the same number of elements
## as @var{x}. Units depend on the physical quantity being represented.
##
## @item padbit
## Logical flag (0 or 1) controlling zero-padding behavior:
## @itemize
## @item 0 - Use data as-is without padding
## @item 1 - Prepend a data point with x=0 and y=first_y_value
## @end itemize
## Padding is useful for scaling laws that should pass through or near origin.
## @end table
##
## @strong{Outputs:}
## @table @var
## @item data
## 2-by-N numeric matrix where N is the number of data points.
## Row 1 contains sorted y-values, Row 2 contains sorted x-values.
## Format: [y1, y2, ..., yn; x1, x2, ..., xn] where x1 <= x2 <= ... <= xn.
## If @var{padbit}=1, N includes the prepended zero point.
## @end table
##
## @strong{Algorithm:}
## @enumerate
## @item Validates that x and y are numeric arrays (not structs or cells)
## @item Sorts x-values in ascending order and obtains sort indices
## @item Reorders y-values according to the same sort indices
## @item If @var{padbit}=1, prepends x=0 with y=sorted_y(1)
## @item Arranges data into 2-row matrix format [y_row; x_row]
## @end enumerate
##
## @strong{Assumptions and Notes:}
## @itemize
## @item Assumes x and y vectors have matching lengths (not explicitly checked)
## @item Zero-padding (@var{padbit}=1) assumes the first sorted y-value is
##   representative of behavior near x=0, which may not be valid for all datasets
## @item The output format (y in first row, x in second) is specific to the
##   scaling law fitting workflow in ESDC
## @item Empty arrays are not explicitly handled and may cause unexpected behavior
## @end itemize
##
## @strong{Error Conditions:}
## @itemize
## @item Throws error if @var{x} or @var{y} are not numeric types
## @item Throws error if @var{x} or @var{y} are cell arrays
## @item May fail if @var{x} and @var{y} have different lengths (sort will succeed
##   but indexing may fail or produce incorrect results)
## @end itemize
##
## @strong{Example:}
## @example
## x = [3, 1, 4, 2];
## y = [30, 10, 40, 20];
## data = sort_data_to_x(x, y, 0)
##   @result{} [10, 20, 30, 40; 1, 2, 3, 4]
##
## data_padded = sort_data_to_x(x, y, 1)
##   @result{} [10, 10, 20, 30, 40; 0, 1, 2, 3, 4]
## @end example
##
## @seealso{sort, data_fitting, write_selected_data_to_file}
## @end deftypefn

 function [data] = sort_data_to_x(x,y,padbit)

    % Validate input: x and y must be numeric, not structs or cells
    % This prevents type mismatch errors in subsequent array operations
    if ~isnumeric(x) || ~isnumeric(y)
        error('sort_data_to_x: x and y must be numeric arrays, not structs or cells');
    end
    
    % Additional check for cell arrays (defensive programming)
    if iscell(x) || iscell(y)
        error('sort_data_to_x: x and y cannot be cell arrays');
    end
    
    % Sort x-values in ascending order and obtain permutation indices
    [sorted_x sort_index] = sort(x);
    
    % Initialize sorted y array
    sorted_y = [];
    
    % Reorder y-values to match the sorted x-values
    % Using the permutation indices from the x sort
    for i=1:numel(x)
     sorted_y(i) = y(sort_index(i));
    endfor

    % Apply zero-padding if requested
    % Prepends a data point at x=0 with y-value equal to the first sorted point
    % Useful for scaling laws that should pass through or near the origin
    if padbit==1
      sorted_x = [0 sorted_x];
      sorted_y = [sorted_y(1) sorted_y];
    end
    
    % Arrange into 2-row matrix format: [y_values; x_values]
    % This format is used by downstream fitting and visualization functions
    data = [sorted_y; sorted_x];

 endfunction