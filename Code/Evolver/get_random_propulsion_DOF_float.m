function DOF_return = get_random_propulsion_DOF_float(data, propulsion, propellant, DOF)
    % get a randomized number of a float degree of freedom from the propulsion system , applicable for c_e and F floats currently
    DOF_list = [];
    n_thruster_entries = size(data.(propulsion).thruster, 2);

    % First pass: collect values matching the requested propellant
    for i = 1:n_thruster_entries
      if n_thruster_entries == 1
        sub_data = data.(propulsion).thruster;
      else
        sub_data = data.(propulsion).thruster{i};
      end
      % Skip entries missing the DOF field or propellant field
      if ~isfield(sub_data, 'propellant') || ~isfield(sub_data, DOF)
        continue;
      end
      if strcmp(sub_data.propellant, propellant)
        DOF_list = append_field_values(DOF_list, sub_data.(DOF));
      end
    end

    % Fallback: if no propellant-matched entries, use full range across all thrusters
    if isempty(DOF_list)
      for i = 1:n_thruster_entries
        if n_thruster_entries == 1
          sub_data = data.(propulsion).thruster;
        else
          sub_data = data.(propulsion).thruster{i};
        end
        if ~isfield(sub_data, DOF)
          continue;
        end
        DOF_list = append_field_values(DOF_list, sub_data.(DOF));
      end
    end

    if isempty(DOF_list)
      DOF_return = NaN;
    else
      DOF_return = rand_range(min(DOF_list), max(DOF_list));
    end
end

function list = append_field_values(list, val)
  % Append a scalar or min/max struct value to a list
  if isstruct(val)
    if isfield(val, 'min') && isfield(val, 'max')
      list = [list; val.min; val.max];
    end
  else
    list = [list; val];
  end
end