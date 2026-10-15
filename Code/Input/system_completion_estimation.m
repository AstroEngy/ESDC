% system_completion_estimation  Estimate unknown mass/power subsystem values from known inputs.
%
% Given a set of user-supplied mass and power fields (any subset of the
% recognised subsystem parameters), derives the remaining unknowns via SMAD
% statistical scaling relationships and returns a structured summary of
% known and estimated values.
%
% Parameters:
%   inputs - struct of user-supplied mission parameters for one input case
%   sim    - simulation parameters struct (used for sc_type threshold defaults)
%
% Returns:
%   derived_parameters - struct with fields:
%     .sc_type          - classified spacecraft type (1-4)
%     .known.mass.*     - user-supplied mass values
%     .known.power.*    - user-supplied power values
%     .unknown.mass.*   - estimated mass values (including mass_total)
%     .unknown.power.*  - estimated power values (including power_total)

function [derived_parameters] = system_completion_estimation(inputs, sim)
  derived_parameters = struct;

  % Available mass fields (may or may not be provided in external file)
  masses = {
  'mass_total'
  %'mass_propellant'
  'mass_payload'
  'mass_structmech'
  'mass_thermal'
  'mass_power'
  'mass_TTC'
  'mass_ADC'
  'mass_propulsion'
  'mass_other'
  };

  % Available power fields
  powers = {
  'power_total'
  'power_payload'
  'power_structmech'
  'power_thermal'
  'power_power'
  'power_TTC'
  'power_ADC'
  'propulsion_power'
  };

  % Create structures for known and unknown data
  known = struct();
  unknown = struct();

  % Partition mass fields into known (user-supplied) and unknown (to be estimated)
  for i=1:numel(masses)
    if isfield(inputs, cellstr(masses{i}))
      known.mass.(masses{i}) = inputs.(masses{i});
    else
      unknown.mass.(masses{i}) = 0;
    end
  endfor

  % Partition power fields into known and unknown
  for i=1:numel(powers)
    if isfield(inputs, cellstr(powers{i}))
      known.power.(powers{i}) = inputs.(powers{i});
    else
      unknown.power.(powers{i}) = 0;
    end
  endfor

  % Spacecraft type derivation — priority: explicit sc_type > orbit_height > delta_v
  sc_data = struct();
  if isfield(inputs, 'sc_type')
    sc_data.sc_type = inputs.sc_type;
  end
  if isfield(inputs, 'orbit_height') && inputs.orbit_height > 0
    sc_data.orbit_height = inputs.orbit_height;
  end
  if isfield(inputs, 'deltav')
    sc_data.dv = inputs.deltav;
  end
  sc_thresholds = struct();
  if isstruct(sim) && isfield(sim, 'Simulation_parameters') ...
      && isfield(sim.Simulation_parameters, 'defaults') ...
      && isfield(sim.Simulation_parameters.defaults, 'sc_type_thresholds')
    sc_thresholds = sim.Simulation_parameters.defaults.sc_type_thresholds;
  end
  sc_type = determine_sc_type(sc_data, sc_thresholds);
  derived_parameters.sc_type = sc_type;

  % Require at least one known mass or power field
  if not(isfield(known,'power')) && not(isfield(known,'mass'))
    disp(' ')
    disp('If anything would be known - yeah - that d great');
    disp('Define at least one system or mass - quitting ESDC');
    error('Insufficient knowns');
  endif

  margin = 0.3; %TODO config parameter

  if isfield(known,'mass') && isfield(known.mass,'mass_total')
    [known unknown] = system_with_known_mass_total(known, unknown, margin, sc_type);
  elseif isfield(known,'power') && isfield(known.power,'power_total')
    [known unknown] = system_with_known_totalpower(known, unknown, margin, sc_type);
  elseif isfield(unknown.mass,'mass_total') && isfield(unknown.power,'power_total')
    [known unknown] = system_with_unknown_totals(known, unknown, margin, sc_type);
  endif

  derived_parameters.known = known;
  derived_parameters.unknown = unknown;
endfunction


