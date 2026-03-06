% select_propulsion_components — Match thruster hardware for each design individual.
%
% For each individual in evolution_data{end}, searches the propulsion_system
% section of the reference database for thrusters matching the design's
% technology type and propellant.  Candidates are ranked by a geometric-mean
% proximity score over thrust, c_e and jet power.
%
% Results are appended to:
%   individual.component_matches.propulsion_system
%     .system_type       propulsion technology (e.g. 'arcjet')
%     .propellant        propellant string
%     .design_thrust     target thrust  [N]
%     .design_c_e        target c_e     [m/s]
%     .design_power_jet  target jet power [W]
%     .candidates        struct array sorted by score (best first)
%       .name .score .thrust .c_e .power_jet .mass .propellant .TRL .source

function evolution_data = select_propulsion_components(evolution_data, db_data)

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'propulsion_system')
    return;
  end

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();

      % Skip individuals without a valid propulsion design point
      if ~isfield(ind, 'propulsion_system') || isempty(ind.propulsion_system) || ...
         ~isfield(ind, 'c_e')   || ~isfield(ind, 'thrust') || ...
         isnan(ind.c_e) || isnan(ind.thrust)
        cm.system_type = '';
        cm.candidates  = struct([]);
        evolution_data{end}(i,j).component_matches.propulsion_system = cm;
        continue;
      end

      prop_sys   = ind.propulsion_system;
      propellant = ind.propellant;
      d_thrust   = ind.thrust;
      d_c_e      = ind.c_e;
      d_power    = ind.power_jet;

      cm.system_type      = prop_sys;
      cm.propellant       = propellant;
      cm.design_thrust    = d_thrust;
      cm.design_c_e       = d_c_e;
      cm.design_power_jet = d_power;

      if ~isfield(db_data.reference_data.propulsion_system, prop_sys)
        cm.candidates = struct([]);
        evolution_data{end}(i,j).component_matches.propulsion_system = cm;
        continue;
      end

      thruster_data = db_data.reference_data.propulsion_system.(prop_sys).thruster;
      if ~iscell(thruster_data)
        thruster_data = {thruster_data};
      end

      candidates = struct([]);

      for k = 1:numel(thruster_data)
        entry = thruster_data{k};

        % --- Propellant filter ---
        if isfield(entry, 'propellant')
          if ~strcmpi(entry.propellant, propellant)
            continue;
          end
        end

        % --- Extract scalar values (handle min/max ranges via midpoint) ---
        e_thrust = scalar_midpoint(entry, 'thrust');
        e_c_e    = scalar_midpoint(entry, 'c_e');
        e_power  = scalar_midpoint(entry, 'power_jet');
        e_mass   = scalar_midpoint(entry, 'mass');
        e_TRL    = scalar_midpoint(entry, 'TRL');

        % Skip entries with no key performance data
        if isnan(e_thrust) && isnan(e_c_e) && isnan(e_power)
          continue;
        end

        % --- Proximity score: geometric mean of available dimensions ---
        scores = [];
        if ~isnan(e_thrust) && d_thrust > 0
          scores(end+1) = 1 / (1 + abs(e_thrust - d_thrust) / d_thrust);
        end
        if ~isnan(e_c_e) && d_c_e > 0
          scores(end+1) = 1 / (1 + abs(e_c_e - d_c_e) / d_c_e);
        end
        if ~isnan(e_power) && d_power > 0
          scores(end+1) = 1 / (1 + abs(e_power - d_power) / d_power);
        end

        total_score = 0;
        if ~isempty(scores)
          total_score = prod(scores) ^ (1 / numel(scores));
        end

        c.name       = get_str_field(entry, 'name', '(unnamed)');
        c.score      = total_score;
        c.thrust     = e_thrust;
        c.c_e        = e_c_e;
        c.power_jet  = e_power;
        c.mass       = e_mass;
        c.propellant = get_str_field(entry, 'propellant', propellant);
        c.TRL        = e_TRL;
        c.source     = get_str_field(entry, 'source', '');

        if isempty(candidates)
          candidates = c;
        else
          candidates(end+1) = c;
        end
      end  % thruster loop

      if ~isempty(candidates)
        [~, idx] = sort([candidates.score], 'descend');
        candidates = candidates(idx);
      end

      cm.candidates = candidates;
      evolution_data{end}(i,j).component_matches.propulsion_system = cm;

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
