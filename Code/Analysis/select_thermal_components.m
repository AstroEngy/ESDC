% select_thermal_components — Match thermal control hardware.
%
% Searches the thermal section of the reference database for components
% (currently active heaters) whose mass best matches the design's estimated
% thermal subsystem mass.  Heater power is used as a secondary scoring
% dimension when available.
%
% Design references:
%   ind.subsystem_masses.mass_thermal   [kg]  — target thermal subsystem mass
%   ind.subsystem_powers.power_thermal  [W]   — target thermal power (optional)
%
% Results are appended to:
%   individual.component_matches.thermal
%     .system_type           always 'active' (passive components skipped)
%     .design_mass_thermal   target thermal mass [kg]
%     .design_power_thermal  target thermal power [W]  (NaN if unavailable)
%     .candidates            struct array sorted by score (best first)
%       .name .score .type .mass .power .source

function evolution_data = select_thermal_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'thermal')
    return;
  end

  thermal_db = db_data.reference_data.thermal;

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();
      cm.system_type = 'active';

      % --- Resolve design targets ---
      d_mass  = NaN;
      d_power = NaN;
      if isfield(ind, 'subsystem_masses') && ...
         isfield(ind.subsystem_masses, 'mass_thermal')
        d_mass = ind.subsystem_masses.mass_thermal;
      end
      if isfield(ind, 'subsystem_powers') && ...
         isfield(ind.subsystem_powers, 'power_thermal')
        d_power = ind.subsystem_powers.power_thermal;
      end

      cm.design_mass_thermal  = d_mass;
      cm.design_power_thermal = d_power;

      candidates = struct([]);

      % --- Search active heater components ---
      if isfield(thermal_db, 'active') && isfield(thermal_db.active, 'heater')
        heater_data = thermal_db.active.heater;
        if ~iscell(heater_data)
          heater_data = {heater_data};
        end

        for k = 1:numel(heater_data)
          entry = heater_data{k};
          if ~isstruct(entry); continue; end

          e_mass  = scalar_midpoint(entry, 'mass');
          e_power = scalar_midpoint(entry, 'power');
          e_volt  = scalar_midpoint(entry, 'voltage');

          if isnan(e_mass)
            continue;
          end

          % --- Score by mass proximity (primary), power (secondary) ---
          scores = [];
          if ~isnan(e_mass) && ~isnan(d_mass) && d_mass > 0
            scores(end+1) = 1 / (1 + abs(e_mass - d_mass) / d_mass);
          end
          if ~isnan(e_power) && ~isnan(d_power) && d_power > 0
            scores(end+1) = 1 / (1 + abs(e_power - d_power) / d_power);
          end

          total_score = 0;
          if ~isempty(scores)
            total_score = prod(scores) ^ (1 / numel(scores));
          end

          c.name    = get_str_field(entry, 'name', '(unnamed)');
          c.score   = total_score;
          c.type    = get_str_field(entry, 'type', 'electric');
          c.mass    = e_mass;
          c.power   = e_power;
          c.voltage = e_volt;
          c.source  = get_str_field(entry, 'source', '');

          if isempty(candidates)
            candidates = c;
          else
            candidates(end+1) = c;
          end
        end  % heater loop
      end  % active branch

      if ~isempty(candidates)
        [~, idx] = sort([candidates.score], 'descend');
        candidates = candidates(idx);
      end

      cm.candidates = candidates;
      evolution_data{end}(i,j).component_matches.thermal = cm;

    end  % seed loop
  end  % case loop

end
