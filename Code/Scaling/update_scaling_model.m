## -*- texinfo -*-
## @deftypefn {} {@var{scaling_model_struct} =} update_scaling_model (@var{force_update_flag})
## Update scaling law database by checking for changes and regenerating CSV files.
##
## Master function that orchestrates the update of all scaling law lookup tables
## from XML reference databases. Checks for database changes using MD5 hashes
## and regenerates scaling law CSV files only when needed, unless forced.
## Processes both component/system scaling and spacecraft scaling.
##
## @strong{Inputs:}
## @table @var
## @item force_update_flag
## Logical flag (0 or 1) to force regeneration of all scaling laws:
## @itemize
## @item 0 - Update only if database files have changed (hash-based detection)
## @item 1 - Force regeneration regardless of database state
## @end itemize
## @end table
##
## @strong{Outputs:}
## @table @var
## @item scaling_model_struct
## Empty return (function signature compatibility). Actual outputs are CSV files
## written to Database/Scaling/ directory.
## @end table
##
## @strong{Side Effects:}
## @itemize
## @item Reads ESDC_Reference_Data_Systems.xml and ESDC_Reference_Data_Spacecrafts.xml
## @item Creates or updates MD5 hash files for change detection
## @item Generates/updates multiple CSV files in Database/Scaling/ directory:
##   - Component scaling laws (mass-to-power, mass-to-thrust, etc.)
##   - Spacecraft scaling laws (total-mass-to-payload, etc.)
## @item Displays status messages during processing
## @end itemize
##
## @strong{Algorithm:}
## @enumerate
## @item Calls update_system_scaling() for component/system scaling laws
## @item Calls update_SC_scaling() for spacecraft scaling laws
## @item Each sub-function handles hash checking and conditional updates
## @end enumerate
##
## @strong{Notes:}
## @itemize
## @item Designed for incremental updates: skips regeneration if data unchanged
## @item Force update useful after code changes or manual database edits
## @item Processing time depends on database size (can take minutes for large DBs)
## @item Database/Scaling/ directory must exist or be writable
## @end itemize
##
## @seealso{update_system_scaling, update_SC_scaling, read_reference_data, read_reference_spacecraft_data}
## @end deftypefn

function [scaling_model_struct] = update_scaling_model(force_update_flag, prefer_xml)
% HOW TO TEST (MATLAB/Octave style — supplements the Texinfo docs above):
%   1. Normal update (hash-based):
%        update_scaling_model(0)
%      Verify that "No update required" is printed for both system and
%      spacecraft sub-functions when no XML has changed.
%   2. Forced rebuild:
%        update_scaling_model(1)
%      Verify that CSV files in Database/Scaling/ have updated timestamps.
%   3. Corrupt a CSV file and run update_scaling_model(0); verify the
%      function does NOT regenerate it (hash still matches original XML).
%      Then manually change a value in the source XML and run again; verify
%      the CSV IS regenerated.
%   4. Test the prefer_xml flag: update_scaling_model(0, true) should read
%      the XML source directly rather than the YAML counterpart.
%   5. After a successful run, call scale_SMAD_parameter() for a known
%      spacecraft (e.g. LEO, 1000 kg) and verify the returned fraction is
%      within the expected SMAD range (e.g. payload fraction 15–35 %).
%
% SAFEGUARDS TO ADD (future work):
%   - Check that at least one CSV is present in Database/Scaling/ after
%     running and raise an error if not (the DB may have been empty).
%   - Validate that CSV fractions are in [0, 1] after generation to catch
%     corrupt or badly formatted source XML.
  if nargin < 2; prefer_xml = false; end
  disp('Database check:');
  
  % System/component scaling: generates CSV lookup tables from component database
  update_system_scaling(force_update_flag, prefer_xml);
  
  % Spacecraft scaling: generates CSV lookup tables from spacecraft database
  update_SC_scaling(force_update_flag, prefer_xml);

end

%% ==========================================================================
%% SPACECRAFT SCALING UPDATE
%% ==========================================================================

## -*- texinfo -*-
## @deftypefn {} {} update_SC_scaling (@var{force_update})
## Update spacecraft scaling laws with hash-based change detection.
##
## Checks if spacecraft reference database has changed using MD5 hash comparison
## and regenerates spacecraft scaling law CSV files only when needed. Hash file
## stores previous database state to enable incremental updates.
##
## @strong{Inputs:}
## @table @var
## @item force_update
## Logical flag (0 or 1) to bypass hash checking and force full regeneration.
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Reads Database/ESDC_Reference_Data_Spacecrafts.xml
## @item Creates/updates Database/ESDC_Reference_Data_Spacecrafts_hash
## @item Generates CSV files via update_generic_spacecraft_scaling_model()
## @item Displays status messages (hash file creation, updates detected, etc.)
## @end itemize
##
## @strong{Algorithm:}
## @enumerate
## @item Check if hash file exists
## @item If exists: compare stored hash with current database MD5
## @item If changed or no hash: regenerate scaling laws and update hash
## @item If @var{force_update}=1: regenerate regardless of hash state
## @end enumerate
##
## @seealso{update_generic_spacecraft_scaling_model, read_reference_spacecraft_data}
## @end deftypefn

