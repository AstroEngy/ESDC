function [disp_label, disp_unit] = plot_quantity_label(quantity_id, unit_hint)
% plot_quantity_label  Translate a quantity identifier into a readable display label and unit.
%
% [label, unit] = plot_quantity_label(quantity_id)
% [label, unit] = plot_quantity_label(quantity_id, unit_hint)
%
% quantity_id  — string from law.input.quantity or law.output.quantity
% unit_hint    — unit string from the law; used as fallback for unknown identifiers
%
% Returns:
%   disp_label  — human-readable label, e.g. 'Effective exhaust velocity'
%   disp_unit   — unit string, e.g. 'm/s'
%
% Unit strings are kept as plain ASCII for compatibility with text
% interpreter='none'.  Use the unit in axis labels as "[unit]".
%
% Unknown identifiers emit a warning with the identifier and fallback
% values; add the identifier to the registry below to suppress it.
%
% To add a new quantity:
%   1. Locate the relevant section below.
%   2. Add a line:  reg.identifier = {'Display label', 'unit'};
%   3. Re-run test_plotting to confirm the new entry is reachable.

if nargin < 2; unit_hint = ''; end

% ---- Quantity registry -------------------------------------------------
% Struct fieldnames match quantity_id exactly (underscores preserved).
% Values are 2-element cells: {display_label, unit_string}.
reg = struct();

% Mass (kg)
reg.mass                   = {'Mass',                          'kg'};
reg.mass_total             = {'Total mass',                    'kg'};
reg.mass_payload           = {'Payload mass',                  'kg'};
reg.mass_total_dry         = {'Dry mass',                      'kg'};
reg.mass_propellant        = {'Propellant mass',               'kg'};
reg.structure_mass         = {'Structure mass',                'kg'};

% Power (W)
reg.power                  = {'Electrical power',              'W'};
reg.power_total            = {'Total power',                   'W'};
reg.power_jet              = {'Jet power',                     'W'};
reg.power_nom              = {'Nominal power',                 'W'};
reg.power_nominal          = {'Nominal power',                 'W'};
reg.power_max              = {'Maximum power',                 'W'};
reg.static_power_consumption = {'Static power consumption',   'W'};

% Propulsion
reg.thrust                 = {'Thrust',                        'N'};
reg.nominal_thrust         = {'Nominal thrust',                'N'};
reg.c_e                    = {'Effective exhaust velocity',    'm/s'};
reg.isp                    = {'Specific impulse',              's'};
reg.massflow               = {'Mass flow rate',                'kg/s'};
reg.delta_v                = {'Delta-v',                       'm/s'};
reg.impulse_tot            = {'Total impulse',                 'N s'};
reg.total_impulse          = {'Total impulse',                 'N s'};
reg.minimum_impulse_bit    = {'Minimum impulse bit',           'N s'};
reg.efficiency             = {'Efficiency',                    '-'};

% Geometry
reg.volume                 = {'Volume',                        'm3'};
reg.volume_box             = {'Bounding box volume',           'm3'};
reg.area                   = {'Area',                          'm2'};
reg.height                 = {'Height',                        'm'};
reg.width                  = {'Width',                         'm'};
reg.length                 = {'Length',                        'm'};
reg.size_x                 = {'Size (x)',                      'm'};
reg.size_y                 = {'Size (y)',                      'm'};
reg.size_h                 = {'Height',                        'm'};

% Electrical
reg.voltage                = {'Voltage',                       'V'};
reg.voltage_nominal        = {'Nominal voltage',               'V'};
reg.resistance             = {'Resistance',                    'Ohm'};
reg.el_resistance          = {'Electrical resistance',         'Ohm'};
reg.internal_resistance    = {'Internal resistance',           'Ohm'};
reg.pressure               = {'Pressure',                      'Pa'};

% Energy storage
reg.energy                 = {'Energy',                        'J'};
reg.energy_density         = {'Energy density',                'Wh/kg'};
reg.specific_energy        = {'Specific energy',               'Wh/kg'};
reg.capacity               = {'Capacity',                      'Ah'};
reg.cell_nominal_capacity  = {'Cell nominal capacity',         'Ah'};
reg.cells_total            = {'Total cell count',              '-'};
reg.charge_current_max     = {'Max. charge current',           'A'};
reg.discharge_current_cont = {'Continuous discharge current',  'A'};
reg.discharge_current_pulse= {'Pulse discharge current',       'A'};
reg.cycle_life             = {'Cycle life',                    '-'};

