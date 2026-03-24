% select_propulsion_components — Match thruster, tank, PPU hardware for each design individual.
%
% For each individual in evolution_data{end}, searches the propulsion_system
% section of the reference database and selects:
%   1. Thruster (or cluster) — must deliver >= design thrust
%   2. Propellant tank       — must hold >= design propellant mass; scored by mass proximity
%   3. PPU                   — for electric propulsion types, if required and not already
%                              included in the thruster entry; must handle <= design power
%   4. Piping                — represented as a fixed fraction of total dry propulsion mass
%
% Thruster selection rules:
%   - Minimum cluster count n = ceil(d_thrust / e_thrust) so cluster thrust >= design thrust.
%   - Cluster jet power (n * e_power) must be <= design power_jet.
%   - Cluster mass must be <= available propulsion system mass budget (soft constraint;
%     over-budget candidates kept as fallback sorted by ascending cluster mass).
%   - c_e scored for proximity; power budget utilisation used as secondary score.
%
% Cluster scaling for n thrusters:
%   thrust, power_jet, mass all scale with n.  c_e / Isp unchanged.
%
% PPU requirement:
%   Electric propulsion types (arcjet, gridionthruster, HET, FEEP, electrospray, ion)
%   require a PPU unless the thruster entry already contains one (detected by a
%   'PPU_included' flag or the type string containing 'system').
%   PPU is selected from db_data.reference_data.propulsion_system.<type>.ppu.
%   The PPU whose input power most closely matches (and does not exceed) the design
%   jet power is preferred.
%
% Piping:
%   Piping mass is estimated as PIPING_FRACTION * (thruster_cluster_mass + tank_mass + ppu_mass).
%   Default fraction: 0.05 (5 %).
%
% Results are appended to:
%   individual.component_matches.propulsion_system
%     .system_type              technology (e.g. 'arcjet')
%     .propellant               propellant string
%     .design_thrust            [N]
%     .design_c_e               [m/s]
%     .design_power_jet         [W]
%     .design_propellant_mass   [kg] (from subsystem_masses.mass_propellant)
%     .design_mass_budget       [kg] (from subsystem_masses.mass_propulsion)
%     .piping_fraction          dimensionless fraction used for piping estimate
%     .no_solution_within_mass_budget   0/1 flag
%     .thruster_candidates      struct array (best first)
%     .tank_candidates          struct array (best first)
%     .ppu_candidates           struct array (best first, empty if PPU not required)