function[] = update_SC_scaling(force_update, prefer_xml)
    if nargin < 2; prefer_xml = false; end

    make_update = 0;
    
    % Check if hash file exists for change detection
    if exist("Database/ESDC_Reference_Data_Spacecrafts_hash");
    hash_file = fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "r");
    hash_val = fgetl(hash_file);
    fclose(hash_file);
    
    % Compute current database hash and compare
    current_hash = hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml'));
      if (hash_val == current_hash)
      disp('No updates to spacecraft database detected.');
      else
      disp('Updates to spacecraft database detected.');
        % Load spacecraft data and regenerate scaling laws
        [data] = read_reference_spacecraft_data(prefer_xml);
        
        % Update hash file with new database state
        hash_file= fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "w");
        fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml')));
        fclose(hash_file);
        
        update_generic_spacecraft_scaling_model(data);
        disp('Updates to S/C db complete.');
      end
    else
      % No hash file exists - first run, create it
      disp('No spacecraft database hash file found');
      disp('Creating hash file');
      hash_file= fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "a");
      disp('Write hash');
      fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml')));
      fclose(hash_file);
      make_update = 1;
    end
    
    % Force update overrides hash-based detection
    if (force_update)
      disp('Forcing Spacecraft Database Update');
    end
    
    % Perform update if needed (first run or forced)
    if (make_update | force_update)
      [data] = read_reference_spacecraft_data();
      update_generic_spacecraft_scaling_model(data);
    end
end

%% ==========================================================================
%% SPACECRAFT SCALING MODEL GENERATION
%% ==========================================================================

## -*- texinfo -*-
## @deftypefn {} {} update_generic_spacecraft_scaling_model (@var{data})
## Generate all spacecraft scaling law CSV files from reference data.
##
## Processes spacecraft reference database to create scaling laws correlating
## various spacecraft parameters (mass, power, payload) filtered by orbit type.
## Generates separate CSV files for each orbit type and parameter pair combination.
##
## @strong{Inputs:}
## @table @var
## @item data
## Struct containing spacecraft reference data loaded from XML database.
## Expected structure: data.reference_data_spacecraft.spacecraft (or .reference_data_spracecraft for legacy compatibility).
## Can be struct or cell array; automatically normalized to 1D cell array.
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Generates multiple CSV files in Database/Scaling/ directory
## @item Filename pattern: scaling_spacecraft_@{orbit_type@}_parameter_@{field_x@}_to_@{field_y@}.csv
## @item Correlates predefined fields: m_total, m_payload, p_total, p_payload
## @item Excludes metadata fields: name, launch_year, source, orbit_type, TRL, name_long, comment
## @item Displays progress messages during processing
## @end itemizes
##
## @strong{Algorithm:}
## @enumerate
## @item Extract spacecraft data from input structure (handle struct/cell variants)
## @item Normalize to 1D cell array of spacecraft entry structs
## @item Collect all unique orbit types from entries
## @item Collect all available field names across all entries
## @item For each combination of:
##   - Orbit type (LEO, GEO, etc.)
##   - Predefined correlation field (m_total, m_payload, p_total, p_payload)
##   - Available parameter field (not in exclusion list)
## @item Call update_generic_spacecraft_system_scaling_a_to_b() to generate CSV
## @end enumerate
##
## @strong{Notes:}
## @itemize
## @item Handles both struct and cell array input formats automatically
## @item Supports legacy field name typo (reference_data_spracecraft)
## @item Empty spacecraft entries are safely skipped
## @item Only numeric correlatable fields generate scaling laws
## @item Processing time scales with number of spacecraft × parameter combinations
## @end itemizes
##
## @seealso{update_generic_spacecraft_system_scaling_a_to_b, read_reference_spacecraft_data}
## @end deftypefn

