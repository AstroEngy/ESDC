% select_structure_components — Match structural bus hardware.
%
% Searches all technology types under the structure section of the reference
% database (e.g. CubeSat bus) for components whose mass best matches the
% design's estimated structural subsystem mass.
%
% Design reference:
%   ind.subsystem_masses.mass_structmech  [kg]  — target structural mass
%
% Results are appended to:
%   individual.component_matches.structure
%     .system_type             always 'all' (cross-technology search)
%     .design_mass_structmech  target structural mass [kg]
%     .candidates              struct array sorted by score (best first)
%       .name .score .type .mass .source
%       + geometry fields (length, width, height) when available

function evolution_data = select_structure_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'structure')
    return;
  end

  struct_db  = db_data.reference_data.structure;
  tech_types = fieldnames(struct_db);

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();
      cm.system_type = 'all';

      % --- Resolve design target ---
      d_mass = NaN;
      if isfield(ind, 'subsystem_masses') && ...
         isfield(ind.subsystem_masses, 'mass_structmech')
        d_mass = ind.subsystem_masses.mass_structmech;
      end

      cm.design_mass_structmech = d_mass;

      candidates = struct([]);

      for t = 1:numel(tech_types)
        tech = tech_types{t};
        component_types = fieldnames(struct_db.(tech));

        for ct = 1:numel(component_types)
          comp_type = component_types{ct};
          comp_data = struct_db.(tech).(comp_type);

          if ~iscell(comp_data)
            comp_data = {comp_data};
          end

          for k = 1:numel(comp_data)
            entry = comp_data{k};
            if ~isstruct(entry); continue; end

            e_mass   = scalar_midpoint(entry, 'mass');
            e_length = scalar_midpoint(entry, 'length');
            e_width  = scalar_midpoint(entry, 'width');
            e_height = scalar_midpoint(entry, 'height');

            if isnan(e_mass)
              continue;
            end

            % --- Score by mass proximity ---
            scores = [];
            if ~isnan(e_mass) && ~isnan(d_mass) && d_mass > 0
              scores(end+1) = 1 / (1 + abs(e_mass - d_mass) / d_mass);
            end

            total_score = 0;
            if ~isempty(scores)
              total_score = prod(scores) ^ (1 / numel(scores));
            end

            c.name   = get_str_field(entry, 'name', '(unnamed)');
            c.score  = total_score;
            c.type   = tech;
            c.mass   = e_mass;
            c.length = e_length;
            c.width  = e_width;
            c.height = e_height;
            c.source = get_str_field(entry, 'source', '');

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
      evolution_data{end}(i,j).component_matches.structure = cm;

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
