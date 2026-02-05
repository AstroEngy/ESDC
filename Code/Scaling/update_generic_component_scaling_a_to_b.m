## -*- texinfo -*-
## @deftypefn {} {} update_generic_component_scaling_a_to_b (@var{db_data}, @var{system_type}, @var{technology_type}, @var{component_type}, @var{field_x}, @var{field_y})
## @deftypefnx {} {} update_generic_component_scaling_a_to_b (@var{db_data}, @var{system_type}, @var{technology_type}, @var{component_type}, @var{field_x}, @var{field_y}, @var{add_dim})
## Generate scaling law CSV files for component parameters from reference database.
##
## Extracts parameter pairs from component reference data and generates scaling law
## CSV files with fitted curves. Supports two modes: generic (all data combined) or
## subdivided by an additional dimension (e.g., separate scaling laws per propellant type).
## Automatically filters out non-numeric field values to prevent type errors.
##
## @strong{Inputs:}
## @table @var
## @item db_data
## Struct containing reference database with nested hierarchy:
## db_data.reference_data.@var{system_type}.@var{technology_type}.@var{component_type}
## Each component entry is a struct or cell array of structs with parameter fields.
##
## @item system_type
## String specifying system category (e.g., 'propulsion_system', 'power_system').
## Must match a field name in db_data.reference_data structure.
##
## @item technology_type
## String specifying technology variant (e.g., 'arcjet', 'gridded_ion_thruster').
## Must match a field within the specified system_type.
##
## @item component_type
## String specifying component name (e.g., 'thruster', 'ppu', 'solar_cell').
## Must match a field within the specified technology_type.
##
## @item field_x
## String specifying independent variable field name (e.g., 'mass', 'power_jet').
## Must exist in component data structures and contain numeric values.
## Should not be same as @var{field_y}.
##
## @item field_y
## String specifying dependent variable field name (e.g., 'power', 'thrust').
## Must exist in component data structures and contain numeric values.
## Non-correlatable fields ('type', 'name', 'source', 'propellant') are excluded.
##
## @item add_dim
## Optional string specifying additional dimension field for data subdivision
## (e.g., 'propellant' to create separate scaling laws for Xe, Kr, Ar).
## When provided (nargin==7), creates multiple CSV files, one per unique value.
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Creates or overwrites CSV files in Database/Scaling/ directory
## @item Without @var{add_dim}: scaling_@var{system_type}_@var{technology_type}_@var{component_type}_@var{field_x}_to_@var{field_y}.csv
## @item With @var{add_dim}: scaling_@var{system_type}_@var{technology_type}_@var{component_type}_with_@var{add_dim}_@var{value}_@var{field_x}_to_@var{field_y}.csv
## @item Displays status messages during file creation (via write_selected_data_to_file)
## @item Returns early without output if @var{field_y} is in exclusion list
## @item Returns early without output if @var{field_x} equals @var{field_y}
## @end itemize
##
## @strong{Algorithm:}
## @enumerate
## @item Check exclusion list: skip if @var{field_y} is non-numeric type
## @item Check self-correlation: skip if @var{field_x} equals @var{field_y}
## @item If @var{add_dim} provided (nargin==7):
##   - Collect all unique values of @var{add_dim} field
##   - For each unique value, collect matching x-y pairs
##   - Generate separate CSV file for each subdivision
## @item Otherwise (generic mode):
##   - Collect all x-y pairs from all component instances
##   - Generate single CSV file combining all data
## @item Data validation applied during collection:
##   - Only numeric scalar values are included
##   - Struct and cell values are filtered out
##   - Empty values are skipped
## @item CSV generation includes polynomial fitting via write_selected_data_to_file()
## @end enumerate
##
## @strong{Assumptions and Notes:}
## @itemize
## @item Assumes db_data follows ESDC reference database structure conventions
## @item Component data can be single struct or cell array of structs
## @item Non-numeric metadata fields (name, source, etc.) are automatically filtered
## @item Empty or missing fields are silently skipped, not treated as errors
## @item Output directory Database/Scaling/ must exist or be creatable
## @item Scaling law quality depends on number and distribution of data points
## @item When @var{add_dim} subdivides data, some subdivisions may have insufficient points
## @end itemize
##
## @strong{Error Conditions:}
## @itemize
## @item Returns silently if no valid numeric data pairs found
## @item May fail if database structure does not match expected hierarchy
## @item May fail if output directory is not writable
## @item Downstream errors from write_selected_data_to_file if data validation fails
## @end itemize
##
## @strong{Example:}
## @example
## # Generic scaling: PPU mass vs power for all gridded ion thrusters
## update_generic_component_scaling_a_to_b(db, 'propulsion_system', ...
##     'gridded_ion_thruster', 'ppu', 'mass', 'power');
##
## # Subdivided scaling: thruster mass vs thrust, separate per propellant
## update_generic_component_scaling_a_to_b(db, 'propulsion_system', ...
##     'arcjet', 'thruster', 'mass', 'thrust', 'propellant');
## # Creates: scaling_propulsion_system_arcjet_thruster_with_propellant_Xe_mass_to_thrust.csv
## #          scaling_propulsion_system_arcjet_thruster_with_propellant_Kr_mass_to_thrust.csv
## #          (one file per propellant type found in data)
## @end example
##
## @seealso{write_selected_data_to_file, update_generic_spacecraft_system_scaling_a_to_b}
## @end deftypefn