function [] =  update_generic_spacecraft_scaling_model(data)
  
    % Exclusion list: metadata fields that should not be correlated numerically
    exclusion_list =    {'name', 'launch_year', 'source', 'orbit_type','TRL','name_long', 'comment'};
    disp('Updating spacecraft scaling models');
    
    % === Extract spacecraft data from input structure ===
    % Handle field name variations (correct vs legacy typo)
    if isfield(data, 'reference_data_spacecraft')
      ref_field = data.reference_data_spacecraft;
    elseif isfield(data, 'reference_data_spracecraft')  % fallback for legacy typo
      ref_field = data.reference_data_spracecraft;
    else
      error('update_generic_spacecraft_scaling_model: missing field ''reference_data_spacecraft'' in input data');
    end
    
    % === Normalize spacecraft data structure ===
    % Handle both cell array and struct formats from XML reader
    if iscell(ref_field)
      % If it's a cell array, extract first element
      scdata = ref_field{1,1}.spacecraft;
    elseif isstruct(ref_field) && isfield(ref_field, 'spacecraft')
      % If it's a struct with spacecraft field, access directly
      scdata = ref_field.spacecraft;
    else
      error('update_generic_spacecraft_scaling_model: unexpected reference data structure');
    end

    % Convert to 1D cell array of spacecraft structs for uniform iteration
    if iscell(scdata)
      rawEntries = scdata(:);  % Ensure column vector
    elseif isstruct(scdata)
      % Convert struct array to cell array for consistent indexing
      rawEntries = num2cell(scdata(:));
    else
      error('update_generic_spacecraft_scaling_model: unexpected spacecraft data type');
    end

    % === Compute derived geometry field: volume_box = size_x * size_y * size_h ===
    % Adds volume_box to each entry that has all three size dimensions so that
    % the scaling loop below can generate a mass_total → volume_box CSV automatically.
    for i = 1:numel(rawEntries)
      if isempty(rawEntries{i}); continue; end
      e = rawEntries{i};
      if isfield(e,'size_x') && isfield(e,'size_y') && isfield(e,'size_h') && ...
         ~isempty(e.size_x) && ~isempty(e.size_y) && ~isempty(e.size_h)
        vx = e.size_x; vy = e.size_y; vh = e.size_h;
        if isnumeric(vx) && isnumeric(vy) && isnumeric(vh)
          rawEntries{i}.volume_box = vx * vy * vh;
        end
      end
    end
    % Determine which fields are available across all spacecraft entries
    allFieldNames = {};
    for i = 1:numel(rawEntries)
      if isempty(rawEntries{i})
        continue;
      end
      fn = fieldnames(rawEntries{i});
      allFieldNames = [allFieldNames; fn];
    end
    allFieldNames = unique(allFieldNames);

    % Collect unique orbit types for filtering (LEO, GEO, MEO, etc.)
    distinct_orbit_cases  = {};
    for i=1:numel(rawEntries)
      if ~isempty(rawEntries{i}) && isfield(rawEntries{i}, 'orbit_type')
        distinct_orbit_cases{i}=rawEntries{i}.orbit_type;
      else
        distinct_orbit_cases{i} = '';
      end
    end
    distinct_orbit_cases = unique(distinct_orbit_cases);

    % Collect all unique field names available for correlation  
    all_fields = {};
    for i=1:numel(rawEntries)
      if ~isempty(rawEntries{i})
        case_fields = fieldnames(rawEntries{i});
        all_fields = [all_fields; case_fields];
      end
    end
    all_fields = unique(all_fields);

    % === Generate scaling law CSV files ===
    % Predefined parameters to use as independent variables in correlations
    to_correlate = {'mass_total','mass_payload','power_total','power_payload'}; 
    
    % Triple nested loop: orbit types × correlation variables × all fields
    for i=1: numel(distinct_orbit_cases);
      for j=1:numel(to_correlate)
       for k=1:numel(all_fields)
         % Skip fields in exclusion list (non-numeric metadata)
         if sum(strcmp(all_fields{k},exclusion_list))
           % Field excluded, skip correlation
         else
          % Generate scaling law CSV for this orbit type and parameter pair
          update_generic_spacecraft_system_scaling_a_to_b(rawEntries,char(distinct_orbit_cases{i}),char(to_correlate{j}),char(all_fields{k}));
         end
       end
      end
    end
  
   disp('Updating Spacecraft system scalings complete');
end



function [] = update_system_scaling(force_update, prefer_xml)
  if nargin < 2; prefer_xml = false; end
  make_update = 0;

  % Check if hash file exists for change detection
  if exist("Database/ESDC_Reference_Data_Systems_hash")
    hash_file = fopen('Database/ESDC_Reference_Data_Systems_hash', "r");
    hash_val = fgetl(hash_file);
    fclose(hash_file);

    % Compute current database hash and compare
    current_hash = hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml'));
    if (hash_val == current_hash)
      disp('No updates to database detected.');
    else
      disp('Updates to database detected.');
      make_update = 1;
    end
  else
    % No hash file exists - first run
    disp('No database hash file found');
    make_update = 1;
  end

  % Force update overrides hash-based detection
  if force_update
    disp('Forcing Component Database Update');
  end

  % Perform update if needed (first run or forced)
  % Hash file is only written after a successful update
  if (make_update | force_update)
    [data] = read_reference_data(prefer_xml);
    update_generic_component_scaling_model(data);
    % Update succeeded - now persist the new hash
    disp('Writing database hash file');
    hash_file = fopen('Database/ESDC_Reference_Data_Systems_hash', "w");
    fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml')));
    fclose(hash_file);
    disp('Updates complete.');
  end
