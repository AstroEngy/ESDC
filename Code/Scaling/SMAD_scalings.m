%Space Mission Engineering - The New SMAD
% Author(s): James Wertz, David Everett, Jeffery Puschell
% Series: Space Technology Library, Vol. 28
% Publisher: Microcosm Press, Year: 2011
% ISBN: 978-1881883159

%Page 422 Tab 14-18 Average Mass by System as a Percentage of Dry Mass for 4 Types of Spacecraft

%Factor - 1 no propulsion , 2  LEO up to 1000 km, 3 - above 1000, 4 - planetary probe

function [systemmasses systempowers scaling_quality] = SMAD_scalings(data)
  
  %disp(data)

   systemmasses                 = struct;
   systempowers                 = struct;
   
   sc_type                      = determine_sc_type(data);
   systemmasses.m_dry_nomargin  = determine_m_dry(data);                                 % total mass of system without considering any margin
   
   systemmasses.m_margin        = m_margin(systemmasses.m_dry_nomargin, sc_type);       % obtain typical margin mass to be applied to such a system
   systemmasses.m_dry_margin    = systemmasses.m_dry_nomargin - systemmasses.m_margin;  % calculate new maximum mass available when subtracting the margin mass
   
   systemmasses.mass_propellant    = data.mass - systemmasses.m_dry_nomargin;              % calculate the propellant mass by difference of total mass to dry mass
  
  
   %Scale subsystem masses accordingly
   systemmasses.mass_payload       = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_payload")*systemmasses.m_dry_margin;;
   systemmasses.mass_structmech    = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_structmech")*systemmasses.m_dry_margin;
   systemmasses.mass_thermal       = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_thermal")*systemmasses.m_dry_margin;
   systemmasses.mass_power         = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_power")*systemmasses.m_dry_margin;  
   systemmasses.mass_ttc           = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_TTC")*systemmasses.m_dry_margin;
   systemmasses.mass_adc           = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_ADC")*systemmasses.m_dry_margin;
   systemmasses.mass_propulsion    = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_propulsion")*systemmasses.m_dry_margin;
   systemmasses.mass_other         = scale_SMAD_parameter(systemmasses.m_dry_margin, sc_type, "mass_total", "fraction_mass_other")*systemmasses.m_dry_margin;

%   
   %Check for remaining mass difference
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
