% SMAD_scalings — Estimate spacecraft subsystem masses and powers via statistical fractions
%
% Three derivation modes are selected by data.system_scaling_mode (set from
% Simulation_parameters.scaling.system_scaling_mode):
%
%   1 = SMAD_flat     : fixed fractions from SMAD Table 14-18 (Wertz 2011, pp. 422, 424).
%                       30 % margin (paper value; overridden by data.mass_margin_fraction).
%   2 = Ehresmann2021 : database polynomial fit (Ehresmann 2021, Sec. 2.2.2).
%                       x-axis for mass fraction lookup = total wet mass.
%                       30 % margin (paper value; overridden by data.mass_margin_fraction).
%   3 = refined       : database polynomial fit, x-axis = post-margin dry mass (default).
%                       Margin from data.mass_margin_fraction (default 0.25, NASA GSFC-STD-1000).
%
% Parameters:
%   data (struct): Population member with at least:
%     .mass                   (float): Total wet mass [kg]
%     .sc_type                (int):   Spacecraft class 1–4
%     .system_scaling_mode    (int):   1, 2, or 3 (default 3 if absent)
%     .mass_margin_fraction   (float): Design margin fraction (optional override)
%
% Returns:
%   systemmasses  (struct): Subsystem mass breakdown [kg]:
%     .m_dry_nomargin, .m_margin, .m_dry_margin, .mass_propellant,
%     .mass_payload, .mass_structmech, .mass_thermal, .mass_power,
%     .mass_ttc, .mass_adc, .mass_propulsion, .mass_other
%   systempowers  (struct): Subsystem power breakdown [W]:
%     .power_total, .power_payload, .power_structmech, .power_thermal,
%     .power_power, .power_ttc, .power_adc, .propulsion_power
%   scaling_quality (struct, optional): Interpolation confidence for mode 2/3;
%     also populated for mode 1 (informational). Includes .mode field.
%
% HOW TO TEST:
%   1. Fractions sum test: systemmasses.m_dry_margin ≈ sum of subsystem masses.
%   2. Mass conservation: m_dry_nomargin + mass_propellant == data.mass.
%   3. Mode comparison: run sc_type 2, mass 1000 kg for modes 1, 2, 3; verify
%      fractions differ between modes and match their respective references.
%   4. Margin override: set data.mass_margin_fraction=0.20; verify m_margin=0.20*m_dry.
%   5. scaling_quality.mode matches the mode used.
function [systemmasses systempowers scaling_quality] = SMAD_scalings(data)

  systemmasses = struct;
  systempowers = struct;

  % ---- Scaling mode and margin (set by make_population from sim params) ------
  % Mode: 1=SMAD_flat, 2=Ehresmann2021, 3=refined (default)
  mode = 3;
  if isfield(data, 'system_scaling_mode') && ~isempty(data.system_scaling_mode)
    mode = data.system_scaling_mode;
  end

  % Margin: use configured value; fall back to mode-appropriate paper default.
  if isfield(data, 'mass_margin_fraction') && ~isempty(data.mass_margin_fraction) ...
      && ~isnan(data.mass_margin_fraction)
    margin_frac = data.mass_margin_fraction;
  elseif mode <= 2
    margin_frac = 0.30;  % Ehresmann 2021, Sec. 2.2
  else
    margin_frac = 0.25;  % NASA GSFC-STD-1000
  end

  % ---- Common: spacecraft type, dry mass, propellant -----------------------
  sc_type = determine_sc_type(data);
  systemmasses.m_dry_nomargin  = determine_m_dry(data);
  systemmasses.mass_propellant = data.mass - systemmasses.m_dry_nomargin;

  systemmasses.m_margin     = margin_frac * systemmasses.m_dry_nomargin;
  systemmasses.m_dry_margin = systemmasses.m_dry_nomargin - systemmasses.m_margin;

  if isfield(data, 'power_total')
    systempowers.power_total = data.power_total;
  else
    systempowers.power_total = p_tot_average(systemmasses.m_dry_nomargin, sc_type);
  end

  % ---- Derive subsystem fractions by mode ----------------------------------
  if mode == 1
    % SMAD flat: fixed fractions from Wertz 2011 Table 14-18, pp. 422, 424
    [systemmasses, systempowers] = apply_smad_flat(systemmasses, systempowers, sc_type);

  elseif mode == 2
    % Ehresmann 2021 (Sec. 2.2.2): DB polynomial fit, x = total wet mass
    [systemmasses, systempowers] = apply_db_polynomial(systemmasses, systempowers, sc_type, data.mass);

  else
    % mode 3 refined (current): DB polynomial fit, x = post-margin dry mass
    [systemmasses, systempowers] = apply_db_polynomial(systemmasses, systempowers, sc_type, systemmasses.m_dry_margin);
  end

  % ---- Reconcile: re-derive m_dry_margin as subsystem sum ------------------
  systemmasses.m_dry_margin = systemmasses.mass_payload + systemmasses.mass_structmech + ...
    systemmasses.mass_thermal + systemmasses.mass_power + systemmasses.mass_ttc + ...
    systemmasses.mass_adc + systemmasses.mass_propulsion + systemmasses.mass_other;
  systemmasses.m_margin = systemmasses.m_dry_nomargin - systemmasses.m_dry_margin;

  if systemmasses.m_margin < 0
    disp('No system margin left');
  end

  if nargout > 2
    scaling_quality = compute_scaling_quality(systemmasses.m_dry_margin, systempowers.power_total, sc_type);
    scaling_quality.mode = mode;
  end

