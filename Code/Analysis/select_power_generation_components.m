% select_power_generation_components — Match power generation hardware.
%
% Searches the power_generation section of the reference database for
% components (solar panels and batteries) and ranks them by proximity to
% the design's power and energy demands.  All technology types are searched.
%
% Scoring strategy:
%   solar / photovoltaic  — scored by power_max proximity to design power total
%   battery               — scored by energy_wh proximity to required battery
%                           energy (ind.battery.E_battery_required_max [Wh])
%                           if available, else by power_max proximity
%
% Design references (in priority order):
%   ind.subsystem_powers.power_total        [W]   for solar scoring
%   ind.power_propulsion                    [W]   fallback for solar
%   ind.battery.E_battery_required_max      [Wh]  for battery scoring
%
% Results are appended to:
%   individual.component_matches.power_generation
%     .system_type          always 'all' (cross-technology search)
%     .design_power_total   target total system power [W]
%     .design_energy_wh     required battery energy [Wh]  (NaN if unknown)
%     .candidates           struct array sorted by score (best first)
%       .name .score .type .power_max .energy_wh .efficiency .mass .source

function evolution_data = select_power_generation_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'power_generation')
    return;
  end

  power_db = db_data.reference_data.power_generation;
  tech_types = fieldnames(power_db);

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();
      cm.system_type = 'all';

      % --- Resolve design power target ---
      d_power = NaN;
      if isfield(ind, 'subsystem_powers') && ...
         isfield(ind.subsystem_powers, 'power_total')
        d_power = ind.subsystem_powers.power_total;
      elseif isfield(ind, 'power_propulsion') && ~isnan(ind.power_propulsion)
        d_power = ind.power_propulsion;
      end

      % --- Resolve battery energy target ---
      d_energy_wh = NaN;
      if isfield(ind, 'battery') && isstruct(ind.battery) && ...
         isfield(ind.battery, 'E_battery_required_max')
        d_energy_wh = ind.battery.E_battery_required_max;
      end

      cm.design_power_total = d_power;
      cm.design_energy_wh   = d_energy_wh;

      candidates = struct([]);

      for t = 1:numel(tech_types)
        tech = tech_types{t};
        component_types = fieldnames(power_db.(tech));

        for ct = 1:numel(component_types)
          comp_type = component_types{ct};
          comp_data = power_db.(tech).(comp_type);

          if ~iscell(comp_data)
            comp_data = {comp_data};
          end

          for k = 1:numel(comp_data)
            entry = comp_data{k};
            if ~isstruct(entry); continue; end

            e_power_max  = scalar_midpoint(entry, 'power_max');
            e_energy_wh  = scalar_midpoint(entry, 'energy_wh');
            e_mass       = scalar_midpoint(entry, 'mass');
            e_eff        = scalar_midpoint(entry, 'efficiency');
            is_battery   = strcmpi(tech, 'battery');

            if isnan(e_power_max) && isnan(e_energy_wh) && isnan(e_mass)
              continue;
            end

            % --- Score: batteries by energy_wh (or power_max fallback),
            %            solar by power_max ---
            scores = [];
            if is_battery
              if ~isnan(e_energy_wh) && ~isnan(d_energy_wh) && d_energy_wh > 0
                scores(end+1) = 1 / (1 + abs(e_energy_wh - d_energy_wh) / d_energy_wh);
              elseif ~isnan(e_power_max) && ~isnan(d_power) && d_power > 0
                scores(end+1) = 1 / (1 + abs(e_power_max - d_power) / d_power);
              end
            else
              if ~isnan(e_power_max) && ~isnan(d_power) && d_power > 0
                scores(end+1) = 1 / (1 + abs(e_power_max - d_power) / d_power);
              end
            end

            total_score = 0;
            if ~isempty(scores)
              total_score = prod(scores) ^ (1 / numel(scores));
            end

            c.name       = get_str_field(entry, 'name', '(unnamed)');
            c.score      = total_score;
            c.type       = tech;
            c.power_max  = e_power_max;
            c.energy_wh  = e_energy_wh;
            c.efficiency = e_eff;
            c.mass       = e_mass;
            c.source     = get_str_field(entry, 'source', '');

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
      evolution_data{end}(i,j).component_matches.power_generation = cm;

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
  elseif isstruct(v) && isfield(v, 'min') && isfield(v, 'max')
    val = (v.min + v.max) / 2;
  end
end

function s = get_str_field(entry, field, default)
  if isfield(entry, field) && ischar(entry.(field))
    s = entry.(field);
  else
    s = default;
  end
end
