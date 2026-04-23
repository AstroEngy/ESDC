% select_power_generation_components — Match PV and battery hardware for each design individual.
%
% For each individual in evolution_data{end}, searches the power_generation
% section of the reference database and selects:
%   1. Solar array (photovoltaic module cluster) — must deliver >= required PV output power
%   2. Battery pack cluster                      — must hold >= required shadow-phase energy;
%                                                  lifecycle scored against orbital cycle rate
%
% PV selection rules:
%   - Required PV output power from ind.system.power.PV.PV_power_output_required [W]
%     (already accounts for system losses, margin, and battery charging duty).
%   - Minimum cluster count n = ceil(d_pv_power / e_power_max) — minimum panels to meet demand.
%   - Cluster power must be >= d_pv_power; mass soft-constrained by total power budget.
%   - Score: power-fit proximity (excess penalised).
%
% Battery selection rules:
%   - Required energy from ind.system.power.battery.E_battery_required_max [Wh]
%     (worst-case energy to cover full shadow phase at maximum power draw).
%   - Minimum cluster count n = ceil(d_energy_wh / e_energy_wh) — packs in parallel.
%   - Lifecycle scored: expected_life_yr = cycle_life / n_cycles_per_year;
%     batteries expected to survive >= 5 years score 1; shorter lifetimes score lower.
%   - Mass soft-constrained by total power budget.
%
% Cluster scaling:
%   PV:      power, mass, area all scale linearly with n.
%   Battery: energy, capacity, mass all scale linearly with n (parallel packs).
%
% Harness:
%   Per SMAD (3rd ed.): power harness = 10–25 % of total PPS hardware mass
%   (PV cluster + battery cluster).  HARNESS_FRACTION = 0.10 (lower bound;
%   harness is more predictable than propulsion piping).
%
% Results are appended to:
%   individual.component_matches.power_generation
%     .design_pv_power_required    [W]   required PV output power (with margin and losses)
%     .design_battery_energy_wh    [Wh]  required battery energy (worst-case shadow phase)
%     .design_mass_budget          [kg]  total power subsystem dry mass budget
%     .design_n_cycles_per_year    [cyc/yr] orbital charge/discharge cycles per year
%     .harness_fraction            HARNESS_FRACTION constant used
%     .harness_hardware_mass       PV + battery cluster mass used as harness base [kg]
%     .harness_mass_kg             estimated harness mass [kg]
%     .no_pv_within_budget         0/1 flag
%     .no_battery_within_budget    0/1 flag
%     .pv_candidates               struct array (best first)
%     .battery_candidates          struct array (best first)