function evolution_data = select_propulsion_components(evolution_data, db_data)

  EP_TYPES = {'arcjet','gridionthruster','HET','FEEP','electrospray','ion'};
  PIPING_FRACTION = 0.05;

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'propulsion_system')
    return;
  end

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();         %component matches

      % Skip individuals without a valid propulsion design point
      if ~isfield(ind, 'propulsion_system') || isempty(ind.propulsion_system) || ...
         ~isfield(ind, 'c_e')   || ~isfield(ind, 'thrust') || ...
         isnan(ind.c_e) || isnan(ind.thrust)
        cm.system_type = '';
        cm.thruster_candidates = struct([]);
        cm.tank_candidates     = struct([]);
        cm.ppu_candidates      = struct([]);
        evolution_data{end}(i,j).component_matches.propulsion_system = cm;
        continue;
      end

      prop_sys   = ind.propulsion_system;
      propellant = ind.propellant;
      d_thrust   = ind.thrust;
      d_c_e      = ind.c_e;
      d_power    = ind.power_jet;

      % Propellant mass (for tank sizing)
      d_prop_mass = NaN;
      if isfield(ind, 'subsystem_masses') && isfield(ind.subsystem_masses, 'mass_propellant')
        d_prop_mass = ind.subsystem_masses.mass_propellant;
      end

      % Available dry propulsion system mass budget
      d_mass_budget = NaN;
      if isfield(ind, 'subsystem_masses') && isfield(ind.subsystem_masses, 'mass_propulsion')
        d_mass_budget = ind.subsystem_masses.mass_propulsion;
      end

      cm.system_type             = prop_sys;
      cm.propellant              = propellant;
      cm.design_thrust           = d_thrust;
      cm.design_c_e             = d_c_e;
      cm.design_power_jet        = d_power;
      cm.design_propellant_mass  = d_prop_mass;
      cm.design_mass_budget      = d_mass_budget;
      cm.piping_fraction         = PIPING_FRACTION;

      % Reserve piping mass upfront; hardware components must fit within the remainder.
      piping_reserved = NaN;
      hardware_mass_budget = d_mass_budget;
      if ~isnan(d_mass_budget)
        piping_reserved      = PIPING_FRACTION * d_mass_budget;
        hardware_mass_budget = d_mass_budget - piping_reserved;
      end
      cm.piping_mass_reserved    = piping_reserved;
      cm.hardware_mass_budget    = hardware_mass_budget;

      % Scaling-hint masses from the last successful lineage (subsystem mass model).
      % These are the component mass estimates the evolver converged on; they act as
      % the first starting point — hardware matching them ranks first — while the
      % full DB search cross-verifies whether alternative solutions perform better.
      hint_thruster_mass = NaN;
      hint_tank_mass     = NaN;
      hint_ppu_mass      = NaN;
      if isfield(ind, 'subsystem_masses') && isfield(ind.subsystem_masses, 'propulsion')
        pm = ind.subsystem_masses.propulsion;
        if isfield(pm, 'm_thruster') && ~isnan(pm.m_thruster); hint_thruster_mass = pm.m_thruster; end
        if isfield(pm, 'm_tank')     && ~isnan(pm.m_tank);     hint_tank_mass     = pm.m_tank;     end
        if isfield(pm, 'm_PPU')      && ~isnan(pm.m_PPU);      hint_ppu_mass      = pm.m_PPU;      end
      end
      cm.hint_thruster_mass = hint_thruster_mass;
      cm.hint_tank_mass     = hint_tank_mass;
      cm.hint_ppu_mass      = hint_ppu_mass;

      if ~isfield(db_data.reference_data.propulsion_system, prop_sys)
        cm.thruster_candidates = struct([]);
        cm.tank_candidates     = struct([]);
        cm.ppu_candidates      = struct([]);
        evolution_data{end}(i,j).component_matches.propulsion_system = cm;
        continue;
      end

      ps_db = db_data.reference_data.propulsion_system.(prop_sys);

      % ----------------------------------------------------------------
      % 1. THRUSTER SELECTION
      % ----------------------------------------------------------------
      [thruster_cands, thruster_cands_ob] = select_thrusters(ps_db, propellant, ...
          d_thrust, d_c_e, d_power, hardware_mass_budget, hint_thruster_mass);

      if ~isempty(thruster_cands)
        cm.no_solution_within_mass_budget = 0;
        cm.thruster_candidates = thruster_cands;
      elseif ~isempty(thruster_cands_ob)
        cm.no_solution_within_mass_budget = 1;
        cm.thruster_candidates = thruster_cands_ob;
      else
        cm.no_solution_within_mass_budget = 1;
        cm.thruster_candidates = struct([]);
      end

      % ----------------------------------------------------------------
      % 2. TANK SELECTION
      % ----------------------------------------------------------------
      cm.tank_candidates = select_tanks(db_data, propellant, d_prop_mass, hint_tank_mass);

      % ----------------------------------------------------------------
      % 3. PPU SELECTION
      % ----------------------------------------------------------------
      needs_ppu = any(strcmpi(prop_sys, EP_TYPES));
      if needs_ppu && isfield(ps_db, 'ppu')
        cm.ppu_candidates = select_ppu(ps_db.ppu, prop_sys, d_power, hint_ppu_mass);
      else
        cm.ppu_candidates = struct([]);
      end

      evolution_data{end}(i,j).component_matches.propulsion_system = cm;

    end  % seed loop
  end  % case loop

end


