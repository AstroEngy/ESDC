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
%   Per SMAD (3rd ed.): tank mass + feed system (piping, valves, lines) combined
%   account for 10–20 % of the total propulsion system wet mass
%   (wet mass = propellant + thruster cluster + tank cluster + PPU).
%   Piping mass is therefore computed AFTER hardware selection using the
%   top-ranked candidate masses, not reserved upfront from the dry budget.
%   PIPING_FRACTION = 0.20 (worst-case upper bound of the 10–20 % SMAD range).
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
%     .piping_fraction          PIPING_FRACTION constant used (dimensionless)
%     .piping_wet_mass          wet propulsion mass used as piping base [kg]
%     .piping_mass_kg           estimated piping + feed system mass [kg]
%     .hardware_mass_budget     = design_mass_budget (full dry budget; no upfront reservation)
%     .no_solution_within_mass_budget   0/1 flag
%     .thruster_candidates      struct array (best first)
%     .tank_candidates          struct array (best first)
%     .ppu_candidates           struct array (best first, empty if PPU not required)


%TODO 20% margin on propellant volume , generally Per SMAD (3rd ed.): tank + 
%TODO PPU scaling for clustering
%TODO: confidence calcing
%TODO: how to handle fallback when no candidate for propellant is available

function evolution_data = select_propulsion_components(evolution_data, db_data, verbose)
  % verbose (optional, default false): when true, prints per-individual
  % propulsion selection diagnostics showing the lineage hint (scaling model
  % starting point) and what was actually selected after DB cross-verification.
  if nargin < 3; verbose = false; end

  EP_TYPES = {'arcjet','gridionthruster','HET','FEEP','electrospray','ion'};

  % Use worst-case 0.20; applied post-hoc to (propellant + selected hardware masses).
  PIPING_FRACTION = 0.20;   % Per SMAD (3rd ed.): tank + feed system ≈ 10–20 % of total propulsion wet mass.

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'propulsion_system')
    return;
  end

  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);  % individual: one design solution from the best generation
      cm  = struct();                   % component matches

      % Skip individuals that require no propulsion component selection:
      %   - missing or empty propulsion_system field
      %   - propulsion_system is 'No Propulsion' (sc_type 1)
      %   - c_e or thrust is NaN (invalid / not yet computed)
      %   - thrust is zero (no propulsion needed)
      %   - no delta-v defined and thrust/c_e are both NaN
      no_prop_reason = '';
      if ~isfield(ind, 'propulsion_system') || isempty(ind.propulsion_system)
        no_prop_reason = 'propulsion_system field missing or empty';
      elseif strcmpi(strtrim(ind.propulsion_system), 'No Propulsion')
        no_prop_reason = 'sc_type No Propulsion';
      elseif ~isfield(ind, 'c_e') || ~isfield(ind, 'thrust') || ...
             isnan(ind.c_e) || isnan(ind.thrust)
        no_prop_reason = 'c_e or thrust is NaN';
      elseif ind.thrust == 0
        no_prop_reason = 'thrust is zero';
      end

      if ~isempty(no_prop_reason)
        cm.system_type = '';
        cm.skip_reason  = no_prop_reason;
        cm.thruster_candidates = struct([]);
        cm.tank_candidates     = struct([]);
        cm.ppu_candidates      = struct([]);
        evolution_data{end}(i,j).component_matches.propulsion_system = cm;
        if verbose
          fprintf('  [PropSel] Case %d / Seed %d  skipped: %s\n', i, j, no_prop_reason);
          fflush(stdout);
        end
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
      cm.piping_fraction      = PIPING_FRACTION;
      % Hardware competes for the full dry propulsion mass budget.
      % Piping is computed post-hoc after hardware selection (see section 4 below).
      cm.hardware_mass_budget = d_mass_budget;

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
          d_thrust, d_c_e, d_power, d_mass_budget, hint_thruster_mass);

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

      % ----------------------------------------------------------------
      % 4. PIPING / FEED SYSTEM MASS  (post-hoc from wet propulsion mass)
      % Per SMAD (3rd ed.): tank + feed system ≈ 10–20 % of wet propulsion mass.
      % m_wet = propellant + thruster cluster + tank cluster + PPU
      % m_piping = PIPING_FRACTION * m_wet
      % Computed from top-ranked candidates; NaN if any mass is unknown.
      % ----------------------------------------------------------------
      m_sel_thruster = NaN;
      if ~isempty(cm.thruster_candidates); m_sel_thruster = cm.thruster_candidates(1).mass_cluster; end
      m_sel_tank = NaN;
      if ~isempty(cm.tank_candidates);     m_sel_tank     = cm.tank_candidates(1).mass_cluster;    end
      m_sel_ppu = 0;  % zero for chemical propulsion where PPU is not required
      if ~isempty(cm.ppu_candidates);      m_sel_ppu      = cm.ppu_candidates(1).mass;              end

      m_wet_prop = NaN;
      m_piping   = NaN;
      if ~isnan(d_prop_mass) && ~isnan(m_sel_thruster) && ~isnan(m_sel_tank)
        m_wet_prop = d_prop_mass + m_sel_thruster + m_sel_tank + m_sel_ppu;
        m_piping   = PIPING_FRACTION * m_wet_prop;
      end
      cm.piping_wet_mass = m_wet_prop;  % wet propulsion mass [kg] used as base
      cm.piping_mass_kg  = m_piping;    % estimated piping + feed system mass [kg]

      evolution_data{end}(i,j).component_matches.propulsion_system = cm;

      % ----------------------------------------------------------------
      % VERBOSE DEBUG OUTPUT
      % ----------------------------------------------------------------
      if verbose
        fprintf('\n  [PropSel] Case %d / Seed %d  |  %s + %s\n', i, j, prop_sys, propellant);
        fprintf('    Design  : thrust=%.4g N  c_e=%.4g m/s  power=%.4g W  prop_mass=%.4g kg  budget=%.4g kg\n', ...
                d_thrust, d_c_e, d_power, d_prop_mass, d_mass_budget);

        % --- Lineage hint (scaling-model starting point) ---
        fprintf('    Hint (lineage scaling model):\n');
        if ~isnan(hint_thruster_mass)
          fprintf('      Thruster cluster mass : %.4g kg\n', hint_thruster_mass);
        else
          fprintf('      Thruster cluster mass : (no hint)\n');
        end
        if ~isnan(hint_tank_mass)
          fprintf('      Tank cluster mass     : %.4g kg\n', hint_tank_mass);
        else
          fprintf('      Tank cluster mass     : (no hint)\n');
        end
        if ~isnan(hint_ppu_mass)
          fprintf('      PPU mass              : %.4g kg\n', hint_ppu_mass);
        else
          fprintf('      PPU mass              : (no hint / not required)\n');
        end

        % --- Final selection (top-ranked after DB cross-verification) ---
        fprintf('    Selected (DB cross-verification):\n');
        if ~isempty(cm.thruster_candidates)
          t = cm.thruster_candidates(1);
          hint_diff_t = '';
          if ~isnan(hint_thruster_mass) && ~isnan(t.mass_cluster)
            pct = 100 * (t.mass_cluster - hint_thruster_mass) / hint_thruster_mass;
            if abs(pct) < 5
              hint_diff_t = '  [~hint]';
            else
              hint_diff_t = sprintf('  [%+.1f%% vs hint]', pct);
            end
          end
          fprintf('      Thruster : %dx %s (%s)  each: thrust=%.4g N  power=%.4g W  mass=%.4g kg  |  cluster (n=%d): thrust=%.4g N  power=%.4g W  mass=%.4g kg  score=%.3f%s\n', ...
                  t.n_thrusters, t.name, t.company, t.thrust_single, t.power_jet_single, t.mass_single, t.n_thrusters, t.thrust_cluster, t.power_jet_cluster, t.mass_cluster, t.score, hint_diff_t);
          if numel(cm.thruster_candidates) > 1
            t2 = cm.thruster_candidates(2);
            fprintf('               runner-up: %dx %s (%s)  each: thrust=%.4g N  mass=%.4g kg  |  cluster (n=%d): thrust=%.4g N  mass=%.4g kg  score=%.3f\n', ...
                    t2.n_thrusters, t2.name, t2.company, t2.thrust_single, t2.mass_single, t2.n_thrusters, t2.thrust_cluster, t2.mass_cluster, t2.score);
          end
        else
          fprintf('      Thruster : (none found)\n');
        end
        if ~isempty(cm.tank_candidates)
          tk = cm.tank_candidates(1);
          hint_diff_tk = '';
          if ~isnan(hint_tank_mass) && ~isnan(tk.mass_cluster)
            pct = 100 * (tk.mass_cluster - hint_tank_mass) / hint_tank_mass;
            if abs(pct) < 5
              hint_diff_tk = '  [~hint]';
            else
              hint_diff_tk = sprintf('  [%+.1f%% vs hint]', pct);
            end
          end
          n_tanks_str = '?';
          if ~isnan(tk.n_tanks); n_tanks_str = num2str(tk.n_tanks); end
          fprintf('      Tank     : %sx %s (%s)  each: cap=%.4g kg  mass=%.4g kg  |  cluster (n=%s): cap=%.4g kg  mass=%.4g kg  score=%.3f  [%s]%s\n', ...
                  n_tanks_str, tk.name, tk.company, tk.capacity_kg_single, tk.mass_single, n_tanks_str, tk.capacity_kg_cluster, tk.mass_cluster, tk.score, tk.filter_mode, hint_diff_tk);
        else
          fprintf('      Tank     : (none found)\n');
        end
        if ~isempty(cm.ppu_candidates)
          p = cm.ppu_candidates(1);
          hint_diff_p = '';
          if ~isnan(hint_ppu_mass) && ~isnan(p.mass)
            pct = 100 * (p.mass - hint_ppu_mass) / hint_ppu_mass;
            if abs(pct) < 5
              hint_diff_p = '  [~hint]';
            else
              hint_diff_p = sprintf('  [%+.1f%% vs hint]', pct);
            end
          end
          fprintf('      PPU      : %s (%s)  mass=%.4g kg  power=%.4g W  score=%.3f%s\n', ...
                  p.name, p.company, p.mass, p.power, p.score, hint_diff_p);
        elseif any(strcmpi(prop_sys, EP_TYPES))
          fprintf('      PPU      : (none found in DB)\n');
        end
        if isfield(cm, 'no_solution_within_mass_budget') && cm.no_solution_within_mass_budget
          fprintf('      ** NOTE: no thruster within mass budget — over-budget fallback used\n');
        end
        if ~isnan(cm.piping_mass_kg)
          fprintf('    Piping   : %.4g kg  (%.0f %% × wet mass %.4g kg)\n', ...
                  cm.piping_mass_kg, PIPING_FRACTION*100, cm.piping_wet_mass);
        else
          fprintf('    Piping   : (cannot compute — hardware mass unknown)\n');
        end
        fflush(stdout);
      end  % verbose

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

    % Extract representative scalar values from the DB entry.
    % scalar_midpoint returns the field value directly if it is a single number,
    % or (min+max)/2 if the DB stores a range struct {min, max}.  Returns NaN if
    % the field is absent or in an unrecognised format.
    e_thrust = scalar_midpoint(entry, 'thrust');    % single-thruster thrust [N]  — used to compute cluster count n = ceil(d_thrust / e_thrust)
    e_c_e    = scalar_midpoint(entry, 'c_e');       % effective exhaust velocity [m/s] — scored for proximity to design c_e
    e_power  = scalar_midpoint(entry, 'power_jet'); % jet power of one thruster [W]  — scaled by n to check cluster stays within power budget
    e_mass   = scalar_midpoint(entry, 'mass');      % dry mass of one thruster [kg]   — scaled by n for cluster mass; NaN entries are filtered out below
    e_TRL    = scalar_midpoint(entry, 'TRL');       % Technology Readiness Level       — stored on candidate struct for informational output only

    % Skip entries without a usable thrust value — cannot size a cluster without it.
    if isnan(e_thrust) || e_thrust <= 0; continue; end
    % Skip entries without a mass value — cluster mass would be NaN, making mass-budget
    % checks, hint scoring, and the over-budget fallback all meaningless.
    if isnan(e_mass);                    continue; end

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
% Selects from the top-level propulsion_system.tank.vessel list.
%
% Propellant-compatibility filtering (mirrors m_scale_tank logic):
%   1. Propellant-specific entries (propellant field matches) are tried first.
%   2. If none found, generic entries (no propellant field) are used as fallback.
%   3. If still none, all entries are used with a warning.
%
% Tank capacity [kg] is derived from the `mass_propellant` field when present;
% otherwise from `volume` [m³] × prop_density(propellant) [kg/m³].
% Note: volume values in the DB are stored in m³ (the unit attribute "L" is incorrect).
%
% Cluster sizing:  n_tanks = ceil(d_prop_mass / e_prop_cap)  (minimum 1).
% Sorted by score descending, then by cluster mass ascending as tiebreak.
% =========================================================================
function cands = select_tanks(db_data, propellant, d_prop_mass, hint_mass)
  % hint_mass: scaling-model tank cluster mass from last successful lineage (NaN = no hint).
  if nargin < 4; hint_mass = NaN; end
  cands = struct([]);

  ps_db = db_data.reference_data.propulsion_system;
  if ~isfield(ps_db, 'tank') || ~isfield(ps_db.tank, 'vessel')
    return;
  end
  tank_data = ps_db.tank.vessel;
  if ~iscell(tank_data); tank_data = {tank_data}; end

  % Propellant density for volume-based capacity derivation [kg/m³]
  rho_p = NaN;
  try
    rho_p = prop_density([], propellant);
  catch
  end

  % Two-pass propellant filtering
  spec_idx = tank_specific_indices(tank_data, propellant);
  if ~isempty(spec_idx)
    use_idx     = spec_idx;
    filter_mode = 'specific';
  else
    gen_idx = tank_generic_indices(tank_data);
    if ~isempty(gen_idx)
      if numel(spec_idx) == 0  % no specific entries found
        % no warning needed — generic fallback is the expected path for many propellants
      end
      use_idx     = gen_idx;
      filter_mode = 'generic';
    else
      use_idx     = 1:numel(tank_data);
      filter_mode = 'all';
      warning('select_tanks: no compatible vessel for "%s"; using all DB entries as fallback.', propellant);
    end
  end

  for k = use_idx
    entry = tank_data{k};

    e_mass     = scalar_midpoint(entry, 'mass');
    e_volume   = scalar_midpoint(entry, 'volume');   % m³ (DB unit tag "L" is incorrect)
    e_pressure = scalar_midpoint(entry, 'pressure');

    % Capacity: explicit mass_propellant field preferred; derive from volume otherwise
    e_prop_cap = scalar_midpoint(entry, 'mass_propellant');
    if isnan(e_prop_cap) && ~isnan(e_volume) && e_volume > 0 && ~isnan(rho_p) && rho_p > 0
      e_prop_cap = e_volume * rho_p;
    end

    % Cluster sizing: how many identical tanks are needed to hold d_prop_mass?
    n_tanks = 1;
    if ~isnan(e_prop_cap) && e_prop_cap > 0 && ~isnan(d_prop_mass) && d_prop_mass > 0
      n_tanks = ceil(d_prop_mass / e_prop_cap);
    elseif isnan(e_prop_cap) && ~isnan(d_prop_mass) && d_prop_mass > 0
      n_tanks = NaN;  % capacity unknown — keep entry but flag
    end

    cluster_mass = n_tanks * e_mass;
    cluster_cap  = n_tanks * e_prop_cap;

    % Score: capacity-fit proximity (excess penalised; perfect fit = 1)
    score = 0;
    if ~isnan(cluster_cap) && ~isnan(d_prop_mass) && d_prop_mass > 0
      score = 1 / (1 + (cluster_cap - d_prop_mass) / d_prop_mass);
    end
    % Lineage-hint mass proximity: geometric mean with capacity-fit score
    score_mass_hint = 0;
    if ~isnan(hint_mass) && hint_mass > 0 && ~isnan(cluster_mass)
      score_mass_hint = 1 / (1 + abs(cluster_mass - hint_mass) / hint_mass);
    end
    if score > 0 && score_mass_hint > 0
      score = sqrt(score * score_mass_hint);
    elseif score_mass_hint > 0
      score = score_mass_hint;
    end

    % Propellant field as a readable string
    if isfield(entry, 'propellant')
      if ischar(entry.propellant)
        prop_str = entry.propellant;
      elseif iscell(entry.propellant)
        prop_str = strjoin(entry.propellant, ', ');
      else
        prop_str = '';
      end
    else
      prop_str = '(generic)';
    end

    c.name                = get_str_field(entry, 'name', '(unnamed)');
    c.company             = get_str_field(entry, 'company', '');
    c.type                = get_str_field(entry, 'type', 'tank');
    c.filter_mode         = filter_mode;
    c.score               = score;
    c.n_tanks             = n_tanks;
    c.mass_single         = e_mass;
    c.mass_cluster        = cluster_mass;
    c.capacity_kg_single  = e_prop_cap;
    c.capacity_kg_cluster = cluster_cap;
    c.volume_m3           = e_volume;
    c.pressure_Pa         = e_pressure;
    c.propellant          = prop_str;
    c.source              = get_str_field(entry, 'source', '');

    if isempty(cands); cands = c; else; cands(end+1) = c; end
  end

  if ~isempty(cands)
    scores = [cands.score];
    masses = [cands.mass_cluster];
    masses(isnan(masses)) = Inf;
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

% Returns indices of vessels whose propellant field explicitly matches the target.
function idx = tank_specific_indices(tank_data, propellant)
  idx = [];
  for k = 1:numel(tank_data)
    entry = tank_data{k};
    if isfield(entry, 'propellant') && ~isempty(entry.propellant)
      if propellant_match(entry.propellant, propellant)
        idx(end+1) = k;
      end
    end
  end
end

% Returns indices of vessels with no propellant field (generic vessels).
function idx = tank_generic_indices(tank_data)
  idx = [];
  for k = 1:numel(tank_data)
    entry = tank_data{k};
    if ~isfield(entry, 'propellant') || isempty(entry.propellant)
      idx(end+1) = k;
    end
  end
end

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
