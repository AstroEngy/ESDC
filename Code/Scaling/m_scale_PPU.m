function [m_PPU] = m_scale_PPU(P_thruster, propulsion_type)
% Estimate PPU mass from input power using the scaling law database.
% Loads from Database/Scaling/*.yaml (falls back to *.csv with a warning).
  stem = strcat('Database/Scaling/scaling_propulsion_system_', propulsion_type, '_ppu_mass_to_power');
  if exist([stem '.yaml'], 'file') || exist([stem '.csv'], 'file')
    law   = scaling_law_load(stem);
    m_PPU = scaling_law_evaluate(law, P_thruster, 'invert', true);
  else
    m_PPU = 0;
  end
end