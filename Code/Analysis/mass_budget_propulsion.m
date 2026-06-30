% mass_budget_propulsion — Compute propulsion subsystem component masses
%
% PURPOSE:
%   Estimates the dry mass of each propulsion hardware component (tank,
%   thruster, and optionally PPU) using component-specific scaling laws from
%   the database, then sums them into a total propulsion dry mass.
%   This replaces the generic SMAD fraction used during SMAD_scalings with a
%   higher-fidelity, physics-based estimate anchored to the specific
%   technology and propellant.
%
% INTENT:
%   Called after every mutation in evolve_population() to refine the
%   propulsion mass after a technology/thrust/c_e change.  The difference
%   (d_EP = this total - SMAD estimate) is applied to the margin budget so
%   the spacecraft total mass remains self-consistent.
%
% Component mass models:
%   Tank:     m_scale_tank(m_propellant, propellant)   — volume-based scaling
%   Thruster: m_scale_thruster(power, system, propellant) — power-based scaling
%   PPU:      m_scale_PPU(power, system)               — power-based scaling
%             (only if a CSV scaling file exists for this propulsion type)
%
% Parameters:
%   data            (struct): Current population member.  Required fields:
%                     .propellant       (string)
%                     .propulsion_system (string)
%                     .power_thruster   [W]
%   mass_propellant (float): Propellant mass [kg] from SMAD_scalings.
%   db_data         (struct, optional): Reference database.  Passed to
%                   m_scale_tank and m_scale_thruster for DB-backed scaling.
%                   May be empty ([]) when database is not available.
%
% Returns:
%   mass_epropulsion_power (struct):
%     .tank     [kg] — tank + pressurant vessel mass
%     .thruster [kg] — thruster cluster mass
%     .PPU      [kg] — power processing unit mass (if applicable)
%     .total    [kg] — sum of all component masses above
%
% HOW TO TEST:
%   1. For a known thruster (e.g. Hydrazine monoprop, 1 N, 200 g thruster),
%      verify the output .thruster is in the right order of magnitude.
%   2. Verify .total == .tank + .thruster (+ .PPU if present).
%   3. Supply an EP type (e.g. HET) and confirm .PPU is present in output.
%   4. Supply a chemical type (cold gas) and confirm .PPU is absent.
%   5. Verify no NaN or negative mass fields are returned.
%
% SAFEGUARDS TO ADD (future work):
%   - Guard against mass_propellant <= 0 (returns a zero tank, which
%     could silently hide an upstream error).
%   - Validate that .total > 0 before returning.
%   - Warn when no PPU scaling file is found for an EP type (currently
%     silently omits PPU from the mass budget, understating dry mass).
function [mass_epropulsion_power ] = mass_budget_propulsion(data, mass_propellant, db_data)
  if nargin < 3
    db_data = [];
  end
  
  mass_epropulsion_power = struct();

  % ---- Component-level mass estimates -------------------------------------
  mass_epropulsion_power.tank     = m_scale_tank(mass_propellant, data.propellant, db_data);
  mass_epropulsion_power.thruster = m_scale_thruster(data.power_thruster, data.propulsion_system, data.propellant, db_data); % Thruster mass estimation by correlation
  
  % ---- PPU: only present for electric propulsion types --------------------
  % Check for PPU scaling CSV; if it exists this is an EP system that needs a PPU.
  filename = strcat("Database/Scaling/scaling_propulsion_system_",data.propulsion_system, "_ppu_mass_to_power.csv");
  if exist(filename)
     mass_epropulsion_power.PPU = m_scale_PPU(data.power_thruster, data.propulsion_system);
  end
  
  % ---- Sum all component masses -------------------------------------------
  % Piping, valves and structure are NOT included here (handled separately
  % by select_propulsion_components with a PIPING_FRACTION post-hoc factor).
  fields_mass = fieldnames(mass_epropulsion_power);
  mass_total = 0;
  for i=1:numel(fields_mass);
      mass_total = mass_total + mass_epropulsion_power.(fields_mass{i});
  end
  
  mass_epropulsion_power.total = mass_total;
end