% =========================================================================
% THRUSTER SELECTION
% Returns [within_budget_cands, over_budget_cands] sorted by score / mass.
% =========================================================================
function [cands, cands_ob] = select_thrusters(ps_db, propellant, d_thrust, d_c_e, d_power, d_mass_budget, hint_mass)
  % hint_mass: scaling-model thruster cluster mass from last successful lineage (NaN = no hint).
  if nargin < 7; hint_mass = NaN; end
  cands    = struct([]);
  cands_ob = struct([]);

  if ~isfield(ps_db, 'thruster'); return; end
  thruster_data = ps_db.thruster;
  if ~iscell(thruster_data); thruster_data = {thruster_data}; end

  for k = 1:numel(thruster_data)
    entry = thruster_data{k};

    % Propellant filter
    if isfield(entry, 'propellant')
      if ~propellant_match(entry.propellant, propellant)
        continue;
      end
    end

    e_thrust = scalar_midpoint(entry, 'thrust');
    e_c_e    = scalar_midpoint(entry, 'c_e');
    e_power  = scalar_midpoint(entry, 'power_jet');
    e_mass   = scalar_midpoint(entry, 'mass');
    e_TRL    = scalar_midpoint(entry, 'TRL');

    if isnan(e_thrust) || e_thrust <= 0; continue; end

    % Cluster sizing
    n = ceil(d_thrust / e_thrust);
    if n < 1; n = 1; end
    cluster_thrust = n * e_thrust;
    cluster_power  = n * e_power;
    cluster_mass   = n * e_mass;

    % Hard constraint: power
    if ~isnan(cluster_power) && ~isnan(d_power) && d_power > 0
      if cluster_power > d_power; continue; end
    end

    % Soft constraint: mass
    mass_exceeds_budget = false;
    if ~isnan(cluster_mass) && ~isnan(d_mass_budget) && d_mass_budget > 0
      mass_exceeds_budget = cluster_mass > d_mass_budget;
    end

    % Score
    score_c_e       = 0;
    score_power     = 0;
    score_mass_hint = 0;
    if ~isnan(e_c_e) && d_c_e > 0
      score_c_e = 1 / (1 + abs(e_c_e - d_c_e) / d_c_e);
    end
    if ~isnan(cluster_power) && ~isnan(d_power) && d_power > 0
      score_power = cluster_power / d_power;
    end
    % Lineage-hint mass proximity: promotes hardware whose cluster mass matches
    % the scaling-model prediction from the last successful lineage (first starting point).
    if ~isnan(hint_mass) && hint_mass > 0 && ~isnan(cluster_mass)
      score_mass_hint = 1 / (1 + abs(cluster_mass - hint_mass) / hint_mass);
    end
    % Geometric mean of all available score components (cross-verification).
    score_factors = [];
    if ~isnan(e_c_e) && d_c_e > 0;  score_factors(end+1) = score_c_e;       end
    if score_power > 0;              score_factors(end+1) = score_power;     end
    if score_mass_hint > 0;          score_factors(end+1) = score_mass_hint; end
    if ~isempty(score_factors)
      total_score = prod(score_factors)^(1/numel(score_factors));
    else
      total_score = 0;
    end

    c.name                = get_str_field(entry, 'name', '(unnamed)');
    c.company             = get_str_field(entry, 'company', '');
    c.score               = total_score;
    c.n_thrusters         = n;
    c.thrust_single       = e_thrust;
    c.thrust_cluster      = cluster_thrust;
    c.c_e                 = e_c_e;
    c.power_jet_single    = e_power;
    c.power_jet_cluster   = cluster_power;
    c.mass_single         = e_mass;
    c.mass_cluster        = cluster_mass;
    c.propellant          = get_str_field(entry, 'propellant', propellant);
    c.TRL                 = e_TRL;
    c.source              = get_str_field(entry, 'source', '');
    c.mass_exceeds_budget = double(mass_exceeds_budget);

    if mass_exceeds_budget
      if isempty(cands_ob); cands_ob = c; else; cands_ob(end+1) = c; end
    else
      if isempty(cands);    cands = c;    else; cands(end+1) = c;    end
    end
  end

  if ~isempty(cands)
    [~, idx] = sort([cands.score], 'descend');
    cands = cands(idx);
  end
  if ~isempty(cands_ob)
    [~, idx] = sort([cands_ob.mass_cluster], 'ascend');
    cands_ob = cands_ob(idx);
  end
