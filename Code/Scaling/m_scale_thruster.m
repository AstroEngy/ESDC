function [m_thruster] = m_scale_thruster(P_thruster, propulsion_type, propellant, db_data) 
% Estimate thruster mass from jet power using the scaling law database.
% Loads from Database/Scaling/*.yaml; generates from DB if YAML is absent.
  if nargin < 4
    db_data = [];
  end

  safe_prop = sanitize_identifier(propellant);
  stem = strcat('Database/Scaling/scaling_propulsion_system_', propulsion_type, ...
                '_thruster_with_propellant_', safe_prop, '_mass_to_power_jet');

  if ~exist([stem '.yaml'], 'file')
    % Generate YAML from the reference database
    csv_path = [stem '.csv'];  % write_selected_data_to_file still accepts .csv stem
    create_new_correlation_file_mass_to_power_jet(csv_path, propulsion_type, propellant, db_data);
    scaling_law_cache('clear');
  end

  if exist([stem '.yaml'], 'file')
    law       = scaling_law_load(stem);
    m_thruster = scaling_law_evaluate(law, P_thruster, 'invert', true);
  else
    m_thruster = 0;
  end
end


function  [] = create_new_correlation_file_mass_to_power_jet(filename, propulsion_type, propellant, db_data)
  % Use pre-loaded db_data if available, otherwise fall back to reading from disk
  if isempty(db_data) || ~isstruct(db_data) || ~isfield(db_data, 'reference_data')
    data = read_reference_data();
  else
    data = db_data;
  end
  % read data, get calculate data points

  data_thruster =  data.reference_data.propulsion_system.(propulsion_type).thruster;
  %class(data_thruster) % has to be cell
  %size(data_thruster) % has to be 1 x n cell 
  
  %convert to single entry cell array if single element was converted to struct
  if isstruct(data_thruster)
    data_switcher= data_thruster;
    data_thruster = cell();
    data_thruster{1} = data_switcher;
  endif
  
 % disp(data_thruster)
 % class(data_thruster)
  
  n_candidates = size(data_thruster,2);
  list_mass= [];
  list_power_jet = [];

  for i=1:n_candidates
    entry = data_thruster{1,i};

    % Filter by propellant if specified
    if ~isempty(propellant) && isfield(entry, 'propellant')
      if ~strcmp(entry.propellant, propellant)
        continue;
      end
    end

    % Must have a scalar mass
    if ~isfield(entry, 'mass')
      continue;
    end
    mass_val = scalar_struct_field(entry, 'mass');
    if isnan(mass_val)
      continue;
    end

    % Compute jet power from best available data
    if isfield(entry, 'power_jet')
      power_jet = scalar_struct_field(entry, 'power_jet');
    elseif isfield(entry, 'thrust') && isfield(entry, 'c_e')
      F   = scalar_struct_field(entry, 'thrust');
      c_e = scalar_struct_field(entry, 'c_e');
      power_jet = 0.5 * F * c_e;
    elseif isfield(entry, 'thrust') && isfield(entry, 'massflow')
      F     = scalar_struct_field(entry, 'thrust');
      m_dot = scalar_struct_field(entry, 'massflow');
      power_jet = 0.5 * F^2 / m_dot;
    else
      continue;  % skip entries with insufficient data
    end

    if isnan(power_jet) || isnan(mass_val) || power_jet <= 0 || mass_val <= 0
      continue;
    end

    list_mass      = [list_mass      mass_val];
    list_power_jet = [list_power_jet power_jet];
  endfor

  if isempty(list_mass)
    warning('m_scale_thruster: no valid data found for %s / %s, using dummy scaling', propulsion_type, propellant);
    list_mass      = [1, 2];
    list_power_jet = [100, 200];
  else
    % Sort by power_jet and average masses for duplicate power_jet values
    [list_power_jet, sort_idx] = sort(list_power_jet);
    list_mass = list_mass(sort_idx);
    [unique_pj, ia, ~] = unique(list_power_jet, 'stable');
    unique_mass = zeros(size(unique_pj));
    for k = 1:numel(unique_pj)
      unique_mass(k) = mean(list_mass(list_power_jet == unique_pj(k)));
    endfor
    list_power_jet = unique_pj;
    list_mass      = unique_mass;

    if numel(list_mass) == 1
      list_mass      = [list_mass      list_mass(1)*2];
      list_power_jet = [list_power_jet list_power_jet(1)*2];
    endif
  endif

  write_selected_data_to_file(list_mass, list_power_jet, filename, 0);
  %list_mass
  %list_power_jet
  % fit according to algo
  
  % write .csv file for the polynomial

endfunction

function val = scalar_struct_field(s, fname)
  % Extract a representative scalar from a field that may be a scalar or min/max struct.
  if ~isfield(s, fname)
    val = NaN;
  elseif isstruct(s.(fname))
    if isfield(s.(fname), 'min') && isfield(s.(fname), 'max')
      val = (s.(fname).min + s.(fname).max) / 2;
    else
      val = NaN;
    end
  else
    val = s.(fname);
  end
endfunction
