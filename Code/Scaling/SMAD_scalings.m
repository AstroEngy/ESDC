% SMAD_scalings — Estimate spacecraft subsystem masses and powers via statistical fractions
%
% Reference:
%   Space Mission Engineering: The New SMAD, Wertz, Everett & Puschell, 2011
%   Microcosm Press, ISBN 978-1881883159.
%   Table 14-18 (page 422): Average mass by subsystem as % of dry mass for 4 spacecraft types.
%
% PURPOSE:
%   Given a spacecraft's total wet mass and sc_type, applies SMAD statistical
%   mass and power fractions to estimate the mass of each subsystem
%   (payload, structure, thermal, power, TTC, ADC, propulsion) and the power
%   of each consumer.  These estimates drive the evolutionary fitness function.
%
% INTENT:
%   Provides a fast, physics-grounded baseline that does not require a
%   detailed subsystem model.  Every population member is re-sized here after
%   each mutation so that mass budget consistency is maintained throughout
%   evolution.  The third output (scaling_quality) is computed on demand
%   (when called with 3 outputs) to avoid overhead in the inner evolution loop.
%
% Spacecraft type codes (factor):
%   1 — No propulsion (e.g. small LEO with no delta-v)
%   2 — LEO up to 1000 km
%   3 — High Earth (>1000 km, GEO)
%   4 — Planetary probe
%
% Parameters:
%   data (struct): Population member with at least:
%     .mass       (float): Total wet mass [kg]
%     .sc_type    (int):   Spacecraft class 1–4 (or fields for determine_sc_type)
%
% Returns:
%   systemmasses  (struct): Subsystem mass breakdown [kg]:
%     .m_dry_nomargin, .m_margin, .m_dry_margin, .mass_propellant,
%     .mass_payload, .mass_structmech, .mass_thermal, .mass_power,
%     .mass_ttc, .mass_adc, .mass_propulsion, .mass_other
%   systempowers  (struct): Subsystem power breakdown [W]:
%     .power_total, .power_payload, .power_structmech, .power_thermal,
%     .power_power, .power_ttc, .power_adc, .propulsion_power
%   scaling_quality (struct, optional): Statistical confidence of all
%     applied SMAD fractions (interpolation vs extrapolation, data density).
%
% HOW TO TEST:
%   1. Fractions sum test: verify that
%      systemmasses.m_dry_margin ≈ sum of all subsystem masses (after reassignment).
%   2. Mass conservation: systemmasses.m_dry_nomargin + systemmasses.mass_propellant
%      should equal data.mass.
%   3. Power consistency: sum of all non-total power fields should ≈ power_total.
%   4. sc_type sensitivity: run for sc_type 1–4 with same mass and confirm
%      fractions differ (payload fraction highest for sc_type 2, lowest for 4).
%   5. scaling_quality test: call with 3 outputs and verify .min_score is
%      between 0 and 1 and .weakest_parameter is a non-empty string.
%
% SAFEGUARDS ALREADY IN PLACE:
%   - Warning printed when m_margin < 0 (subsystems over-budget).
%   - systempowers.power_total falls back to SMAD estimate when not provided.
%
% SAFEGUARDS TO ADD (future work):
%   - Return an error or set a flag when mass_propellant < 0
%     (indicates the dry mass SMAD estimate exceeds the total wet mass, which
%     would mean m_dry_nomargin > data.mass — physically impossible).
%   - Assert that all fraction values loaded from CSV are in [0, 1].
function [systemmasses systempowers scaling_quality] = SMAD_scalings(data)
  
  %disp(data)

   systemmasses                 = struct;
   systempowers                 = struct;
   
   % ---- Classify spacecraft type and determine dry mass --------------------
   sc_type                      = determine_sc_type(data);
   systemmasses.m_dry_nomargin  = determine_m_dry(data);                                 % total mass of system without considering any margin
   
   % m_margin: statistical design margin fraction of dry mass (from SMAD Table 14-18)
   systemmasses.m_margin        = m_margin(systemmasses.m_dry_nomargin, sc_type);       % obtain typical margin mass to be applied to such a system
   % m_dry_margin: mass actually available for subsystems after the margin reserve
   systemmasses.m_dry_margin    = systemmasses.m_dry_nomargin - systemmasses.m_margin;  % calculate new maximum mass available when subtracting the margin mass
   
   % Propellant mass = wet mass − dry mass.  May be negative if SMAD dry fraction
   % exceeds 1.0 for the given mass — this indicates the input is out of range.
   systemmasses.mass_propellant    = data.mass - systemmasses.m_dry_nomargin;              % calculate the propellant mass by difference of total mass to dry mass
  
  
   % ---- Apply SMAD mass fractions to each subsystem ----------------------
   % scale_SMAD_parameter reads a CSV file and interpolates the fraction at the
   % given reference value; the fraction is then multiplied by the reference mass.
   systemmasses.mass_payload       = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_payload")*systemmasses.m_dry_margin;;
   systemmasses.mass_structmech    = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_structmech")*systemmasses.m_dry_margin;
   systemmasses.mass_thermal       = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_thermal")*systemmasses.m_dry_margin;
   systemmasses.mass_power         = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_power")*systemmasses.m_dry_margin;  
   systemmasses.mass_ttc           = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_TTC")*systemmasses.m_dry_margin;
   systemmasses.mass_adc           = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_ADC")*systemmasses.m_dry_margin;
   systemmasses.mass_propulsion    = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_propulsion")*systemmasses.m_dry_margin;
   systemmasses.mass_other         = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_other")*systemmasses.m_dry_margin;

   % ---- Reconcile subsystem sum against m_dry_margin ----------------------
   % After scaling, re-derive m_dry_margin as the actual sum (fractions may not sum
   % exactly to 1.0); the residual goes into m_margin.
   % Check for remaining mass difference
   %checksum = systemmasses.mass_propellant+systemmasses.mass_payload+systemmasses.mass_structmech +systemmasses.mass_thermal+ systemmasses.mass_power+ systemmasses.m_ttc+ systemmasses.m_adc+systemmasses.mass_propulsion+ systemmasses.mass_other;
   systemmasses.m_dry_margin = systemmasses.mass_payload+systemmasses.mass_structmech +systemmasses.mass_thermal+ systemmasses.mass_power+ systemmasses.mass_ttc+ systemmasses.mass_adc+systemmasses.mass_propulsion+ systemmasses.mass_other;

   %Add discrepancy to margin

   systemmasses.m_margin= systemmasses.m_dry_nomargin -systemmasses.m_dry_margin;

   
   if systemmasses.m_margin<0
      disp('No system margin left');
   end
   if isfield(data,'power_total')
    systempowers.power_total = data.power_total;
   else
    systempowers.power_total = p_tot_average(systemmasses.m_dry_nomargin, sc_type);
   end
   
   systempowers.power_payload       = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_power_payload")*systempowers.power_total;
   systempowers.power_structmech    = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_power_structmech")*systempowers.power_total;
   systempowers.power_thermal       = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_power_thermal")*systempowers.power_total;
   systempowers.power_power         = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_power_power")*systempowers.power_total;  
   systempowers.power_ttc           = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_power_TTC")*systempowers.power_total;
   systempowers.power_adc           = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_power_ADC")*systempowers.power_total;
   systempowers.propulsion_power    = scale_SMAD_parameter(systempowers.power_total, sc_type, "power_total", "fraction_propulsion_power")*systempowers.power_total;
   
   if nargout > 2
     scaling_quality = compute_scaling_quality(systemmasses.m_dry_margin, systempowers.power_total, sc_type);
   end
   