function [] = update_generic_component_scaling_a_to_b(db_data, system_type, technology_type, component_type, field_x, field_y, varargin)

% ===== EARLY RETURN CONDITIONS =====

% Exclusion list: skip non-numeric or non-correlatable y-fields
% These fields contain strings or categorical data that cannot be fitted
if strcmp(field_y,'type') ||  strcmp(field_y,'name') ||  strcmp(field_y,'source') ||  strcmp(field_y,'propellant') 
  return
end

% Prevent self-correlation: x vs x would be meaningless
if strcmp(field_x, field_y)
 return
end

% Output path for generated CSV files
path = "Database/Scaling/";

% ===== CASE 1: ADDITIONAL DIMENSION SUBDIVISION =====
% Generate separate scaling laws for each unique value of additional dimension
% (e.g., separate thruster mass-thrust relations per propellant type)

add_dim=char(varargin);  % Extract optional additional dimension field name
  if nargin==7
      distinct_cases  = {};
        % Determine number of component instances in database
        n_cases = numel(db_data.reference_data.(system_type).(technology_type).(component_type));
        
      % Collect all unique values of the additional dimension field
      for i=1:n_cases
        if n_cases==1
          distinct_cases{i}  = db_data.reference_data.(system_type).(technology_type).(component_type).(add_dim);
        else
          distinct_cases{i}  = db_data.reference_data.(system_type).(technology_type).(component_type){1,i}.(add_dim);
        endif

      end
        distinct_cases= unique(distinct_cases);

      % Process each subdivision separately
      for j=1:numel(distinct_cases) 

        x = [];
        y = [];
        
        % Access component data (handle single struct vs cell array)
        if n_cases==1
          data_point =db_data.reference_data.(system_type).(technology_type).(component_type);
        else 
          data_point =db_data.reference_data.(system_type).(technology_type).(component_type){1,j};
        endif

        % Collect x-y pairs for current subdivision
        for i=1:numel(data_point)
          if isfield(data_point, field_x) && isfield(data_point, field_y) && isfield(data_point, add_dim)
              % Validate that fields contain numeric data (not structs or cells)
              % This prevents "cannot assign struct to matrix" errors
              field_x_value = data_point.(field_x);
              field_y_value = data_point.(field_y);
              
              if isnumeric(field_x_value) && isnumeric(field_y_value) && ...
                 ~iscell(field_x_value) && ~iscell(field_y_value) && ...
                 ~isstruct(field_x_value) && ~isstruct(field_y_value)
                  % Collect numeric data values
                  x = [x field_x_value];
                  y = [y field_y_value];
              endif
          endif
        end
        
          % Generate filename including subdivision identifier
          filename = strcat(path,"scaling_",system_type,"_",technology_type,"_",component_type,"_with_",add_dim,"_",char(distinct_cases(j)),"_",field_x,"_to_",field_y,".csv");

        % Only write file if valid data was collected
        if not( sum(eq(size(y),[0 0]))+sum(eq(size(x),[0 0])) || iscell(y) || iscell(x) || isstruct(y) || isstruct(x))
          write_selected_data_to_file(x,y,filename,0);
         endif
      endfor


  else % ===== CASE 2: GENERIC MODE (NO SUBDIVISION) =====
       % Combine all data into single scaling law
      x = [];
      y = [];
      
      % Walk through all component instances in database
      n_cases = numel(db_data.reference_data.(system_type).(technology_type).(component_type));
      for i=1:n_cases
        % Access component data (handle single struct vs cell array)
        if n_cases == 1
           data_point =db_data.reference_data.(system_type).(technology_type).(component_type);
        else
          data_point =db_data.reference_data.(system_type).(technology_type).(component_type){1,i};
        endif

        % Check for field existence in current component
        if isfield(data_point, field_x) && isfield(data_point, field_y)
              % Validate that fields contain numeric data (not structs or cells)
              % This prevents "cannot assign struct to matrix" errors
              field_x_value = data_point.(field_x);
              field_y_value = data_point.(field_y);
              
              if isnumeric(field_x_value) && isnumeric(field_y_value) && ...
                 ~iscell(field_x_value) && ~iscell(field_y_value) && ...
                 ~isstruct(field_x_value) && ~isstruct(field_y_value)
                  % Collect numeric data values
                  x = [x field_x_value];
                  y = [y field_y_value];
              endif
        endif
      end
      
        % Generate generic filename without subdivision
        filename = strcat(path,"scaling_",system_type,"_",technology_type,"_",component_type,"_",field_x,"_to_",field_y,".csv");
        
        % Only write file if valid data was collected (defense against empty/invalid arrays)
        if not( sum(eq(size(y),[0 0]))+sum(eq(size(x),[0 0])) || iscell(y) || iscell(x) || isstruct(y) || isstruct(x))
        write_selected_data_to_file(x,y,filename,0);
        endif
  end
end

