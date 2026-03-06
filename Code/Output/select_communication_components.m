% select_communication_components — Match communication hardware.
%
% Searches all technology types under the communication section of the
% reference database (e.g. Laser, RF) for components whose mass best matches
% the design's estimated TTC subsystem mass.  Downlink rate and power
% consumption are used as secondary scoring dimensions when available.
%
% Design references:
%   ind.subsystem_masses.mass_ttc   [kg]  — target TTC subsystem mass
%   ind.subsystem_powers.power_ttc  [W]   — target TTC power (optional)
%
% Results are appended to:
%   individual.component_matches.communication
%     .system_type         always 'all' (cross-technology search)
%     .design_mass_ttc     target TTC mass [kg]
%     .design_power_ttc    target TTC power [W]  (NaN if unavailable)
%     .candidates          struct array sorted by score (best first)
%       .name .score .type .mass .power .downlink .source

function evolution_data = select_communication_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'communication')
    return;
  end

  comm_db    = db_data.reference_data.communication;
  tech_types = fieldnames(comm_db);

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
         isfield(ind.subsystem_masses, 'mass_ttc')
        d_mass = ind.subsystem_masses.mass_ttc;
      end
      if isfield(ind, 'subsystem_powers') && ...
         isfield(ind.subsystem_powers, 'power_ttc')
        d_power = ind.subsystem_powers.power_ttc;
      end

      cm.design_mass_ttc  = d_mass;
      cm.design_power_ttc = d_power;

      candidates = struct([]);

      for t = 1:numel(tech_types)
        tech = tech_types{t};
        component_types = fieldnames(comm_db.(tech));

        for ct = 1:numel(component_types)
          comp_type = component_types{ct};
          comp_data = comm_db.(tech).(comp_type);

          % Communication DB entries may be a single struct (not always cell)
          if ~iscell(comp_data)
            comp_data = {comp_data};
          end

          for k = 1:numel(comp_data)
            entry = comp_data{k};
            if ~isstruct(entry); continue; end

            e_mass     = scalar_midpoint(entry, 'mass');
            e_power    = scalar_midpoint(entry, 'power');
            e_downlink = scalar_midpoint(entry, 'downlink');

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

            c.name     = get_str_field(entry, 'name', '(unnamed)');
            c.score    = total_score;
            c.type     = tech;
            c.mass     = e_mass;
            c.power    = e_power;
            c.downlink = e_downlink;
            c.source   = get_str_field(entry, 'source', '');

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
      evolution_data{end}(i,j).component_matches.communication = cm;

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
