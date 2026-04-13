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
%   The PPU must be rated for at least the design jet power (can throttle down in
%   underrating mode). Among candidates, lower mass is preferred (lighter PPU when
%   throttling); power margin and lineage-hint mass are secondary scoring factors.
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
      %   - sc_type == 1 (No Propulsion): evolver assigns a random type but it is irrelevant
      %   - missing or empty propulsion_system field
      %   - propulsion_system is 'No Propulsion' (legacy string check)
      %   - c_e or thrust is NaN (invalid / not yet computed)
      %   - thrust is zero (no propulsion needed)
      %   - no delta-v defined and thrust/c_e are both NaN
      no_prop_reason = '';
      if isfield(ind, 'sc_type') && isnumeric(ind.sc_type) && ind.sc_type == 1
        no_prop_reason = 'sc_type=1 No Propulsion';
      elseif ~isfield(ind, 'propulsion_system') || isempty(ind.propulsion_system)
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
          d_thrust, d_c_e, d_power, d_mass_budget, hint_thruster_mass, any(strcmpi(prop_sys, EP_TYPES)));

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
      cm.tank_candidates = select_tanks(db_data, propellant, d_prop_mass, hint_tank_mass, verbose);

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

      % ----------------------------------------------------------------
      % Mission-time thruster override:
      % If thrust_min is defined, walk the ranked candidate list and promote
      % the first one whose cluster thrust satisfies F_cluster >= thrust_min.
      % The full ranked list is preserved; selected_thruster_idx records which
      % candidate was actually chosen so piping and duration use the same one.
      % If no candidate satisfies the constraint, fall back to rank-1 and flag.
      % ----------------------------------------------------------------
      t_min_req = NaN;
      if isfield(evolution_data{end}(i,j), 'thrust_min')
        t_min_req = evolution_data{end}(i,j).thrust_min;
      end
      selected_thruster_idx = 1;
      if ~isempty(cm.thruster_candidates) && ~isnan(t_min_req) && t_min_req > 0
        for t_idx = 1:numel(cm.thruster_candidates)
          if cm.thruster_candidates(t_idx).thrust_cluster >= t_min_req
            selected_thruster_idx = t_idx;
            break;
          end
        end
        % If we had to promote beyond rank-1, update the mass used for piping.
        if selected_thruster_idx > 1
          m_sel_thruster = cm.thruster_candidates(selected_thruster_idx).mass_cluster;
          if verbose
            fprintf('  [PropSel] Case %d / Seed %d  thrust_min=%.4g N: promoted candidate %d (%.4g N) over rank-1 (%.4g N)\n', ...
                    i, j, t_min_req, selected_thruster_idx, ...
                    cm.thruster_candidates(selected_thruster_idx).thrust_cluster, ...
                    cm.thruster_candidates(1).thrust_cluster);
            fflush(stdout);
          end
        end
      end
      cm.selected_thruster_idx = selected_thruster_idx;

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
      % Recompute maneuver_duration using actual selected cluster thrust.
      % The design variable 'thrust' is continuous; the selected hardware
      % delivers thrust_cluster = n_thrusters * thrust_single, which may
      % differ.  c_e is an intensive property — unchanged by clustering.
      %   t_man = m_prop / (F_cluster / c_e)  = m_prop * c_e / F_cluster
      % This value is stored alongside the design-based maneuver_duration
      % so both are available in the output for comparison.
      % ----------------------------------------------------------------
      if ~isempty(cm.thruster_candidates) && ~isnan(d_prop_mass) && ~isnan(d_c_e)
        F_cluster = cm.thruster_candidates(selected_thruster_idx).thrust_cluster;
        if ~isnan(F_cluster) && F_cluster > 0
          t_man_actual = d_prop_mass * d_c_e / F_cluster;
          evolution_data{end}(i,j).mission_parameters.maneuver_duration_actual = t_man_actual;
          if ~isnan(t_min_req) && t_min_req > 0
            evolution_data{end}(i,j).mission_parameters.thrust_min_satisfied = double(F_cluster >= t_min_req);
          end
        end
      end

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
          if isfield(t, 'power_derived') && t.power_derived
            pwr_str = sprintf('each: thrust=%.4g N  power=%.4g W(%s)  mass=%.4g kg  |  cluster (n=%d): thrust=%.4g N  power=%.4g W(%s)  mass=%.4g kg', ...
                              t.thrust_single, t.power_jet_single, t.power_derive_method, t.mass_single, t.n_thrusters, t.thrust_cluster, t.power_jet_cluster, t.power_derive_method, t.mass_cluster);
          else
            pwr_str = sprintf('each: thrust=%.4g N  power=%.4g W  mass=%.4g kg  |  cluster (n=%d): thrust=%.4g N  power=%.4g W  mass=%.4g kg', ...
                              t.thrust_single, t.power_jet_single, t.mass_single, t.n_thrusters, t.thrust_cluster, t.power_jet_cluster, t.mass_cluster);
          end
          fprintf('      Thruster : %dx %s (%s)  %s  score=%.3f%s', ...
                  t.n_thrusters, t.name, t.company, pwr_str, t.score, hint_diff_t);
          if isfield(t, 'mass_exceeds_budget') && t.mass_exceeds_budget
            fprintf('  [FALLBACK: %.4g kg over]\n', t.mass_overage_kg);
          else
            fprintf('\n');
          end
          if numel(cm.thruster_candidates) > 1
            t2 = cm.thruster_candidates(2);
            if isfield(t2, 'power_derived') && t2.power_derived
              ru_pwr = sprintf('power=%.4g W(%s)', t2.power_jet_single, t2.power_derive_method);
            else
              ru_pwr = sprintf('power=%.4g W', t2.power_jet_single);
            end
            fprintf('               runner-up: %dx %s (%s)  each: thrust=%.4g N  %s  mass=%.4g kg  |  cluster (n=%d): thrust=%.4g N  mass=%.4g kg  score=%.3f', ...
                    t2.n_thrusters, t2.name, t2.company, t2.thrust_single, ru_pwr, t2.mass_single, t2.n_thrusters, t2.thrust_cluster, t2.mass_cluster, t2.score);
            if isfield(t2, 'mass_exceeds_budget') && t2.mass_exceeds_budget
              fprintf('  [FALLBACK: %.4g kg over]\n', t2.mass_overage_kg);
            else
              fprintf('\n');
            end
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
          fprintf('      ** FALLBACK: no thruster within mass budget; using best-scoring over-budget option\n');
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
function [cands, cands_ob] = select_thrusters(ps_db, propellant, d_thrust, d_c_e, d_power, d_mass_budget, hint_mass, is_ep)
  % hint_mass: scaling-model thruster cluster mass from last successful lineage (NaN = no hint).
  % is_ep: true for electric propulsion types — used to flag candidates where power_jet is absent
  %        even after derivation (power constraint silently skipped).
  if nargin < 7; hint_mass = NaN; end
  if nargin < 8; is_ep = false; end
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

    % If power_jet is absent from the DB, derive it via derive_jet_power().
    % That function tries (in order): 0.5*F*ve, F^2/(2*mdot), 0.5*mdot*ve^2.
    power_derived = false;
    power_derive_method = '';
    if isnan(e_power)
      e_mdot = scalar_midpoint(entry, 'mass_flow');
      [e_power, power_derive_method] = derive_jet_power(e_thrust, e_c_e, e_mdot);
      power_derived = ~isnan(e_power);
    end

    % Skip entries without a usable thrust value — cannot size a cluster without it.
    if isnan(e_thrust) || e_thrust <= 0; continue; end
    % Skip entries without a mass value — cluster mass would be NaN, making mass-budget
    % checks, hint scoring, and the over-budget fallback all meaningless.
    if isnan(e_mass);                    continue; end
    % Skip entries where jet power cannot be determined (not in DB and no derivation
    % succeeded) — the power-budget constraint is mandatory and cannot be skipped.
    if isnan(e_power);                   continue; end

    % Cluster sizing
    n = ceil(d_thrust / e_thrust);
    if n < 1; n = 1; end
    cluster_thrust = n * e_thrust;
    cluster_power  = n * e_power;
    cluster_mass   = n * e_mass;

    % Hard constraint: power (cluster jet power must not exceed design power budget).
    % e_power is guaranteed non-NaN here (candidates without power were skipped above).
    if ~isnan(d_power) && d_power > 0
      if cluster_power > d_power; continue; end
    end

    % Soft constraint: mass
    mass_exceeds_budget = false;
    mass_overage_kg = 0;
    if ~isnan(cluster_mass) && ~isnan(d_mass_budget) && d_mass_budget > 0
      if cluster_mass > d_mass_budget
        mass_exceeds_budget = true;
        mass_overage_kg = cluster_mass - d_mass_budget;
      end
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

    % Penalty for over-budget candidates: multiply score by 0.5 (strong disincentive).
    % Over-budget candidates only used as fallback; should always rank below in-budget.
    SCORE_PENALTY_OVER_BUDGET = 0.5; % TO THINK: is this too harsh? Too lenient? Should it be a function of how much the mass exceeds the budget?
    if mass_exceeds_budget
      total_score = total_score * SCORE_PENALTY_OVER_BUDGET;
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
    c.mass_overage_kg     = mass_overage_kg;  % overage above design budget [kg]
    c.power_derived       = double(power_derived); % 1 when Pjet was computed analytically (not in DB)
    c.power_derive_method = power_derive_method; % formula used, e.g. '0.5*F*ve'

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
    scores_ob = [cands_ob.score];
    masses_ob = [cands_ob.mass_cluster];
    masses_ob(isnan(masses_ob)) = Inf;
    [~, idx] = sortrows([-scores_ob(:), masses_ob(:)]);
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
function cands = select_tanks(db_data, propellant, d_prop_mass, hint_mass, verbose)
  % hint_mass: scaling-model tank cluster mass from last successful lineage (NaN = no hint).
  if nargin < 4; hint_mass = NaN; end
  if nargin < 5; verbose = false; end
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

  % Minimum MEOP [Pa] that qualifies a vessel as «high-pressure» — suitable for
  % storing compressed or supercritical gases (Xe, Kr, Ar, H2, He, …).
  % Value chosen to sit between the low-pressure propellant-tank cluster (~35 bar)
  % and the lowest high-pressure xenon/gas tank in the DB (~88 bar).
  HIGH_PRESSURE_THRESHOLD_Pa = 5e6;   % 50 bar

  % Three-pass propellant filtering
  spec_idx = tank_specific_indices(tank_data, propellant);
  if ~isempty(spec_idx)
    use_idx     = spec_idx;
    filter_mode = 'specific';
  else
    gen_idx = tank_generic_indices(tank_data);
    if ~isempty(gen_idx)
      % Generic (no propellant tag) vessels are the expected fallback for most propellants.
      use_idx     = gen_idx;
      filter_mode = 'generic';
    else
      % No specific or generic vessel found — apply propellant-class-aware fallback.
      if is_gas_propellant(propellant)
        % Gaseous propellants (He, Xe, Kr, Ar, H2, H2/N2 blends, …) must be stored
        % at high pressure; only vessels rated at or above HIGH_PRESSURE_THRESHOLD_Pa
        % are physically suitable.  Use those as a targeted fallback.
        hp_idx = tank_highpressure_indices(tank_data, HIGH_PRESSURE_THRESHOLD_Pa);
        if ~isempty(hp_idx)
          use_idx     = hp_idx;
          filter_mode = 'high_pressure';
          if verbose
            fprintf('    [TankSel] no compatible vessel for "%s"; using high-pressure DB entries (>= %.0f MPa MEOP) as fallback.\n', propellant, HIGH_PRESSURE_THRESHOLD_Pa / 1e6);
          end
        else
          % No high-pressure vessel in DB at all — last resort: all entries.
          use_idx     = 1:numel(tank_data);
          filter_mode = 'all';
          if verbose
            fprintf('    [TankSel] no compatible vessel for "%s"; no high-pressure vessels found either; using all DB entries as fallback.\n', propellant);
          end
        end
      else
        % Liquid and liquid-metal propellants (hydrazine, water, ammonia, indium,
        % bismuth, iodine, ionic liquids, etc.) exert only low ullage pressure in
        % the tank; any structurally rated pressure vessel can physically contain
        % them.  All DB entries are therefore acceptable candidates.
        % No warning is emitted because using all tanks is a valid and expected
        % path for propellants that have no dedicated vessel in the database.
        use_idx     = 1:numel(tank_data);
        filter_mode = 'all';
      end
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
% Selects from ps_db.ppu.  PPU must be rated for at least design jet power
% (can throttle down in underrating mode). Sorted by mass (lightest first),
% then by power margin and lineage-hint proximity as tiebreakers.
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

    % PPU capability constraint: must be rated for at least the design jet power
    % (can throttle down to d_power in underrating/throttling mode).
    if ~isnan(e_power) && ~isnan(d_power) && d_power > 0
      if e_power < d_power; continue; end
    end

    % Score: prioritise low mass (advantageous when throttling) and power margin
    % score_mass_inv: lower mass scores higher (inverse normalisation)
    score_mass_inv = 0;
    if ~isnan(e_mass)
      % Invert: 1 / (1 + mass) — lower mass gets higher score
      score_mass_inv = 1 / (1 + e_mass / 10);  % normalise by typical PPU mass ~10 kg
    end
    % score_power_margin: how much headroom above d_power (higher margin = lower score, so cap excess)
    score_power_margin = 0;
    if ~isnan(e_power) && ~isnan(d_power) && d_power > 0
      margin_factor = e_power / d_power;
      % Score penalises excess power: 1 / (1 + excess_ratio)
      % At margin_factor=1.0 (min capable), score = 1
      % At margin_factor=2.0 (2x capable), score = 0.5
      score_power_margin = 1 / (1 + (margin_factor - 1));
    end
    % Lineage-hint mass proximity: promotes PPUs whose mass matches the
    % scaling-model prediction; geometric mean with other scores.
    score_mass_hint = 0;
    if ~isnan(hint_mass) && hint_mass > 0 && ~isnan(e_mass)
      score_mass_hint = 1 / (1 + abs(e_mass - hint_mass) / hint_mass);
    end
    % Geometric mean of available scores
    score_factors = [];
    if score_mass_inv > 0;         score_factors(end+1) = score_mass_inv;     end
    if score_power_margin > 0;    score_factors(end+1) = score_power_margin; end
    if score_mass_hint > 0;        score_factors(end+1) = score_mass_hint;    end
    if ~isempty(score_factors)
      score = prod(score_factors)^(1/numel(score_factors));
    else
      score = 0;
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

% Returns indices of vessels whose MEOP is at or above threshold_Pa.
% Used as a fallback for gaseous propellants that require high-pressure storage.
function idx = tank_highpressure_indices(tank_data, threshold_Pa)
  idx = [];
  for k = 1:numel(tank_data)
    p = scalar_midpoint(tank_data{k}, 'pressure');
    if ~isnan(p) && p >= threshold_Pa
      idx(end+1) = k;
    end
  end
end

% Returns true when propellant is a compressed or supercritical gas that must
% be stored in a high-pressure vessel.  Liquids, liquid metals, solids, and
% low-pressure-liquefied gases are treated as non-gas for the purpose of tank
% fallback selection.
function tf = is_gas_propellant(propellant)
  prop_lc = lower(strtrim(propellant));
  gas_keywords = {'xe', 'xenon', 'kr', 'krypton', 'ar', 'argon', ...
                  'he', 'helium', ...
                  'hydrogen', 'h2', ...
                  'nitrogen', 'n2', ...
                  'oxygen', 'o2', ...
                  'h2/n2', 'nh3/n2h4 decomposition'};
  tf = false;
  for i = 1:numel(gas_keywords)
    if ~isempty(strfind(prop_lc, gas_keywords{i}))
      tf = true;
      return;
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
