% select_obc_components — Match on-board computer hardware.
%
% Searches all technology types under the onboard_computer section of the
% reference database (ARM, AVR, x86, …) for components whose mass and
% nominal power best match the design's estimated OBC budget.
%
% Design references (in priority order):
%   ind.subsystem_masses.mass_OBC   [kg]  — targeted OBC mass
%   ind.mass_OBC                    [kg]  — alternative field name
%   ind.subsystem_powers.power_OBC  [W]   — targeted OBC power (optional)
%   ind.power_OBC                   [W]   — alternative field name
%
% Results are appended to:
%   individual.component_matches.onboard_computer
%     .system_type       always 'all' (cross-technology search)
%     .design_mass_obc   target OBC mass [kg]   (NaN if unavailable)
%     .design_power_obc  target OBC power [W]   (NaN if unavailable)
%     .candidates        struct array sorted by score (best first)
%       .name .score .type .mass .power_nom .power_max .storage_gb .source

function evolution_data = select_obc_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'onboard_computer')
    return;
  end

  obc_db     = db_data.reference_data.onboard_computer;
  tech_types = fieldnames(obc_db);

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

      % Mass: try subsystem_masses.mass_OBC, then top-level mass_OBC
      if isfield(ind, 'subsystem_masses') && ...
         isfield(ind.subsystem_masses, 'mass_OBC')
        d_mass = ind.subsystem_masses.mass_OBC;
      elseif isfield(ind, 'mass_OBC') && ~isnan(ind.mass_OBC)
        d_mass = ind.mass_OBC;
      end

      % Power: try subsystem_powers.power_OBC, then top-level power_OBC
      if isfield(ind, 'subsystem_powers') && ...
         isfield(ind.subsystem_powers, 'power_OBC')
        d_power = ind.subsystem_powers.power_OBC;
      elseif isfield(ind, 'power_OBC') && ~isnan(ind.power_OBC)
        d_power = ind.power_OBC;
      end

      cm.design_mass_obc  = d_mass;
      cm.design_power_obc = d_power;

      candidates = struct([]);

      for t = 1:numel(tech_types)
        tech = tech_types{t};
        component_types = fieldnames(obc_db.(tech));

        for ct = 1:numel(component_types)
          comp_type = component_types{ct};
          comp_data = obc_db.(tech).(comp_type);

          if ~iscell(comp_data)
            comp_data = {comp_data};
          end

          for k = 1:numel(comp_data)
            entry = comp_data{k};
            if ~isstruct(entry); continue; end

            e_mass      = scalar_midpoint(entry, 'mass');
            e_power_nom = scalar_midpoint(entry, 'power_nom');
            e_power_max = scalar_midpoint(entry, 'power_max');
            e_storage   = scalar_midpoint(entry, 'storage_gb');

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

            c.name       = get_str_field(entry, 'name', '(unnamed)');
            c.score      = total_score;
            c.type       = tech;
            c.mass       = e_mass;
            c.power_nom  = e_power_nom;
            c.power_max  = e_power_max;
            c.storage_gb = e_storage;
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
      evolution_data{end}(i,j).component_matches.onboard_computer = cm;

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