end


% =========================================================================
% TANK SELECTION
% Selects from the top-level tank.vessel list in the propulsion_system DB.
% A tank must hold >= d_prop_mass of propellant (if known).
% Candidates are sorted by ascending tank mass (lightest sufficient tank first).
% =========================================================================
% =========================================================================
% TANK SELECTION
% Selects from the top-level tank.vessel list in the propulsion_system DB.
% A single tank or a cluster of identical tanks (n_tanks) must together hold
% >= d_prop_mass of propellant.  n_tanks = ceil(d_prop_mass / e_prop_cap).
% Candidates are sorted by ascending cluster mass (lightest sufficient first).
% =========================================================================
function cands = select_tanks(db_data, propellant, d_prop_mass, hint_mass)
  % hint_mass: scaling-model tank cluster mass from last successful lineage (NaN = no hint).
  if nargin < 4; hint_mass = NaN; end
  cands = struct([]);

  % Tank data lives at propulsion_system.tank.vessel (not per-type)
  ps_db = db_data.reference_data.propulsion_system;
  if ~isfield(ps_db, 'tank') || ~isfield(ps_db.tank, 'vessel')
    return;
  end
  tank_data = ps_db.tank.vessel;
  if ~iscell(tank_data); tank_data = {tank_data}; end

  for k = 1:numel(tank_data)
    entry = tank_data{k};

    % Propellant compatibility filter (skip if propellant field known and mismatches)
    if isfield(entry, 'propellant') && ~isempty(entry.propellant)
      if ~propellant_match(entry.propellant, propellant)
        continue;
      end
    end

    e_mass      = scalar_midpoint(entry, 'mass');
    e_prop_cap  = scalar_midpoint(entry, 'mass_propellant');  % capacity [kg]
    e_volume    = scalar_midpoint(entry, 'volume');
    e_pressure  = scalar_midpoint(entry, 'pressure');

    % Determine number of tanks needed to cover the required propellant mass
    n_tanks = 1;
    if ~isnan(e_prop_cap) && e_prop_cap > 0 && ~isnan(d_prop_mass) && d_prop_mass > 0
      n_tanks = ceil(d_prop_mass / e_prop_cap);
    elseif isnan(e_prop_cap) && ~isnan(d_prop_mass) && d_prop_mass > 0
      % No capacity data — cannot verify coverage; keep but flag
      n_tanks = NaN;
    end

    cluster_mass     = n_tanks * e_mass;     % NaN if e_mass or n_tanks NaN
    cluster_cap      = n_tanks * e_prop_cap; % NaN if either NaN

    % Score: how closely the cluster capacity matches the required propellant mass
    % (excess capacity penalised; a perfect fit scores 1)
    score = 0;
    if ~isnan(cluster_cap) && ~isnan(d_prop_mass) && d_prop_mass > 0
      score = 1 / (1 + (cluster_cap - d_prop_mass) / d_prop_mass);
    end
    % Lineage-hint mass proximity: promotes tanks whose cluster mass matches the
    % scaling-model prediction; geometric mean with capacity-fit score.
    score_mass_hint = 0;
    if ~isnan(hint_mass) && hint_mass > 0 && ~isnan(cluster_mass)
      score_mass_hint = 1 / (1 + abs(cluster_mass - hint_mass) / hint_mass);
    end
    if score > 0 && score_mass_hint > 0
      score = sqrt(score * score_mass_hint);
    elseif score_mass_hint > 0
      score = score_mass_hint;
    end

    % Propellant field as a readable string for output
    if isfield(entry, 'propellant')
      if ischar(entry.propellant)
        prop_str = entry.propellant;
      elseif iscell(entry.propellant)
        prop_str = strjoin(entry.propellant, ', ');
      else
        prop_str = '';
      end
    else
      prop_str = '';
    end

    c.name             = get_str_field(entry, 'name', '(unnamed)');
    c.company          = get_str_field(entry, 'company', '');
    c.type             = get_str_field(entry, 'type', 'tank');
    c.score            = score;
    c.n_tanks          = n_tanks;
    c.mass_single      = e_mass;
    c.mass_cluster     = cluster_mass;
    c.capacity_kg_single = e_prop_cap;
    c.capacity_kg_cluster = cluster_cap;
    c.volume_L         = e_volume;
    c.pressure_Pa      = e_pressure;
    c.propellant       = prop_str;
    c.source           = get_str_field(entry, 'source', '');

    if isempty(cands); cands = c; else; cands(end+1) = c; end
  end

  % Sort by score descending (best fit first), then by cluster mass ascending as tiebreak
  if ~isempty(cands)
    scores  = [cands.score];
    masses  = [cands.mass_cluster];
    masses(isnan(masses)) = Inf;
    % Combined sort: primary descending score, secondary ascending mass
    [~, idx] = sortrows([-scores(:), masses(:)]);
    cands = cands(idx);
  end