function evolution_data = select_power_generation_components(evolution_data, db_data, verbose)
  % verbose (optional, default false): when true, prints per-individual
  % power generation selection diagnostics.
  if nargin < 3; verbose = false; end

  % Per SMAD (3rd ed.): harness + cabling = 10-25 % of total PPS hardware mass.
  % Use upper bound (25 %) for worst case assumption % akternative source could account for 5% of nominal dry mass here (ESA Margin philosophy for science assessment studies)
  HARNESS_FRACTION = 0.25;

  if ~isfield(db_data, 'reference_data') || ...
     ~isfield(db_data.reference_data, 'power_generation')
    return;
  end

  power_db = db_data.reference_data.power_generation;
  n_cases = size(evolution_data{end}, 1);
  n_seeds  = size(evolution_data{end}, 2);

  for i = 1:n_cases
    for j = 1:n_seeds

      ind = evolution_data{end}(i, j);
      cm  = struct();

      % ---- Resolve design targets from power system analysis results ----
      d_pv_power    = NaN;   % required PV output power [W]
      d_energy_wh   = NaN;   % required battery shadow-phase energy [Wh]
      d_n_cycles_yr = NaN;   % orbital cycles per year [cyc/yr]

      if isfield(ind, 'system') && isfield(ind.system, 'power')
        pss = ind.system.power;
        if isfield(pss, 'PV') && isfield(pss.PV, 'PV_power_output_required')
          d_pv_power = pss.PV.PV_power_output_required;
        end
        if isfield(pss, 'battery')
          if isfield(pss.battery, 'E_battery_required_max')
            d_energy_wh = pss.battery.E_battery_required_max / 3600;  % J → Wh (field is stored in J)
          end
          if isfield(pss.battery, 'n_cycles_per_year')
            d_n_cycles_yr = pss.battery.n_cycles_per_year;
          end
        end
      end

      % Fallback for PV power if detailed analysis not available
      if isnan(d_pv_power) && isfield(ind, 'subsystem_powers') && ...
         isfield(ind.subsystem_powers, 'power_total')
        d_pv_power = ind.subsystem_powers.power_total;
      end
      if isnan(d_pv_power) && isfield(ind, 'power_propulsion')
        d_pv_power = ind.power_propulsion;
      end
      % Fallback for battery energy if PSS struct not yet populated
      if isnan(d_energy_wh) && isfield(ind, 'battery') && isstruct(ind.battery) && ...
         isfield(ind.battery, 'E_battery_required_max')
        d_energy_wh = ind.battery.E_battery_required_max / 3600;  % J → Wh
      end

      % Total power subsystem mass budget
      d_mass_budget = NaN;
      if isfield(ind, 'subsystem_masses') && isfield(ind.subsystem_masses, 'mass_power')
        d_mass_budget = ind.subsystem_masses.mass_power;
      end

      cm.design_pv_power_required = d_pv_power;
      cm.design_battery_energy_wh = d_energy_wh;
      cm.design_mass_budget       = d_mass_budget;
      cm.design_n_cycles_per_year = d_n_cycles_yr;
      cm.harness_fraction         = HARNESS_FRACTION;

      % ----------------------------------------------------------------
      % 1. PV SOLAR ARRAY SELECTION
      % ----------------------------------------------------------------
      [pv_cands, pv_cands_ob] = select_pv(power_db, d_pv_power, d_mass_budget);

      if ~isempty(pv_cands)
        cm.no_pv_within_budget = 0;
        cm.pv_candidates = pv_cands;
      elseif ~isempty(pv_cands_ob)
        cm.no_pv_within_budget = 1;
        cm.pv_candidates = pv_cands_ob;
      else
        cm.no_pv_within_budget = 1;
        cm.pv_candidates = struct([]);
      end

      % ----------------------------------------------------------------
      % 2. BATTERY SELECTION
      % ----------------------------------------------------------------
      [batt_cands, batt_cands_ob] = select_batteries(db_data.reference_data, d_energy_wh, d_n_cycles_yr, d_mass_budget);

      if ~isempty(batt_cands)
        cm.no_battery_within_budget = 0;
        cm.battery_candidates = batt_cands;
      elseif ~isempty(batt_cands_ob)
        cm.no_battery_within_budget = 1;
        cm.battery_candidates = batt_cands_ob;
      else
        cm.no_battery_within_budget = 1;
        cm.battery_candidates = struct([]);
      end

      % ----------------------------------------------------------------
      % 3. HARNESS MASS  (post-hoc from selected hardware masses)
      % Per SMAD (3rd ed.): harness + cabling = 10-25 % of PPS hardware mass.
      % m_hardware = PV cluster mass + battery cluster mass
      % m_harness  = HARNESS_FRACTION * m_hardware
      % Computed from top-ranked candidates; NaN if any mass is unknown.
      % ----------------------------------------------------------------
      m_sel_pv   = NaN;
      m_sel_batt = NaN;
      if ~isempty(cm.pv_candidates);      m_sel_pv   = cm.pv_candidates(1).mass_cluster;      end
      if ~isempty(cm.battery_candidates); m_sel_batt = cm.battery_candidates(1).mass_cluster; end

      m_hardware = NaN;
      m_harness  = NaN;
      if ~isnan(m_sel_pv) && ~isnan(m_sel_batt)
        m_hardware = m_sel_pv + m_sel_batt;
        m_harness  = HARNESS_FRACTION * m_hardware;
      end
      cm.harness_hardware_mass = m_hardware;  % PV + battery hardware mass [kg]
      cm.harness_mass_kg       = m_harness;   % estimated harness mass [kg]

      evolution_data{end}(i,j).component_matches.power_generation = cm;

      % ----------------------------------------------------------------
      % VERBOSE DEBUG OUTPUT
      % ----------------------------------------------------------------
      if verbose
        fprintf('\n  [PwrSel] Case %d / Seed %d\n', i, j);
        fprintf('    Design  : pv_power=%.4g W  batt_energy=%.4g Wh  budget=%.4g kg  cycles_yr=%.4g /yr\n', ...
                d_pv_power, d_energy_wh, d_mass_budget, d_n_cycles_yr);

        % --- Solar array ---
        fprintf('    Solar array:\n');
        if ~isempty(cm.pv_candidates)
          pv          = cm.pv_candidates(1);
          eff_str     = '';
          area_str    = '';
          area_cl_str = '';
          if ~isnan(pv.efficiency);      eff_str     = sprintf('  eff=%.1f%%',   pv.efficiency * 100); end
          if ~isnan(pv.area_single_m2);  area_str    = sprintf('  area=%.4g m2', pv.area_single_m2);   end
          if ~isnan(pv.area_cluster_m2); area_cl_str = sprintf('  area=%.4g m2', pv.area_cluster_m2);  end
          budget_str = '';
          if pv.mass_exceeds_budget
            budget_str = sprintf('  ** OVER BUDGET by %.4g kg', pv.mass_overage_kg);
          end
          fprintf('      #1  : %s (%s)  [%s]\n', pv.name, pv.manufacturer, pv.filter_mode);
          fprintf('            each   : power=%.4g W  mass=%.4g kg%s%s\n', ...
                  pv.power_max_single, pv.mass_single, area_str, eff_str);
          fprintf('            cluster: n=%d  power=%.4g W  mass=%.4g kg%s', ...
                  pv.n_panels, pv.power_max_cluster, pv.mass_cluster, area_cl_str);
          if pv.n_panels > 1 && pv.mass_structural_kg > 0
            fprintf('  (modules=%.4g kg + struct=%.4g kg)', pv.mass_modules_kg, pv.mass_structural_kg);
          end
          fprintf('\n');
          fprintf('            score  : %.3f  (power_fit=%.3f)%s\n', ...
                  pv.score, pv.score_power_fit, budget_str);
          if numel(cm.pv_candidates) > 1
            pv2   = cm.pv_candidates(2);
            bstr2 = '';
            if pv2.mass_exceeds_budget; bstr2 = ' [OVER BUDGET]'; end
            fprintf('      r/up: %s (%s)  n=%d  power=%.4g W  mass=%.4g kg  score=%.3f%s\n', ...
                    pv2.name, pv2.manufacturer, pv2.n_panels, ...
                    pv2.power_max_cluster, pv2.mass_cluster, pv2.score, bstr2);
          end
          if cm.no_pv_within_budget
            fprintf('      ** FALLBACK: no solar array within mass budget; using best over-budget option\n');
          end
        else
          fprintf('      (none found)\n');
        end

        % --- Battery ---
        fprintf('    Battery:\n');
        if ~isempty(cm.battery_candidates)
          bt         = cm.battery_candidates(1);
          spec_e_str = '';
          if ~isnan(bt.specific_energy); spec_e_str = sprintf('  spec_e=%.4g Wh/kg', bt.specific_energy); end
          cl_str   = '?';
          life_str = '?';
          if ~isnan(bt.cycle_life);       cl_str   = num2str(bt.cycle_life, '%g');            end
          if ~isnan(bt.expected_life_yr); life_str = sprintf('%.1f yr', bt.expected_life_yr); end
          score_detail = '';
          if bt.score_energy_fit > 0 && bt.score_life_fit > 0
            score_detail = sprintf('  (energy_fit=%.3f  life=%.3f)', bt.score_energy_fit, bt.score_life_fit);
          elseif bt.score_energy_fit > 0
            score_detail = sprintf('  (energy_fit=%.3f)', bt.score_energy_fit);
          end
          budget_str = '';
          if bt.mass_exceeds_budget
            budget_str = sprintf('  ** OVER BUDGET by %.4g kg', bt.mass_overage_kg);
          end
          fprintf('      #1  : %s (%s)  [%s]\n', bt.name, bt.manufacturer, bt.filter_mode);
          fprintf('            each   : energy=%.4g Wh  mass=%.4g kg%s  cycle_life=%s\n', ...
                  bt.energy_wh_single, bt.mass_single, spec_e_str, cl_str);
          fprintf('            cluster: n=%d  energy=%.4g Wh  mass=%.4g kg  expected life=%s\n', ...
                  bt.n_batteries, bt.energy_wh_cluster, bt.mass_cluster, life_str);
          fprintf('            score  : %.3f%s%s\n', bt.score, score_detail, budget_str);
          if numel(cm.battery_candidates) > 1
            bt2      = cm.battery_candidates(2);
            bstr2    = '';
            life2_str = '';
            if bt2.mass_exceeds_budget;      bstr2     = ' [OVER BUDGET]';                                end
            if ~isnan(bt2.expected_life_yr); life2_str = sprintf('  life=%.1f yr', bt2.expected_life_yr); end
            fprintf('      r/up: %s (%s)  n=%d  energy=%.4g Wh  mass=%.4g kg  score=%.3f%s%s\n', ...
                    bt2.name, bt2.manufacturer, bt2.n_batteries, ...
                    bt2.energy_wh_cluster, bt2.mass_cluster, bt2.score, life2_str, bstr2);
          end
          if cm.no_battery_within_budget
            fprintf('      ** FALLBACK: no battery cluster within mass budget; using best over-budget option\n');
          end
        else
          fprintf('      (none found)\n');
        end

        % Harness
        if ~isnan(cm.harness_mass_kg)
          fprintf('    Harness : %.4g kg  (%.0f%% x hardware mass %.4g kg)\n', ...
                  cm.harness_mass_kg, HARNESS_FRACTION * 100, m_hardware);
        else
          fprintf('    Harness : (cannot compute - hardware mass unknown)\n');
        end

        fflush(stdout);
      end  % verbose

    end  % seed loop
  end  % case loop

