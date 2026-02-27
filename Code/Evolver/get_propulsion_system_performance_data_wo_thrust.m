function [thrust power_thruster power_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_thrust(data, propulsion, propellant, c_e, power_propulsion)
  % returns thrust, jet oiwer and efficiencies for given propulsion+propellant case for a specific c_e

  eff_ppu = 1;
  if isfield(data.(propulsion),'ppu')
    eff_ppu = get_ppu_eff(data.(propulsion).ppu);
  end
  power_thruster = power_propulsion * eff_ppu;
  eff_thruster = get_thruster_eff(data.(propulsion).thruster, propellant, power_thruster, propulsion);
  if isnan(c_e) || isempty(c_e) || c_e == 0
    % fallback: estimate c_e from database range
    dummy = struct('propellant', propellant);
    [c_e_min, c_e_max] = search_min_max(data.(propulsion).thruster, dummy, 'c_e', 'propellant');
    if c_e_max > 0
      c_e = (c_e_min + c_e_max) / 2;
    else
      c_e = 1;  % last-resort fallback
    end
  end
  power_thruster = power_propulsion*eff_ppu;
  power_jet = power_thruster*eff_thruster;
  thrust = 2*power_jet/c_e; 
end