end

%% ==========================================================================
%% COMPONENT SCALING MODEL GENERATION
%% ==========================================================================

## -*- texinfo -*-
## @deftypefn {} {} update_generic_component_scaling_model (@var{data})
## Generate all component scaling law CSV files from reference data.
##
## Processes component reference database to create scaling laws correlating
## component parameters (mass, power, thrust, etc.) across the system hierarchy:
## system type → technology type → component type → parameters. Special handling
## for thruster data with propellant-specific subdivisions.
##
## @strong{Inputs:}
## @table @var
## @item data
## Struct containing component reference data loaded from XML database.
## Expected structure: data.reference_data.@{system_type@}.@{technology_type@}.@{component_type@}
## with parameter fields (mass, power, thrust, etc.) in each component entry.
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Generates multiple CSV files in Database/Scaling/ directory
## @item Filename patterns:
##   - Generic: scaling_@{system@}_@{tech@}_@{component@}_@{field_x@}_to_@{field_y@}.csv
##   - Propellant: scaling_@{system@}_@{tech@}_thruster_with_propellant_@{prop@}_@{field_x@}_to_@{field_y@}.csv
## @item Displays progress messages during processing
## @end itemizes
##
## @strong{Algorithm:}
## @enumerate
## @item Iterate through system types (propulsion_system, power_system, etc.)
## @item For each system, iterate through technology types (arcjet, GIT, etc.)
## @item For each technology, iterate through component types (thruster, ppu, etc.)
## @item For each component, iterate through all parameters
## @item Special case: thrusters get propellant-subdivided scaling laws
## @item Generic case: all other components get combined scaling laws
## @item Call update_generic_component_scaling_a_to_b() for each correlation
## @end enumerate
##
## @strong{Notes:}
## @itemize
## @item Thruster parameters are correlated against mass with propellant subdivision
## @item All other components correlate parameters against mass without subdivision
## @item Skips 'system' parameter fields (metadata, not correlatable)
## @item Handles both single struct and cell array component data
## @item Processing time scales with database size (system × technology × component × parameter)
## @end itemizes
##
## @seealso{update_generic_component_scaling_a_to_b, read_reference_data}
## @end deftypefn

function [] =  update_generic_component_scaling_model(data)
disp('Starting updating of scaling data');
disp('');

% === Iterate through system hierarchy ===
% Level 1: System types (propulsion_system, power_system, communication, etc.)
system_type_names=fieldnames(data.reference_data);

for k=1:numel(system_type_names)
  
  % Level 2: Technology types within each system (arcjet, gridded_ion_thruster, etc.)
  technology_type_names=fieldnames(data.reference_data.(char(system_type_names(k))));
  for i=1:numel(technology_type_names)

    % Level 3: Component types within each technology (thruster, ppu, solar_cell, etc.)
    component_type_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))));
    for j=1:numel(component_type_names)
      % Handle both struct and cell array component data
      component_data = data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j)));
      if iscell(component_data)
        % Cell array format - use first element for fieldnames
        parameter_names=fieldnames(component_data{1,1});
      elseif isstruct(component_data)
        % Struct format
        parameter_names=fieldnames(component_data);
      else
        % String or other scalar - not indexable for fieldnames, skip
        continue;
      end
      
      % Skip metadata 'system' fields
      if strcmp(parameter_names,"system") 
        break;
      end
      
        % Level 4: Parameters within each component (mass, power, thrust, etc.)
        for l=1:numel(parameter_names)
          % Special case: thruster parameters use propellant subdivision
          if strcmp(char(component_type_names(j)),'thruster')
          update_generic_component_scaling_a_to_b(data,char(system_type_names(k)),char(technology_type_names(i)),char(component_type_names(j)),'mass',char(parameter_names(l)), 'propellant');
          else
          % Generic case: all other components without subdivision
          update_generic_component_scaling_a_to_b(data,char(system_type_names(k)),char(technology_type_names(i)),char(component_type_names(j)),'mass',char(parameter_names(l)));
          end
        end

    end
  end
end

disp('');
disp('Updating scaling data complete');
disp('');

end