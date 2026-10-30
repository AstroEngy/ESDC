% m_scale_PV  Estimate solar-cell mass from required power output.
% Loads from Database/Scaling/*.yaml (falls back to *.csv with a warning).
% NOTE: this function is currently unused; PV sizing is in analysis_power_system.m.
function [m_PV] = m_scale_PV(P_out, db_data)
  stem = 'Database/Scaling/scaling_power_generation_photovoltaic_cell_mass_to_power_max';
  if exist([stem '.yaml'], 'file') || exist([stem '.csv'], 'file')
    law  = scaling_law_load(stem);
    m_PV = scaling_law_evaluate(law, P_out, 'invert', true);
  else
    m_PV = 0;
  end
end
