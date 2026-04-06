function [c_e power_thruster power_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_c_e(data, propulsion, propellant, F, power_propulsion)
  % returns c_e, thruster input power, jet power and efficiencies for a propulsion+propellant case with thrust
  
  eff_ppu = 1;
  if isfield(data.(propulsion),'ppu')
    eff_ppu = get_ppu_eff(data.(propulsion).ppu);
  end
  power_thruster = power_propulsion * eff_ppu;

  if strcmp(propulsion, 'chemical')
    % Chemical propulsion: c_e (Isp*g0) is thermochemically determined, not from electrical power.
    % Derive c_e directly from DB range; power_jet = 0.5*F*c_e (enthalpy-based).
    % eff_thruster is combustion/nozzle efficiency, independent of electrical input.
    eff_thruster = literature_fallback_efficiency('chemical', propellant);
    dummy = struct('propellant', propellant);
    [c_e_min, c_e_max] = search_min_max(data.(propulsion).thruster, dummy, 'c_e', 'propellant');
    if isnan(c_e_min) || isnan(c_e_max) || c_e_max <= 0
      c_e = 1500;  % last-resort fallback [m/s], ~Isp 150s
    else
      c_e = (c_e_min + c_e_max) / 2;
    end
    power_jet = 0.5 * F * c_e;
    return;
  end

  eff_thruster = get_thruster_eff(data.(propulsion).thruster, propellant, power_thruster, propulsion);
  power_thruster = power_propulsion*eff_ppu;
  power_jet = power_thruster*eff_thruster;
  c_e = 2*power_jet/F; 
  
  dummy_struct = struct;
  dummy_struct.propellant = propellant;
  
  [c_e_min c_e_max] = search_min_max(data.(propulsion).thruster, dummy_struct, 'c_e', 'propellant');

  % Only clamp when a valid DB range exists (c_e_max=0 means no match was found).
  if c_e_max > 0 && c_e > c_e_max
      c_e = c_e_max;
  endif
end