% Mission timeline
reg.mission_life           = {'Mission life',                  'years'};

% AOCS
reg.momentum_storage       = {'Momentum storage',             'N m s'};
reg.nom_mag_moment         = {'Nominal magnetic moment',       'A m2'};
reg.sat_mag_moment         = {'Saturation magnetic moment',    'A m2'};
reg.torque_max             = {'Maximum torque',                'N m'};
reg.max_slew               = {'Maximum slew rate',             'deg/s'};
reg.pointing_deg           = {'Pointing accuracy',             'deg'};
reg.pointing_knowledge_error = {'Pointing knowledge error',    'deg'};
reg.accuracy               = {'Accuracy',                      'deg'};
reg.axis                   = {'Controlled axes',               '-'};

% Payload / instruments
reg.FOV                    = {'Field of view',                 'deg'};

% Communications
reg.storage                = {'Data storage',                  'Gb'};
reg.downlink               = {'Downlink rate',                 'kbps'};
reg.uplink                 = {'Uplink rate',                   'kbps'};
reg.sampling_rate          = {'Sampling rate',                 'Hz'};

% Power electronics (MPPT)
reg.mppt_channels          = {'MPPT channels',                 '-'};
reg.mppt_input_current_max = {'Max. MPPT input current',       'A'};
reg.mppt_input_voltage_max = {'Max. MPPT input voltage',       'V'};

% Miscellaneous
reg.TRL                    = {'Technology readiness level',    '-'};

% Mass fractions (spacecraft-level SMAD correlations)
reg.fraction_mass_payload    = {'Mass fraction, payload',      '-'};
reg.fraction_mass_propulsion = {'Mass fraction, propulsion',   '-'};
reg.fraction_mass_power      = {'Mass fraction, power',        '-'};
reg.fraction_mass_ADC        = {'Mass fraction, AOCS',         '-'};
reg.fraction_mass_OBC        = {'Mass fraction, OBC',          '-'};
reg.fraction_mass_TTC        = {'Mass fraction, TTC',          '-'};
reg.fraction_mass_thermal    = {'Mass fraction, thermal',      '-'};
reg.fraction_mass_structmech = {'Mass fraction, structure',    '-'};
reg.fraction_mass_other      = {'Mass fraction, other',        '-'};

% Power fractions (spacecraft-level)
reg.fraction_power_payload   = {'Power fraction, payload',     '-'};
reg.fraction_power_power     = {'Power fraction, power subs.', '-'};
reg.fraction_power_ADC       = {'Power fraction, AOCS',        '-'};
reg.fraction_power_OBC       = {'Power fraction, OBC',         '-'};
reg.fraction_power_TTC       = {'Power fraction, TTC',         '-'};
reg.fraction_power_thermal   = {'Power fraction, thermal',     '-'};
reg.fraction_power_structmech= {'Power fraction, structure',   '-'};
reg.fraction_propulsion_power= {'Propulsion power fraction',   '-'};

% ---- Lookup ------------------------------------------------------------
safe_id = fieldname_safe(quantity_id);

if isfield(reg, safe_id)
  entry      = reg.(safe_id);
  disp_label = entry{1};
  disp_unit  = entry{2};
  return;
end

% Unknown identifier: safe fallback with diagnostic
if ~isempty(unit_hint) && ~any(strcmp(unit_hint, {'unknown', ''}))
  disp_unit = unit_hint;
else
  disp_unit = '?';
end
disp_label = strrep(quantity_id, '_', ' ');

warning('plot_quantity_label:unknown', ...
  ['No registry entry for quantity ''%s''. Add it to plot_quantity_label.m. ' ...
   'Using label ''%s'' and unit ''%s''.'], ...
  quantity_id, disp_label, disp_unit);
end

% -------------------------------------------------------------------------
function s = fieldname_safe(id)
% Make an identifier safe to use as a struct fieldname.
s = regexprep(id, '[^a-zA-Z0-9_]', '_');
if ~isempty(s) && s(1) >= '0' && s(1) <= '9'
  s = ['q_' s];
end
end
