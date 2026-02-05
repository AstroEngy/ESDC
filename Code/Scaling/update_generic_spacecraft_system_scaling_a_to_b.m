## -*- texinfo -*-
## @deftypefn {} {} update_generic_spacecraft_system_scaling_a_to_b (@var{data}, @var{orbit_type}, @var{field_x}, @var{field_y})
## Generate scaling law CSV file for spacecraft parameters filtered by orbit type.
##
## Extracts x-y parameter pairs from spacecraft reference data, filtering entries
## by orbit type (e.g., LEO, GEO), and generates a scaling law CSV file with fitted
## curve data. Only processes entries matching the specified orbit type and having
## both required fields with non-empty values.
##
## @strong{Inputs:}
## @table @var
## @item data
## Cell array of spacecraft data structures (typically from reference database).
## Each cell contains a struct with spacecraft parameters. Must be a 1D cell array
## (Nx1) where each element is a struct with fields like orbit_type, m_total, etc.
##
## @item orbit_type
## String specifying the orbit type to filter by (e.g., 'LEO', 'GEO', 'MEO').
## Only spacecraft with matching orbit_type field will be included. Empty string
## matches entries without orbit_type field.
##
## @item field_x
## String specifying the independent variable field name (e.g., 'm_total', 'p_total').
## Must exist as a field in spacecraft data structures. Typically represents a
## physical quantity that drives the scaling relationship.
##
## @item field_y
## String specifying the dependent variable field name (e.g., 'm_payload', 'p_payload').
## Must exist as a field in spacecraft data structures. Represents the quantity
## being predicted by the scaling law.
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Creates or overwrites CSV file in Database/Scaling/ directory
## @item Filename format: scaling_spacecraft_@var{orbit_type}_parameter_@var{field_x}_to_@var{field_y}.csv
## @item CSV file contains raw data points and fitted polynomial curve (via write_selected_data_to_file)
## @item Displays status messages to console during file creation
## @item Silently skips processing if no valid data points are found
## @end itemize
##
## @strong{Algorithm:}
## @enumerate
## @item Iterates through all spacecraft entries in data cell array
## @item For each entry, checks:
##   - Entry is not empty
##   - Has orbit_type field matching @var{orbit_type} parameter
##   - Has both @var{field_x} and @var{field_y} fields
##   - Both field values are non-empty
## @item Collects x and y values from matching entries
## @item If at least one valid data pair exists, generates scaling law CSV
## @item CSV generation includes polynomial fitting via write_selected_data_to_file()
## @end enumerate
##
## @strong{Assumptions and Notes:}
## @itemize
## @item Assumes data is a 1D cell array (column vector) of structs
## @item Assumes field values are numeric scalars (validated in write_selected_data_to_file)
## @item Empty entries in data array are silently skipped
## @item Name field (if present) is collected but currently not used in output
## @item Output directory Database/Scaling/ must exist or be creatable
## @item Scaling law quality depends on number and distribution of data points
## @end itemize
##
## @strong{Error Conditions:}
## @itemize
## @item Silently skips if no matching data points found (no CSV generated)
## @item May fail if data contains non-numeric values in @var{field_x} or @var{field_y}
##   (caught by downstream write_selected_data_to_file validation)
## @item May fail if output directory is not writable
## @end itemizes
##
## @strong{Example:}
## @example
## # Generate mass-to-payload scaling for LEO spacecraft
## spacecraft_data = @{struct('orbit_type','LEO','m_total',500,'m_payload',100), ...
##                     struct('orbit_type','LEO','m_total',1000,'m_payload',250)@};
## update_generic_spacecraft_system_scaling_a_to_b(spacecraft_data, 'LEO', 'm_total', 'm_payload');
## # Creates: Database/Scaling/scaling_spacecraft_LEO_parameter_m_total_to_m_payload.csv
## @end example
##
## @seealso{write_selected_data_to_file, update_generic_component_scaling_a_to_b}
## @end deftypefn

function [] = update_generic_spacecraft_system_scaling_a_to_b (data, orbit_type, field_x,field_y)
  path = "Database/Scaling/";
  
  % Initialize arrays for collecting parameter values
  x = [];
  y = [];
  name = {};
  
  % Iterate through all spacecraft entries in the data cell array
  for i=1:numel(data)
        % Access data as 1D cell array with single index
        % Filter by orbit type and validate field existence and non-empty values
        if ~isempty(data{i}) && isfield(data{i},'orbit_type') && strcmp(data{i}.orbit_type,orbit_type) && isfield(data{i},field_x)  && isfield(data{i},field_y) && not(isempty(data{i}.(field_x))) && not(isempty(data{i}.(field_y))) % consider data only when orbit type of object is correct and the respective field exists
              % Collect x and y parameter values from matching spacecraft
              x = [x data{i}.(field_x)];
              y = [y data{i}.(field_y)];
              
              % Optionally collect spacecraft name for reference (currently unused in output)
              if isfield(data{i},"name")
                name{1,numel(x)} = data{i}.name;
              else
                name{1,numel(x)} = {};
              end
        end
  end
  
  % Generate output filename based on orbit type and parameter names
  filename = strcat(path,"scaling_spacecraft_",orbit_type,"_parameter_",field_x,"_to_",field_y,".csv");
  
  % Only generate scaling law file if valid data points were found
  if numel(x)>0 && numel(y)>0
    write_selected_data_to_file(x,y,filename,0);
  end
end