endfunction


% =========================================================================
% MODE 1: SMAD flat fractions (Wertz 2011, Table 14-18, pp. 422, 424)
% =========================================================================
% Columns correspond to sc_type: 1=NoProp, 2=LEO, 3=HEO, 4=Probe.
% OBC and Misc from Table 2 are merged into mass_other (no separate OBC field).
% Structural power fraction for NoProp corrected 0.20→0.02 (OCR artefact in paper).
function [sm, sp] = apply_smad_flat(sm, sp, sc_type)
  % rows: payload, structmech, thermal, power, ttc, adc, propulsion, other(OBC+misc)
  mf = [0.41 0.31 0.32 0.15;
        0.20 0.27 0.24 0.25;
        0.02 0.02 0.04 0.06;
        0.19 0.21 0.17 0.21;
        0.02 0.02 0.04 0.07;
        0.08 0.06 0.06 0.06;
        0.00 0.03 0.07 0.13;
        0.08 0.08 0.06 0.07];  % OBC(0.05/0.05/0.03/0.04) + misc(0.03)

  sm.mass_payload    = mf(1, sc_type) * sm.m_dry_margin;
  sm.mass_structmech = mf(2, sc_type) * sm.m_dry_margin;
  sm.mass_thermal    = mf(3, sc_type) * sm.m_dry_margin;
  sm.mass_power      = mf(4, sc_type) * sm.m_dry_margin;
  sm.mass_ttc        = mf(5, sc_type) * sm.m_dry_margin;
  sm.mass_adc        = mf(6, sc_type) * sm.m_dry_margin;
  sm.mass_propulsion = mf(7, sc_type) * sm.m_dry_margin;
  sm.mass_other      = mf(8, sc_type) * sm.m_dry_margin;

  % rows: payload, structmech, thermal, power, ttc, adc, propulsion
  % OBC power is not separately tracked; consistent with modes 2 & 3.
  pf = [0.43 0.46 0.35 0.22;
        0.02 0.01 0.00 0.01;
        0.05 0.10 0.14 0.15;
        0.10 0.09 0.07 0.10;
        0.11 0.12 0.16 0.18;
        0.18 0.10 0.16 0.12;
        0.00 0.00 0.02 0.11];

  sp.power_payload    = pf(1, sc_type) * sp.power_total;
  sp.power_structmech = pf(2, sc_type) * sp.power_total;
  sp.power_thermal    = pf(3, sc_type) * sp.power_total;
  sp.power_power      = pf(4, sc_type) * sp.power_total;
  sp.power_ttc        = pf(5, sc_type) * sp.power_total;
  sp.power_adc        = pf(6, sc_type) * sp.power_total;
  sp.propulsion_power = pf(7, sc_type) * sp.power_total;
endfunction


