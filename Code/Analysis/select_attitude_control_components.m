% select_attitude_control_components — Match ADCS actuator hardware.
%
% Searches all technology types under attitude_control (Magnetorquer,
% ReactionWheel, …) for components whose mass best matches the design's
% estimated ADCS mass.  Power consumption is used as a secondary scoring
% dimension when available.
%
% Design references:
%   ind.subsystem_masses.mass_adc    [kg]  — target ADCS subsystem mass
%   ind.subsystem_powers.power_adc   [W]   — target ADCS power (optional)
%
% Results are appended to:
%   individual.component_matches.attitude_control
%     .system_type          always 'all' (cross-technology search)
%     .design_mass_adc      target ADCS mass [kg]
%     .design_power_adc     target ADCS power [W]  (NaN if unavailable)
%     .candidates           struct array sorted by score (best first)
%       .name .score .type .mass .power_nom .source
%       + technology-specific fields (nom_mag_moment, momentum_storage, …)

function evolution_data = select_attitude_control_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'attitude_control')
    return;
  end

  adcs_db    = db_data.reference_data.attitude_control;
  tech_types = fieldnames(adcs_db);

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();
      cm.system_type = 'all';

      % --- Resolve design targets ---
      d_mass  = NaN;
      d_power = NaN;
      if isfield(ind, 'subsystem_masses') && ...
         isfield(ind.subsystem_masses, 'mass_adc')
        d_mass = ind.subsystem_masses.mass_adc;
      end
      if isfield(ind, 'subsystem_powers') && ...
         isfield(ind.subsystem_powers, 'power_adc')
        d_power = ind.subsystem_powers.power_adc;
      end

      cm.design_mass_adc  = d_mass;
      cm.design_power_adc = d_power;

      candidates = struct([]);

      for t = 1:numel(tech_types)
        tech = tech_types{t};
        component_types = fieldnames(adcs_db.(tech));

        for ct = 1:numel(component_types)
          comp_type = component_types{ct};
          comp_data = adcs_db.(tech).(comp_type);

          if ~iscell(comp_data)
            comp_data = {comp_data};
          end

          for k = 1:numel(comp_data)
            entry = comp_data{k};
            if ~isstruct(entry); continue; end

            e_mass      = scalar_midpoint(entry, 'mass');
            e_power_nom = scalar_midpoint(entry, 'power_nom');

            % Technology-specific performance fields
            e_mag_moment    = scalar_midpoint(entry, 'nom_mag_moment');
            e_momentum      = scalar_midpoint(entry, 'momentum_storage');
            e_torque        = scalar_midpoint(entry, 'torque_max');

            if isnan(e_mass)
              continue;
            end

            % --- Score by mass proximity (primary), power (secondary) ---
            scores = [];
            if ~isnan(e_mass) && ~isnan(d_mass) && d_mass > 0
              scores(end+1) = 1 / (1 + abs(e_mass - d_mass) / d_mass);
            end
            if ~isnan(e_power_nom) && ~isnan(d_power) && d_power > 0
              scores(end+1) = 1 / (1 + abs(e_power_nom - d_power) / d_power);
            end

            total_score = 0;
            if ~isempty(scores)
              total_score = prod(scores) ^ (1 / numel(scores));
            end

            c.name             = get_str_field(entry, 'name', '(unnamed)');
            c.score            = total_score;
            c.type             = tech;
            c.mass             = e_mass;
            c.power_nom        = e_power_nom;
            c.nom_mag_moment   = e_mag_moment;
            c.momentum_storage = e_momentum;
            c.torque_max       = e_torque;
            c.source           = get_str_field(entry, 'source', '');

            if isempty(candidates)
              candidates = c;
            else
              candidates(end+1) = c;
            end
          end  % component loop
        end  % component type loop
      end  % technology type loop

      if ~isempty(candidates)
        [~, idx] = sort([candidates.score], 'descend');
        candidates = candidates(idx);
      end

      cm.candidates = candidates;
      evolution_data{end}(i,j).component_matches.attitude_control = cm;

    end  % seed loop
  end  % case loop

end


% -------------------------------------------------------------------------
function val = scalar_midpoint(entry, field)
  val = NaN;
  if ~isfield(entry, field); return; end
  v = entry.(field);
  if isnumeric(v) && isscalar(v)
    val = v;
  elseif iscell(v)
    for _ci = 1:numel(v)
      tmp.x = v{_ci};
      candidate = scalar_midpoint(tmp, 'x');
      if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        val = candidate; return;
      end
    end
  elseif isstruct(v)
    if isfield(v, 'nominal')
      val = v.nominal;
    elseif isfield(v, 'min') && isfield(v, 'max')
      val = (v.min + v.max) / 2;
    elseif isfield(v, 'min')
      val = v.min;
    elseif isfield(v, 'max')
      val = v.max;
    end
  end
end

function s = get_str_field(entry, field, default)
  if isfield(entry, field) && ischar(entry.(field))
    s = entry.(field);
  else
    s = default;
  end
end