endfunction



% =========================================================================
% SCALING CONFIDENCE COLLECTOR
% =========================================================================
% Evaluates the statistical confidence of all SMAD mass- and power-fraction
% scalings by calling scaling_confidence for each parameter.
%
% The aggregate score uses the minimum (worst-case) convention: if even one
% parameter extrapolates or uses sparse data, the overall assessment
% reflects that weakest link.
%
% x_mass   [kg]  m_dry_margin — input for all 8 mass-fraction scalings
% x_power  [W]   power_total  — input for all 7 power-fraction scalings
% sc_type  int   spacecraft type 1–4 (selects the correct CSV database)
%
% Returns scaling_quality struct:
%   .mass.(param)  — per-parameter conf struct (score/regime/label/
%                    gap_fraction/n_source_points) for each mass parameter
%   .power.(param) — same, for each power parameter
%   .mass_score    — minimum score over all 8 mass parameters
%   .power_score   — minimum score over all 7 power parameters
%   .total_score   — minimum of mass_score and power_score (worst case)
%   .total_regime  — 'extrapolation' when any single parameter is outside
%                    the source data range; 'interpolation' otherwise
%   .total_label   — 'high' (0.70 and above), 'medium' (0.40 to 0.70),
%                    'low' (below 0.40)  [green / yellow / red]

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
    [~, conf] = scale_SMAD_parameter(x_mass, sc_type, 'mass_total', mass_csv_params{k});
    sq.mass.(mass_keys{k}) = conf;
    mass_scores(k) = conf.score;
    if strcmp(conf.regime, 'extrapolation'); any_extrap = true; end
  end

  for k = 1:numel(power_keys)
    [~, conf] = scale_SMAD_parameter(x_power, sc_type, 'power_total', power_csv_params{k});
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
    % Support both 'dv' and 'deltav' field names (make_population stores 'deltav')
    if isfield(data, 'dv')
      dv = data.dv;
    elseif isfield(data, 'deltav')
      dv = data.deltav;
    else
      dv = NaN;
    end
    if ~isnan(dv) && isfield(data,'c_e') && dv > 0 && data.c_e > 0
      m_dry = exp(-dv/data.c_e)*data.mass;
    elseif isfield(data,'mass_propellant')
      m_dry = data.mass - data.mass_propellant;
    else
      m_dry = data.mass;
    endif
endfunction



function m = m_margin(m_dry, sc_type)       %TODO: config parameter
  %Mass budget margin
  factor=[.25 .25 .25 .25];         % https://standards.nasa.gov/standard/gsfc/gsfc-std-1000 
  m = m_dry*(factor(sc_type));   
end

%Power Scaling
%Page 423 Tab 14-20 Average Mass by System as a Percentage of Dry Mass for 4 Types of Spacecraft

%Factor - 1 no propulsion , 2  LEO up to 1000 km, 3 - above 1000, 4 - planetary probe

function P = p_tot_average(mass_dry, sc_type)
  power_factor=[299 794 691 749];
  mass_factor = mass_dry./[1497 2344 1258 888];
  P= mass_factor(sc_type)^(2/3)*power_factor(sc_type); % continue here with better data from 966 new SMAD
end