% =========================================================================
% MODES 2 & 3: polynomial interpolation from spacecraft reference database
% =========================================================================
% x_mass: lookup reference (mode 2 = total wet mass; mode 3 = post-margin dry mass)
function [sm, sp] = apply_db_polynomial(sm, sp, sc_type, x_mass)
  sm.mass_payload    = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_payload')    * sm.m_dry_margin;
  sm.mass_structmech = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_structmech') * sm.m_dry_margin;
  sm.mass_thermal    = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_thermal')    * sm.m_dry_margin;
  sm.mass_power      = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_power')      * sm.m_dry_margin;
  sm.mass_ttc        = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_TTC')        * sm.m_dry_margin;
  sm.mass_adc        = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_ADC')        * sm.m_dry_margin;
  sm.mass_propulsion = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_propulsion') * sm.m_dry_margin;
  sm.mass_other      = interp_spacecraft_param(x_mass, sc_type, 'mass_total', 'fraction_mass_other')      * sm.m_dry_margin;

  sp.power_payload    = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_power_payload')    * sp.power_total;
  sp.power_structmech = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_power_structmech') * sp.power_total;
  sp.power_thermal    = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_power_thermal')    * sp.power_total;
  sp.power_power      = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_power_power')      * sp.power_total;
  sp.power_ttc        = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_power_TTC')        * sp.power_total;
  sp.power_adc        = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_power_ADC')        * sp.power_total;
  sp.propulsion_power = interp_spacecraft_param(sp.power_total, sc_type, 'power_total', 'fraction_propulsion_power') * sp.power_total;
endfunction


% =========================================================================
% SCALING CONFIDENCE COLLECTOR
% =========================================================================
% Evaluates the statistical confidence of the DB polynomial interpolations.
% Always uses m_dry_margin as the mass reference (informational for mode 1).
%
% Returns scaling_quality struct with per-parameter confidence scores and an
% aggregate worst-case total_score / total_regime / total_label.

function sq = compute_scaling_quality(x_mass, x_power, sc_type)
  mass_csv_params = {'fraction_mass_payload',    'fraction_mass_structmech', ...
                     'fraction_mass_thermal',     'fraction_mass_power', ...
                     'fraction_mass_TTC',         'fraction_mass_ADC', ...
                     'fraction_mass_propulsion',  'fraction_mass_other'};
  mass_keys       = {'mass_payload',    'mass_structmech', ...
                     'mass_thermal',    'mass_power', ...
                     'mass_ttc',        'mass_adc', ...
                     'mass_propulsion', 'mass_other'};

  power_csv_params = {'fraction_power_payload',    'fraction_power_structmech', ...
                      'fraction_power_thermal',     'fraction_power_power', ...
                      'fraction_power_TTC',          'fraction_power_ADC', ...
                      'fraction_propulsion_power'};
  power_keys       = {'power_payload',    'power_structmech', ...
                      'power_thermal',    'power_power', ...
                      'power_ttc',        'power_adc', ...
                      'propulsion_power'};

  sq.mass  = struct();
  sq.power = struct();

  mass_scores  = zeros(1, numel(mass_keys));
  power_scores = zeros(1, numel(power_keys));
  any_extrap   = false;

  for k = 1:numel(mass_keys)
    [~, conf] = interp_spacecraft_param(x_mass, sc_type, 'mass_total', mass_csv_params{k});
    sq.mass.(mass_keys{k}) = conf;
    mass_scores(k) = conf.score;
    if strcmp(conf.regime, 'extrapolation'); any_extrap = true; end
  end

  for k = 1:numel(power_keys)
    [~, conf] = interp_spacecraft_param(x_power, sc_type, 'power_total', power_csv_params{k});
    sq.power.(power_keys{k}) = conf;
    power_scores(k) = conf.score;
    if strcmp(conf.regime, 'extrapolation'); any_extrap = true; end
  end

  sq.mass_score   = min(mass_scores);
  sq.power_score  = min(power_scores);
  sq.total_score  = min(sq.mass_score, sq.power_score);
  sq.total_regime = 'interpolation';
  if any_extrap; sq.total_regime = 'extrapolation'; end

  if sq.total_score >= 0.70
    sq.total_label = 'high';
  elseif sq.total_score >= 0.40
    sq.total_label = 'medium';
  else
    sq.total_label = 'low';
  end
end

function [m_dry] = determine_m_dry(data)
  if isfield(data, 'dv')
    dv = data.dv;
  elseif isfield(data, 'deltav')
    dv = data.deltav;
  else
    dv = NaN;
  end
  if ~isnan(dv) && isfield(data, 'c_e') && dv > 0 && data.c_e > 0
    m_dry = exp(-dv / data.c_e) * data.mass;
  elseif isfield(data, 'mass_propellant')
    m_dry = data.mass - data.mass_propellant;
  else
    m_dry = data.mass;
  endif
endfunction

function P = p_tot_average(mass_dry, sc_type)
  % Reference: Wertz 2011 Table 14-20 average power vs dry mass per sc_type.
  power_factor = [299 794 691 749];
  mass_factor  = mass_dry ./ [1497 2344 1258 888];
  P = mass_factor(sc_type)^(2/3) * power_factor(sc_type);
end
