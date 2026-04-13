function eff_thruster = get_thruster_eff(data, propellant, power_in, propulsion_type)
  %returns the efficiency of a certain thruster type for a specific propellant
  % power_in (optional): mission thruster input power (power_propulsion * eff_ppu),
  %   used as P_in fallback when the DB entry has no 'power' field.
  % propulsion_type (optional): technology string used for literature-based fallback.
  if nargin < 3
    power_in = NaN;
  end
  if nargin < 4
    propulsion_type = '';
  end

  % --- Chemical propulsion: efficiency concept is combustion/nozzle, not electrical ---
  % P_jet / P_electrical is physically meaningless for chemical thrusters.
  % Return combustion efficiency directly; see literature_fallback_efficiency for value & source.
  if strcmp(propulsion_type, 'chemical')
    eff_thruster = literature_fallback_efficiency('chemical', propellant);
    return;
  end

  n_thruster = size(data,2);
  if n_thruster==1
    if isfield(data,'efficiency')
      eff_thruster = scalar_field(data, 'efficiency');
    else
      efficiency_calculated = calculate_thruster_efficiency(data, power_in);
      eff_thruster = efficiency_calculated;
    end
  else
    eff_thruster_list = [];
    for i=1:n_thruster
      if ~isfield(data{i}, 'propellant') || ~strcmp(data{i}.propellant, propellant)
        continue;
      endif
      if isfield(data{i},'efficiency')
        val = scalar_field(data{i}, 'efficiency');
      else
        val = calculate_thruster_efficiency(data{i}, power_in);
      end
      if ~isnan(val)
        eff_thruster_list = [eff_thruster_list; val];
      end
    end
    if isempty(eff_thruster_list)
      eff_thruster = NaN;
    else
      eff_thruster = average_array(eff_thruster_list);
    end
  end

  % --- Literature-based fallback when no DB or calculated efficiency is available ---
  if isnan(eff_thruster) || isempty(eff_thruster)
    eff_thruster = literature_fallback_efficiency(propulsion_type, propellant);
  end
end



function efficiency = calculate_thruster_efficiency(data, power_in)
  % Compute thruster jet efficiency (P_jet / P_in) from available DB fields.
  % Priority: direct DB data always takes precedence; mission power_in is fallback for P_in.
  if nargin < 2
    power_in = NaN;
  end

  % --- Determine P_jet (all DB-based options, in priority order) ---
  if isfield(data, 'power_jet')
    P_jet = scalar_field(data, 'power_jet');
  elseif isfield(data, 'thrust') && isfield(data, 'c_e')
    F   = scalar_field(data, 'thrust');
    c_e = scalar_field(data, 'c_e');
    P_jet = 0.5 * F * c_e;
  elseif isfield(data, 'thrust') && isfield(data, 'massflow')
    F     = scalar_field(data, 'thrust');
    m_dot = scalar_field(data, 'massflow');
    P_jet = 0.5 * F^2 / m_dot;
  else
    P_jet = NaN;
  endif

  % --- Determine P_in (DB field takes precedence, mission power_in as fallback) ---
  if isfield(data, 'power')
    P_in = scalar_field(data, 'power');
  elseif ~isnan(power_in)
    P_in = power_in;
  else
    P_in = NaN;
  endif

  % --- Compute efficiency ---
  if isnan(P_jet)
    %warning('get_thruster_eff: insufficient data to calculate thruster efficiency, will use literature fallback');
    efficiency = NaN;
  elseif isnan(P_in) || P_in == 0
    %warning('get_thruster_eff: no input power of thruster given, will use literature fallback');
    efficiency = NaN;
  else
    efficiency = P_jet / P_in;
  endif
endfunction

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
endfunction