end


% =========================================================================
% PV (SOLAR ARRAY) SELECTION
% Returns [within_budget_cands, over_budget_cands] sorted by ascending mass.
%
% Design goal: fewest panels that deliver >= (d_pv_power * POWER_MARGIN) AND
%   fit within the mass budget.
%
% Cluster sizing: n = ceil(d_pv_power * POWER_MARGIN / e_power_max) — the
%   minimum panel count guaranteed to cover the margined power demand.
%   POWER_MARGIN = 1.20 accounts for pointing, temperature, radiation and
%   other loss effects [Raja Reddy 2003, combined LEO loss factor ~0.80].
%
% Structural substrate penalty of 1.3 kg/m² applied per-cell area
%   [Raja Reddy 2003, Table 9 — rigid planar array, worst case].
%
% Scoring: fraction of mass budget remaining (1 = uses no budget, 0 = uses
%   all budget).  Lighter clusters rank first.  Mass budget is a hard
%   constraint — over-budget candidates are kept only as a last-resort
%   fallback and returned in cands_ob.
% =========================================================================
function [cands, cands_ob] = select_pv(power_db, d_pv_power, d_mass_budget)
  cands    = struct([]);
  cands_ob = struct([]);

  if ~isfield(power_db, 'photovoltaic') || ~isfield(power_db.photovoltaic, 'cell')
    return;
  end
  pv_data = power_db.photovoltaic.cell;
  if ~iscell(pv_data); pv_data = {pv_data}; end

  SCORE_PENALTY_OVER_BUDGET = 0.5;  % applied to over-budget fallback candidates only

  % 20 % power margin to account for array pointing losses, temperature
  % degradation, radiation degradation, and other in-orbit loss effects.
  % [Raja Reddy 2003]: combined loss factor for LEO planar arrays ≈ 0.80 (Table 5).
  % A 20 % upsize (factor 1.20) conservatively covers the main loss mechanisms.
  % Source: Raja Reddy, M., "Space solar cells—tradeoff analysis," Solar Energy
  %   Materials and Solar Cells, Vol. 77, No. 2, 2003, pp. 175–208,
  %   doi:10.1016/S0927-0248(02)00320-3.
  POWER_MARGIN = 1.20;  % scale required power demand before sizing

  % Structural mass penalty applied per cell (each cell has its own
  % substrate/mounting structure regardless of cluster size).
  % Source: Raja Reddy, M., "Space solar cells—tradeoff analysis,"
  %   Solar Energy Materials and Solar Cells, Vol. 77, No. 2, 2003, pp. 175–208,
  %   doi:10.1016/S0927-0248(02)00320-3.  Table 9 — rigid planar array solar panel
  %   substrate areal mass density = 1.3 kg/m² (worst-case; flexible arrays range
  %   0.35–0.65 kg/m²).  Rigid value used as conservative upper bound.
  % TO REFINE: Apply differing masses for rigid vs. flexible arrays when that data is available.
  ARRAY_SUBSTRATE_KG_PER_M2 = 1.3;  % [kg/m²] rigid planar array substrate (worst case)

  for k = 1:numel(pv_data)
    entry = pv_data{k};
    if ~isstruct(entry); continue; end

    % Max rated output power per module; DB stores as 'power: {max: X}'
    e_power = scalar_field_max(entry, 'power');   % [W]
    e_mass  = scalar_midpoint(entry, 'mass');     % [kg]
    e_area  = scalar_midpoint(entry, 'area');     % [m²] — informational
    e_eff   = scalar_midpoint(entry, 'efficiency');

    % Skip entries without power or mass — cannot size cluster
    if isnan(e_power) || e_power <= 0; continue; end
    if isnan(e_mass);                  continue; end

    % Cluster sizing: minimum panel count to meet margined PV output power demand.
    % POWER_MARGIN = 1.20 accounts for pointing, temperature, and radiation losses.
    n = 1;
    if ~isnan(d_pv_power) && d_pv_power > 0
      n = ceil(d_pv_power * POWER_MARGIN / e_power);
      if n < 1; n = 1; end
    end

    cluster_power = n * e_power;
    cluster_mass  = n * e_mass;
    cluster_area  = n * e_area;   % NaN if e_area unknown — informational only

    % Structural substrate penalty applied per cell (each cell requires its own
    % panel substrate/mounting structure).
    % Raja Reddy (2003), Table 9: rigid planar array substrate = 1.3 kg/m² per cell area.
    m_structural = 0;
    if ~isnan(cluster_area)
      m_structural = ARRAY_SUBSTRATE_KG_PER_M2 * cluster_area;
    end
    cluster_mass_total = cluster_mass + m_structural;  % modules + per-cell structure

    % Soft mass constraint
    mass_exceeds_budget = false;
    mass_overage_kg = 0;
    if ~isnan(cluster_mass_total) && ~isnan(d_mass_budget) && d_mass_budget > 0
      if cluster_mass_total > d_mass_budget
        mass_exceeds_budget = true;
        mass_overage_kg = cluster_mass_total - d_mass_budget;
      end
    end

    % Score: fraction of mass budget remaining after placing this cluster.
    % Higher score = lighter cluster = fewer / smaller panels = preferred.
    % Candidates that exceed the mass budget receive a penalty and go into
    % cands_ob (fallback only); the score there is still mass-based so the
    % lightest over-budget option ranks first.
    score_power_fit = 0;   % kept for informational output only
    if ~isnan(cluster_power) && ~isnan(d_pv_power) && d_pv_power > 0
      score_power_fit = 1 / (1 + (cluster_power - d_pv_power * POWER_MARGIN) / (d_pv_power * POWER_MARGIN));
    end
    score = 0;
    if ~isnan(cluster_mass_total) && ~isnan(d_mass_budget) && d_mass_budget > 0
      score = max(0, 1 - cluster_mass_total / d_mass_budget);  % fraction of budget remaining
    elseif ~isnan(cluster_mass_total) && cluster_mass_total > 0
      score = 1 / (1 + cluster_mass_total);  % fallback when budget unknown
    end
    if mass_exceeds_budget
      score = score * SCORE_PENALTY_OVER_BUDGET;
    end

    c.name              = get_str_field(entry, 'name', '(unnamed)');
    c.manufacturer      = get_str_field(entry, 'company', get_str_field(entry, 'manufacturer', ''));
    c.filter_mode       = 'all';
    c.score             = score;
    c.score_power_fit   = score_power_fit;  % power-fit sub-score before mass penalty
    c.n_panels          = n;
    c.power_max_single  = e_power;
    c.power_max_cluster = cluster_power;
    c.mass_single       = e_mass;
    c.mass_cluster      = cluster_mass_total;   % modules + structural substrate
    c.mass_modules_kg   = cluster_mass;         % panel modules only (n * mass_single)
    c.mass_structural_kg = m_structural;        % array substrate penalty [Raja Reddy 2003, Table 9]
    c.area_single_m2    = e_area;
    c.area_cluster_m2   = cluster_area;
    c.efficiency        = e_eff;
    c.mass_exceeds_budget = double(mass_exceeds_budget);
    c.mass_overage_kg   = mass_overage_kg;
    c.source            = get_str_field(entry, 'source', '');

    if mass_exceeds_budget
      if isempty(cands_ob); cands_ob = c; else; cands_ob(end+1) = c; end
    else
      if isempty(cands);    cands = c;    else; cands(end+1) = c;    end
    end
  end

  % Sort within-budget: score descending (= lightest first), mass ascending as tiebreak.
  % Over-budget: same order so lightest over-budget option is first fallback.
  if ~isempty(cands)
    scores = [cands.score];
    masses = [cands.mass_cluster]; masses(isnan(masses)) = Inf;
    [~, idx] = sortrows([-scores(:), masses(:)]);
    cands = cands(idx);
  end
  if ~isempty(cands_ob)
    scores_ob = [cands_ob.score];
    masses_ob = [cands_ob.mass_cluster]; masses_ob(isnan(masses_ob)) = Inf;
    [~, idx] = sortrows([-scores_ob(:), masses_ob(:)]);
    cands_ob = cands_ob(idx);
  end