% =========================================================================
% CASE: both totals unknown — at least one subsystem mass or power known
% =========================================================================
function [known unknown] = system_with_unknown_totals(known, unknown, margin, sc_type)

  if isfield(known,'mass')
    % --- Mass-based estimation path ---
    unknown_parameters = fieldnames(unknown.mass);
    known_parameters   = fieldnames(known.mass);

    % Inverse-scaling: derive the implied mass_total from each known subsystem mass
    all_known_masses = 0;
    fracs = [];
    for i = 1:numel(known_parameters)
      fracs = [fracs scale_SMAD_parameter_inverse_fraction( ...
                 known.mass.(known_parameters{i}), sc_type, 'mass_total', ...
                 strcat('fraction_', known_parameters{i}))];
      all_known_masses = all_known_masses + known.mass.(known_parameters{i});
    end

    all_known_fractions = sum(fracs);

    % Derive initial mass_total estimate
    unknown.mass.mass_total_margin = all_known_masses / all_known_fractions;
    unknown.mass.mass_total        = unknown.mass.mass_total_margin / (1 - margin);
    unknown.mass.m_margin          = unknown.mass.mass_total - unknown.mass.mass_total_margin;

    % Estimate all remaining subsystem masses from mass_total_margin
    for i = 1:numel(unknown_parameters)
      if not(strcmp(unknown_parameters{i}, 'mass_total'))
        unknown.mass.(unknown_parameters{i}) = ...
          scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total', ...
                               strcat('fraction_', unknown_parameters{i})) ...
          * unknown.mass.mass_total_margin;
      endif
    endfor

    % Estimate unknown power subsystems from mass_total_margin
    unknown_parameters = fieldnames(unknown.power);
    power_tot_relevant = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, ...
                                              'mass_total', 'power_total');
    for i = 1:numel(fieldnames(unknown.power))
      if not(strcmp(unknown_parameters{i}, 'power_total'))
        unknown.power.(unknown_parameters{i}) = ...
          scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total', ...
                               strcat('fraction_', unknown_parameters{i})) ...
          * power_tot_relevant;
      end
    endfor

    % Sum all system powers; guard against absent known.power (payload-mass-only input)
    if isfield(known, 'power')
      new_power_tot = sum_powers(known.power, unknown.power);
    else
      new_power_tot = sum_powers(struct(), unknown.power);
    end

    % Update total power field
    if isfield(unknown.power, 'power_total')
      unknown.power.power_total = new_power_tot;
    elseif isfield(known, 'power') && isfield(known.power, 'power_total')
      if new_power_tot > known.power.power_total
        disp('')
        disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
        disp('')
        known.power.power_total = new_power_tot;
      else
        known.power.p_margin = known.power.power_total - new_power_tot;
        known.power.power_total_margin = new_power_tot;
      end
    end

    % Refine power-system mass from the derived total power
    unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, ...
                                                   'power_total', 'fraction_mass_power') ...
                              * unknown.mass.mass_total_margin;

    % Validate mass budget (no user warning — total was derived, not user-given)
    [unknown.mass.mass_total, unknown.mass.m_margin, unknown.mass.mass_total_margin] = ...
      mass_validate(known.mass, unknown.mass, false);

  else
    % --- Power-based estimation path (no known mass fields) ---
    unknown_parameters = fieldnames(unknown.power);
    known_parameters   = fieldnames(known.power);

    % Inverse-scaling: derive the implied power_total from each known subsystem power
    all_known_powers = 0;
    fracs = [];
    for i = 1:numel(known_parameters)
      fracs = [fracs scale_SMAD_parameter_inverse_fraction( ...
                 known.power.(known_parameters{i}), sc_type, 'power_total', ...
                 strcat('fraction_', known_parameters{i}))];
      all_known_powers = all_known_powers + known.power.(known_parameters{i});
    end

    all_known_fractions = sum(fracs);
    unknown.power.power_total = all_known_powers / all_known_fractions;

    unknown_parameters = fieldnames(unknown.power);
    for i = 1:numel(fieldnames(unknown.power))
      if not(strcmp(unknown_parameters{i}, 'power_total'))
        unknown.power.(unknown_parameters{i}) = ...
          scale_SMAD_parameter(unknown.power.power_total, sc_type, 'power_total', ...
                               strcat('fraction_', unknown_parameters{i})) ...
          * unknown.power.power_total;
      end
    endfor

    new_power_tot = sum_powers(known.power, unknown.power);

    if new_power_tot > unknown.power.power_total
      disp('')
      disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
      disp('')
      unknown.power.power_total        = new_power_tot;
      unknown.power.p_margin           = 0;
      unknown.power.power_total_margin = unknown.power.power_total;
    else
      unknown.power.p_margin           = unknown.power.power_total - new_power_tot;
      unknown.power.power_total_margin = new_power_tot;
    end

    % Derive mass_total from power_total
    unknown.mass.mass_total = scale_SMAD_parameter(unknown.power.power_total, sc_type, ...
                                                   'power_total', 'mass_total');
    unknown_parameters = fieldnames(unknown.mass);
    unknown.mass.m_margin          = unknown.mass.mass_total * margin;
    unknown.mass.mass_total_margin = unknown.mass.mass_total - unknown.mass.m_margin;

    for i = 1:numel(unknown_parameters)
      if not(strcmp(unknown_parameters{i}, 'mass_total'))
        unknown.mass.(unknown_parameters{i}) = ...
          scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total', ...
                               strcat('fraction_', unknown_parameters{i})) ...
          * unknown.mass.mass_total_margin;
      endif
    endfor

    mass_new = 0;
    for i = 1:numel(unknown_parameters)
      if not(strcmp(unknown_parameters{i}, 'mass_total'))
        mass_new = mass_new + unknown.mass.(unknown_parameters{i});
      endif
    endfor
    unknown.mass.mass_total_margin = mass_new;
    unknown.mass.mass_total        = unknown.mass.mass_total_margin * (1 + margin);
    unknown.mass.m_margin          = unknown.mass.mass_total - unknown.mass.mass_total_margin;

  end