end


% =========================================================================
% PPU SELECTION
% Selects from ps_db.ppu.  PPU input power must not exceed design jet power.
% Sorted by power proximity (closest without exceeding d_power first).
% =========================================================================
function cands = select_ppu(ppu_db, prop_sys, d_power, hint_mass)
  % hint_mass: scaling-model PPU mass from last successful lineage (NaN = no hint).
  if nargin < 4; hint_mass = NaN; end
  cands = struct([]);

  % ppu_db may be a single struct or a cell array of structs
  if isstruct(ppu_db) && ~iscell(ppu_db)
    % Could be a single entry directly (not in a list)
    if isfield(ppu_db, 'name')
      ppu_list = {ppu_db};
    else
      % Struct with fields that are each a PPU entry — flatten to list
      fn = fieldnames(ppu_db);
      ppu_list = {};
      for f = 1:numel(fn)
        ppu_list{end+1} = ppu_db.(fn{f});
      end
    end
  elseif iscell(ppu_db)
    ppu_list = ppu_db;
  else
    return;
  end

  for k = 1:numel(ppu_list)
    entry = ppu_list{k};
    if ~isstruct(entry); continue; end

    e_power = scalar_midpoint(entry, 'power');
    e_mass  = scalar_midpoint(entry, 'mass');
    e_eff   = scalar_midpoint(entry, 'efficiency');
    e_TRL   = scalar_midpoint(entry, 'TRL');

    % PPU power must not exceed design jet power
    if ~isnan(e_power) && ~isnan(d_power) && d_power > 0
      if e_power > d_power; continue; end
    end

    % Score: power utilisation (closer to d_power is better)
    score = 0;
    if ~isnan(e_power) && ~isnan(d_power) && d_power > 0
      score = e_power / d_power;
    end
    % Lineage-hint mass proximity: promotes PPUs whose mass matches the
    % scaling-model prediction; geometric mean with power-utilisation score.
    score_mass_hint = 0;
    if ~isnan(hint_mass) && hint_mass > 0 && ~isnan(e_mass)
      score_mass_hint = 1 / (1 + abs(e_mass - hint_mass) / hint_mass);
    end
    if score > 0 && score_mass_hint > 0
      score = sqrt(score * score_mass_hint);
    elseif score_mass_hint > 0
      score = score_mass_hint;
    end

    c.name        = get_str_field(entry, 'name', '(unnamed)');
    c.company     = get_str_field(entry, 'company', '');
    c.score       = score;
    c.power       = e_power;
    c.mass        = e_mass;
    c.efficiency  = e_eff;
    c.TRL         = e_TRL;
    c.source      = get_str_field(entry, 'source', '');

    if isempty(cands); cands = c; else; cands(end+1) = c; end
  end

  if ~isempty(cands)
    [~, idx] = sort([cands.score], 'descend');
    cands = cands(idx);
  end
end


% =========================================================================
% HELPERS
% =========================================================================

% Returns true if the DB propellant field (string or cell) matches the target.
function ok = propellant_match(db_prop, target)
  if ischar(db_prop)
    ok = strcmpi(db_prop, target);
  elseif iscell(db_prop)
    ok = any(strcmpi(db_prop, target));
  else
    ok = false;
  end
end

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