end


% =========================================================================
% BATTERY SELECTION
% Returns [within_budget_cands, over_budget_cands] sorted by score / mass.
%
% Design goal: lightest battery cluster that provides >= (d_energy_wh * CAPACITY_MARGIN)
%   AND fits within the mass budget.  CAPACITY_MARGIN = 1.30 (30%) per NASA/TM-2009-215751 https://ntrs.nasa.gov/api/citations/20090023862/downloads/20090023862.pdf
%   guidelines for lithium-ion batteries in space.
%
% Cluster sizing: n = ceil(d_energy_wh * CAPACITY_MARGIN / e_energy_wh) — parallel packs
%   such that cluster provides at least 30% headroom above shadow-phase energy demand.
%
% Score: mass-based (fraction of budget remaining). Lifecycle factors ensure batteries
%   survive the mission. Higher score = lighter cluster = fewer packs wins.
%   Expected life = cycle_life / n_cycles_per_year; must support >= 5 year reference mission.
% =========================================================================
function [cands, cands_ob] = select_batteries(ref_db, d_energy_wh, d_n_cycles_yr, d_mass_budget)
  cands    = struct([]);
  cands_ob = struct([]);

  % Batteries are stored under energy_storage.Batteries.battery
  % (energy_storage is a sibling of power_generation, not a child).
  batt_data = [];
  if isfield(ref_db, 'energy_storage') && isfield(ref_db.energy_storage, 'Batteries') && ...
     isfield(ref_db.energy_storage.Batteries, 'battery')
    batt_data = ref_db.energy_storage.Batteries.battery;
  elseif isfield(ref_db, 'energy_storage') && isfield(ref_db.energy_storage, 'battery')
    batt_data = ref_db.energy_storage.battery;
  elseif isfield(ref_db, 'power_generation') && isfield(ref_db.power_generation, 'Batteries') && ...
     isfield(ref_db.power_generation.Batteries, 'battery')
    batt_data = ref_db.power_generation.Batteries.battery;  % legacy fallback
  end
  if isempty(batt_data); return; end
  if ~iscell(batt_data); batt_data = {batt_data}; end

  SCORE_PENALTY_OVER_BUDGET = 0.5;
  LIFECYCLE_REFERENCE_YEARS = 5.0;   % reference mission life for lifecycle score normalisation

  % 30 % capacity margin for lithium-ion battery safety and cell degradation.
  % Source: McKissock, B., Loyselle, P., and Vogel, E., "Guidelines on Lithium-ion
  %   Battery Use in Space Applications," NASA/TM-2009-215751, NESC-RP-08-75/06-069-I,
  %   Glenn Research Center, Cleveland, Ohio.
  % Rationale: compensates for voltage sag, temperature effects, cycle counting margins,
  %   and end-of-life degradation to ensure spacecraft power availability throughout mission.
  CAPACITY_MARGIN = 1.30;  % [dimensionless] scale required battery energy before sizing

  for k = 1:numel(batt_data)
    entry = batt_data{k};
    if ~isstruct(entry); continue; end

    % Energy: prefer explicit 'energy' [Wh]; derive from capacity [Ah] x voltage [V] if absent
    e_energy_wh = scalar_midpoint(entry, 'energy');
    if isnan(e_energy_wh)
      e_cap_ah = scalar_midpoint(entry, 'capacity');
      e_v_nom  = scalar_midpoint(entry, 'voltage_nominal');
      if isnan(e_v_nom) && isfield(entry, 'voltage_range') && isstruct(entry.voltage_range) && ...
         isfield(entry.voltage_range, 'min') && isfield(entry.voltage_range, 'max')
        e_v_nom = (entry.voltage_range.min + entry.voltage_range.max) / 2;
      end
      if ~isnan(e_cap_ah) && ~isnan(e_v_nom)
        e_energy_wh = e_cap_ah * e_v_nom;
      end
    end

    e_mass     = scalar_midpoint(entry, 'mass');           % [kg]
    e_specific = scalar_midpoint(entry, 'specific_energy'); % [Wh/kg] — informational
    e_cycle_life = parse_cycle_life(entry);                % total cycle life [cycles]

    % Skip if energy or mass unknown — cannot size cluster
    if isnan(e_energy_wh) || e_energy_wh <= 0; continue; end
    if isnan(e_mass);                           continue; end

    % Cluster sizing: parallel packs to meet margined shadow-phase energy demand.
    % CAPACITY_MARGIN = 1.30 (30%) per NASA/TM-2009-215751 guidelines.
    n = 1;
    if ~isnan(d_energy_wh) && d_energy_wh > 0
      n = ceil(d_energy_wh * CAPACITY_MARGIN / e_energy_wh);
      if n < 1; n = 1; end
    end

    cluster_energy = n * e_energy_wh;
    cluster_mass   = n * e_mass;

    % Soft mass constraint
    mass_exceeds_budget = false;
    mass_overage_kg = 0;
    if ~isnan(cluster_mass) && ~isnan(d_mass_budget) && d_mass_budget > 0
      if cluster_mass > d_mass_budget
        mass_exceeds_budget = true;
        mass_overage_kg = cluster_mass - d_mass_budget;
      end
    end

    % Score 1: energy-fit proximity against margined demand (excess penalised; perfect fit = 1)
    score_energy = 0;
    if ~isnan(cluster_energy) && ~isnan(d_energy_wh) && d_energy_wh > 0
      score_energy = 1 / (1 + (cluster_energy - d_energy_wh * CAPACITY_MARGIN) / (d_energy_wh * CAPACITY_MARGIN));
    end

    % Score 2: lifecycle compatibility
    % expected_life_yr = cycle_life / n_cycles_per_year
    % score_life = min(1, expected_life_yr / LIFECYCLE_REFERENCE_YEARS)
    % A battery that outlasts the reference mission scores 1; proportionally lower otherwise.
    score_life = 0;
    expected_life_yr = NaN;
    if ~isnan(e_cycle_life) && ~isnan(d_n_cycles_yr) && d_n_cycles_yr > 0
      expected_life_yr = e_cycle_life / d_n_cycles_yr;
      score_life = min(1.0, expected_life_yr / LIFECYCLE_REFERENCE_YEARS);
    end

    % Geometric mean of available score components
    score_factors = [];
    if score_energy > 0; score_factors(end+1) = score_energy; end
    if score_life   > 0; score_factors(end+1) = score_life;   end
    if ~isempty(score_factors)
      score = prod(score_factors)^(1/numel(score_factors));
    else
      score = 0;
    end

    if mass_exceeds_budget
      score = score * SCORE_PENALTY_OVER_BUDGET;
    end

    c.name              = get_str_field(entry, 'name', '(unnamed)');
    c.manufacturer      = get_str_field(entry, 'manufacturer', '');
    c.filter_mode       = 'all';
    c.score             = score;
    c.score_energy_fit  = score_energy;  % energy-fit sub-score before mass penalty
    c.score_life_fit    = score_life;    % lifecycle sub-score before mass penalty
    c.n_batteries       = n;
    c.energy_wh_single  = e_energy_wh;
    c.energy_wh_cluster = cluster_energy;
    c.mass_single       = e_mass;
    c.mass_cluster      = cluster_mass;
    c.specific_energy   = e_specific;    % [Wh/kg] — informational
    c.cycle_life        = e_cycle_life;  % total rated cycles
    c.expected_life_yr  = expected_life_yr; % derived: cycle_life / n_cycles_per_year
    c.mass_exceeds_budget = double(mass_exceeds_budget);
    c.mass_overage_kg   = mass_overage_kg;
    c.source            = get_str_field(entry, 'source', '');

    if mass_exceeds_budget
      if isempty(cands_ob); cands_ob = c; else; cands_ob(end+1) = c; end
    else
      if isempty(cands);    cands = c;    else; cands(end+1) = c;    end
    end
  end

  % Sort: score descending, cluster mass ascending as tiebreak
  if ~isempty(cands)
    scores = [cands.score];
    masses = [cands.mass_cluster]; masses(isnan(masses)) = Inf;
    [~, idx] = sortrows([-scores(:), masses(:)]);
    cands = cands(idx);
  end
  if ~isempty(cands_ob)
    scores_ob = [cands_ob.score];
    masses_ob = [cands_ob.mass_cluster]; masses_ob(isnan(masses_ob)) = Inf;
    [~, idx] = sortrows([-scores_ob(:), masses_ob(:)]);
    cands_ob = cands_ob(idx);
  end
end


% =========================================================================
% HELPERS
% =========================================================================

% Returns the maximum value of a DB field.  Handles:
%   scalar              → return value
%   struct {max: X}     → return X  (e.g. PV 'power: {max: 2.3}')
%   struct {min, max}   → return max (rated upper limit)
%   otherwise           → NaN
function val = scalar_field_max(entry, field)
  val = NaN;
  if ~isfield(entry, field); return; end
  v = entry.(field);
  if isnumeric(v) && isscalar(v)
    val = v;
  elseif isstruct(v) && isfield(v, 'max')
    val = v.max;
  end
end

% Parses the cycle_life DB field which may be a string like ">25000" or a number.
function cycles = parse_cycle_life(entry)
  cycles = NaN;
  if ~isfield(entry, 'cycle_life'); return; end
  v = entry.cycle_life;
  if isnumeric(v) && isscalar(v)
    cycles = v;
  elseif ischar(v)
    % Strip non-numeric characters (e.g. '>', '<', '~') and parse the number
    num_str = regexprep(v, '[^0-9.]', '');
    if ~isempty(num_str)
      cycles = str2double(num_str);
    end
  end
end