endfunction


% =========================================================================
% CASE: total power known, total mass unknown
% =========================================================================
function [known unknown] = system_with_known_totalpower(known, unknown, margin, sc_type)
  unknown_parameters = fieldnames(unknown.mass);

  % Derive total mass from total power via inverse scaling
  unknown.mass.mass_total        = scale_SMAD_parameter(known.power.power_total, sc_type, ...
                                                        'power_total', 'mass_total');
  unknown.mass.m_margin          = unknown.mass.mass_total * margin;
  unknown.mass.mass_total_margin = unknown.mass.mass_total - unknown.mass.m_margin;

  for i = 1:numel(unknown_parameters)
    if not(strcmp(fieldnames(unknown.mass){i}, 'mass_total'))
      unknown.mass.(unknown_parameters{i}) = ...
        scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total', ...
                             strcat('fraction_', unknown_parameters{i})) ...
        * unknown.mass.mass_total_margin;
    end
  endfor

  % Estimate unknown power subsystems for consistency
  if isfield(unknown, 'power')
    unknown_parameters = fieldnames(unknown.power);
    power_tot_relevant = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, ...
                                              'mass_total', 'power_total');
    for i = 1:numel(fieldnames(unknown.power))
      if not(strcmp(unknown_parameters{i}, 'power_total'))
        unknown.power.(unknown_parameters{i}) = ...
          scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total', ...
                               strcat('fraction_', unknown_parameters{i})) ...
          * power_tot_relevant;
      end
    endfor

    new_power_tot = sum_powers(known.power, unknown.power);

    if isfield(unknown.power, 'power_total')
      unknown.power.power_total = new_power_tot;
    elseif isfield(known.power, 'power_total')
      if new_power_tot > known.power.power_total
        disp('')
        disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
        disp('')
        known.power.power_total = new_power_tot;
      else
        known.power.p_margin       = known.power.power_total - new_power_tot;
        known.power.power_total_margin = new_power_tot;
      end
    end

    unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, ...
                                                   'power_total', 'fraction_mass_power') ...
                              * unknown.mass.mass_total_margin;
  end

  % Validate final mass budget
  [known.mass.mass_total, known.mass.m_margin, known.mass.mass_total_margin] = ...
    mass_validate(known.mass, unknown.mass);
endfunction


% =========================================================================
% CASE: total mass known
% =========================================================================
function [known unknown] = system_with_known_mass_total(known, unknown, margin, sc_type)

  if isfield(unknown, 'mass')
    unknown_parameters = fieldnames(unknown.mass);

    known.mass.m_margin          = known.mass.mass_total * margin;
    known.mass.mass_total_margin = known.mass.mass_total - known.mass.m_margin;

    for i = 1:numel(fieldnames(unknown.mass))
      unknown.mass.(unknown_parameters{i}) = ...
        scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total', ...
                             strcat('fraction_', unknown_parameters{i})) ...
        * known.mass.mass_total_margin;
    endfor
  end

  if isfield(unknown, 'power')
    unknown_parameters = fieldnames(unknown.power);
    power_tot_relevant = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, ...
                                              'mass_total', 'power_total');
    for i = 1:numel(fieldnames(unknown.power))
      if not(strcmp(unknown_parameters{i}, 'power_total'))
        unknown.power.(unknown_parameters{i}) = ...
          scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total', ...
                               strcat('fraction_', unknown_parameters{i})) ...
          * power_tot_relevant;
      end
    endfor

    % Guard against absent known.power (no power fields provided by user)
    if isfield(known, 'power')
      new_power_tot = sum_powers(known.power, unknown.power);
    else
      new_power_tot = sum_powers(struct(), unknown.power);
    endif

    if isfield(unknown.power, 'power_total')
      unknown.power.power_total = new_power_tot;
    elseif isfield(known, 'power') && isfield(known.power, 'power_total')
      if new_power_tot > known.power.power_total
        disp('')
        disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
        disp('')
        known.power.power_total = new_power_tot;
      else
        known.power.p_margin       = known.power.power_total - new_power_tot;
        known.power.power_total_margin = new_power_tot;
      end
    end

    unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, ...
                                                   'power_total', 'fraction_mass_power') ...
                              * known.mass.mass_total;
  end

  if isfield(unknown, 'mass')
    [known.mass.mass_total, known.mass.m_margin, known.mass.mass_total_margin] = ...
      mass_validate(known.mass, unknown.mass);
  end
