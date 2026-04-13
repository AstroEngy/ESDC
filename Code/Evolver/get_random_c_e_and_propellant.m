function [c_e propellant] = get_random_c_e_and_propellant(data, propulsion, mode)
  %initialization case of unknown c_e and propellant
  % mode (optional): 'high' selects from upper half of c_e range,
  %                  'low'  selects from lower half, omit for full range
  if nargin < 3
    mode = 'any';
  end
  n_thrusters = size(data.(propulsion).thruster,2);
  c_e_list  = [];
  propellant_list = {};
  
  if n_thrusters == 1
    c_e = scalar_field(data.(propulsion).thruster, 'c_e');
    if isfield(data.(propulsion).thruster, 'propellant')
      propellant = data.(propulsion).thruster.propellant;
    else
      propellant = 'unknown';
    end
  else
    for i=1:n_thrusters
        val = scalar_field(data.(propulsion).thruster{i}, 'c_e');
        c_e_list(end+1) = val;  % NaN if field missing or non-numeric
        if isfield(data.(propulsion).thruster{i}, 'propellant')
          propellant_list{1,end+1} = data.(propulsion).thruster{i}.propellant;
        else
          propellant_list{1,end+1} = 'unknown';
        end
    end
    
    % Remove entries without a valid c_e
    valid = ~isnan(c_e_list);
    c_e_list = c_e_list(valid);
    propellant_list = propellant_list(valid);
    n_valid = numel(c_e_list);

    if n_valid == 0
      error('get_random_c_e_and_propellant: no thruster with valid c_e found for propulsion type "%s" — skipping this selection.', propulsion);
    end

    % Apply mode filter
    c_e_median = median(c_e_list);
    if strcmp(mode, 'high')
      idx = find(c_e_list >= c_e_median);
    elseif strcmp(mode, 'low')
      idx = find(c_e_list <= c_e_median);
    else
      idx = 1:n_valid;
    end
    if isempty(idx)
      idx = 1:n_valid;
    end
    n_case = idx(randi(numel(idx)));
    c_e = c_e_list(n_case);
    propellant = propellant_list{n_case};
    
  end
end

function val = scalar_field(s, fname)
  % Extract a scalar from a field that may be a scalar, a min/max struct, or a
  % cell array (from duplicate XML tags). In the cell case, recurse on the first
  % element that resolves to a finite scalar.
  if ~isfield(s, fname)
    val = NaN;
  elseif iscell(s.(fname))
    val = NaN;
    for _ci = 1:numel(s.(fname))
      tmp_s.(fname) = s.(fname){_ci};
      candidate = scalar_field(tmp_s, fname);
      if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        val = candidate;
        break;
      end
    end
  elseif isstruct(s.(fname))
    % Range given as struct with nominal/min/max
    if isfield(s.(fname), 'nominal')
      val = s.(fname).nominal;
    elseif isfield(s.(fname), 'min') && isfield(s.(fname), 'max')
      val = (s.(fname).min + s.(fname).max) / 2;
    elseif isfield(s.(fname), 'min')
      val = s.(fname).min;
    elseif isfield(s.(fname), 'max')
      val = s.(fname).max;
    else
      val = NaN;
    end
  else
    val = s.(fname);
  end
end