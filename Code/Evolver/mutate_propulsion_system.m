function individual_data = mutate_propulsion_system(individual_data, db_data)
  %disp('attempt propulsion system mutation')
  list_propulsion_systems = fieldnames(db_data.reference_data.propulsion_system);

  % Restrict to compatible technologies when thrust_mode is set
  thrust_mode = '';
  if isfield(individual_data, 'thrust_mode') && ~isempty(individual_data.thrust_mode)
    thrust_mode = individual_data.thrust_mode;
  end
  if ~isempty(thrust_mode)
    dof_filtered = filter_dof_by_thrust_mode(db_data.DOF, thrust_mode);
    compatible = fieldnames(dof_filtered.propulsion_system);
    list_propulsion_systems = compatible;
  end

  while 1
    n_propulsion_system = randi(numel(list_propulsion_systems));
    propulsion_system_new = list_propulsion_systems{n_propulsion_system,1};
  if !isequal(propulsion_system_new,individual_data.propulsion_system) && !strcmp(propulsion_system_new,'tank')
  %disp('New propulsion systems selected!')
    individual_data.propulsion_system = propulsion_system_new;
    break
  end
end

%todo: bug propulsion system tank/vessel wrongly declared
individual_data.propellant = get_random_propellant(db_data.reference_data.propulsion_system, individual_data.propulsion_system);

[c_e_min c_e_max] = search_min_max(db_data.reference_data.propulsion_system.(individual_data.propulsion_system).thruster, individual_data, 'c_e', 'propellant');

%Lower cap new c_e
if c_e_min > individual_data.c_e
  individual_data.c_e = c_e_min;
end
%Upper cap new c_e
if c_e_max < individual_data.c_e
  individual_data.c_e = c_e_max;
end
%disp(individual_data)

if isfield(db_data.reference_data.propulsion_system.(individual_data.propulsion_system),'ppu')
  individual_data.eff_PPU = get_ppu_eff(db_data.reference_data.propulsion_system.(individual_data.propulsion_system).ppu);
end
%update efficiency of thruster for new propellant
individual_data.eff_thruster = get_thruster_eff(db_data.reference_data.propulsion_system.(individual_data.propulsion_system).thruster, individual_data.propellant, NaN, individual_data.propulsion_system);

% update jet power and thrust.
% Chemical propulsion: thrust is thermochemical (enthalpy-based), not derived from
% electrical power.  refresh_thrust = 2*P_jet/c_e applies only to EP technologies.
% For chemical, read thrust directly from the DB average for this propellant so that
% the individual has a physically representative thrust from the first generation onwards.
if strcmp(individual_data.propulsion_system, 'chemical')
  dummy_prop = struct('propellant', individual_data.propellant);
  [F_lo, F_hi] = search_min_max(db_data.reference_data.propulsion_system.chemical.thruster, ...
    dummy_prop, 'thrust', 'propellant');
  if isnan(F_lo) || isnan(F_hi) || F_hi <= 0
    individual_data.thrust = 1;  % last-resort fallback [N]
  else
    individual_data.thrust = (F_lo + F_hi) / 2;
  end
  % Power jet is enthalpy-based: P_jet = 0.5 * F * c_e (kinetic power, no PPU involved).
  individual_data.power_jet = 0.5 * individual_data.thrust * individual_data.c_e;
else
  individual_data.power_jet = refresh_power_jet(individual_data);
  individual_data.thrust = refresh_thrust(individual_data);
end

end