endfunction


% =========================================================================
% HELPERS
% =========================================================================

% Inverse fraction look-up: given a known subsystem value y, return the
% fraction y/x where x is the total that would predict y via the CSV scaling.
function [fraction] = scale_SMAD_parameter_inverse_fraction(y, sc_type, x, file_parameter)
  orbits = {'No Propulsion', 'Low Earth', 'High Earth', 'Planetary'};
  filename = strcat('Database/Scaling/scaling_spacecraft_', orbits{sc_type}, ...
                    '_parameter_', x, '_to_', file_parameter, '.csv');
  if exist(filename)
    data = dlmread(filename, ',');
  else
    disp(filename);
    error(strcat('ERROR: File not found: ', filename));
  end

  frac_vals    = data(3,:);
  x_vals       = data(4,:);
  non_frac_vals = frac_vals .* x_vals;        % actual subsystem values at each data point

  x_derived = interp1(non_frac_vals, x_vals, y, 'linear', 'extrap');
  fraction  = y / x_derived;
endfunction


% Sum all system powers from known and unknown structs (excluding 'power_total').
% Accepts an empty struct for p_known when no power fields were provided.
function [p_new] = sum_powers(p_known, p_unknown)
  p_new = 0;
  parameters = fieldnames(p_known);
  for i = 1:numel(parameters)
    if not(strcmp(parameters{i}, 'power_total'))
      p_new = p_new + p_known.(parameters{i});
    end
  end
  parameters = fieldnames(p_unknown);
  for i = 1:numel(parameters)
    if not(strcmp(parameters{i}, 'power_total'))
      p_new = p_new + p_unknown.(parameters{i});
    end
  end
endfunction


% Validate mass budget and update mass_total / margin fields.
% warn_if_exceeded: when false, suppress the 'Total mass limit exceeded' warning
% (used when mass_total was derived rather than user-specified).
function [mass_total, m_margin, mass_total_margin] = mass_validate(m_known, m_unknown, warn_if_exceeded)
  if nargin < 3; warn_if_exceeded = true; end

  m_new = 0;

  % Sum all estimated subsystem masses
  parameters = fieldnames(m_unknown);
  for i = 1:numel(parameters)
    if not(strcmp(parameters{i}, 'mass_total') || strcmp(parameters{i}, 'm_margin') || ...
           strcmp(parameters{i}, 'mass_total_margin'))
      m_new = m_new + m_unknown.(parameters{i});
    endif
  endfor

  % Sum all user-supplied subsystem masses
  parameters = fieldnames(m_known);
  for i = 1:numel(parameters)
    if not(strcmp(parameters{i}, 'mass_total') || strcmp(parameters{i}, 'm_margin') || ...
           strcmp(parameters{i}, 'mass_total_margin'))
      m_new = m_new + m_known.(parameters{i});
    endif
  endfor

  if isfield(m_unknown, 'mass_total')
    m_tot        = m_unknown.mass_total;
    m_tot_margin = m_unknown.mass_total_margin;
    m_margin_old = m_unknown.m_margin;
  elseif isfield(m_known, 'mass_total')
    m_tot        = m_known.mass_total;
    m_tot_margin = m_known.mass_total_margin;
    m_margin_old = m_known.m_margin;
  end

  diff_m = m_tot_margin - m_new;

  m_margin          = m_margin_old + diff_m;
  mass_total_margin = m_tot - m_margin;

  if (m_new > m_tot || m_margin < 0)
    if warn_if_exceeded
      disp('Warning: Total mass limit exceeded!');
    end
    mass_total = m_new;
    m_margin   = 0;
  else
    mass_total = m_tot;
  endif
endfunction
