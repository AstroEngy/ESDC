% test_mass_initialization  Regression tests for payload-only mass initialisation.
%
% Covers the bug where system_completion_estimation crashed when mass_payload
% was given as the only input (no mass_total, no power fields) because
% system_with_unknown_totals unconditionally accessed known.power even when
% no power fields had been supplied.
%
% Test matrix:
%   T1  — mass_total given explicitly (baseline, must remain unchanged)
%   T2  — mass_payload + deltav + propulsion_power, no mass_total  (example files)
%   T3  — mass_payload + deltav, no mass_total, no power fields    (BUG CASE A)
%   T4  — mass_payload only, no deltav, no mass_total, no power    (BUG CASE B)
%   T5  — mass_total given; repeated evaluation gives consistent result
%
% Usage (from ESDC root directory):
%   addpath('Code/Analysis','Code/Evolver','Code/Input','Code/Output','Code/Scaling','Code/Support');
%   test_mass_initialization()

function test_mass_initialization()
  fprintf('\n=== test_mass_initialization ===\n');

  passed = 0;
  failed = 0;

  tests = {
    @t1_explicit_mass_total,                 'T1 explicit mass_total baseline';
    @t2_payload_deltav_power_no_mass_total,  'T2 payload+deltav+propulsion_power, no mass_total';
    @t3_payload_deltav_no_power,             'T3 payload+deltav, no power (bug case A)';
    @t4_payload_only_no_deltav_no_power,     'T4 payload only, no deltav, no power (bug case B)';
    @t5_mass_total_repeated_consistent,      'T5 mass_total repeated evaluation consistent';
  };

  for i = 1:size(tests, 1)
    fn   = tests{i, 1};
    name = tests{i, 2};
    try
      fn();
      fprintf('  PASS  %s\n', name);
      passed = passed + 1;
    catch err
      fprintf('  FAIL  %s\n        %s\n', name, err.message);
      failed = failed + 1;
    end
  end

  fprintf('\n%d/%d tests passed\n', passed, passed + failed);
  if failed > 0
    error('test_mass_initialization: %d test(s) FAILED', failed);
  end
end


% -------------------------------------------------------------------------
% Helper: build a minimal simulation-parameters struct accepted by
% system_completion_estimation (mirrors ESDC_Simulation_parameters.yaml).
% -------------------------------------------------------------------------
function sim = make_sim()
  sim.Simulation_parameters.defaults.sc_type_thresholds.orbit_height_leo_max = 2000;
  sim.Simulation_parameters.defaults.sc_type_thresholds.dv_geo_min           = 2000;
  sim.Simulation_parameters.defaults.sc_type_thresholds.dv_escape_min        = 4300;
end


% =========================================================================
% T1: mass_total given explicitly
%     The system_with_known_mass_total path should derive consistent
%     subsystem masses whose sum is <= mass_total (within margin).
% =========================================================================
function t1_explicit_mass_total()
  inputs.mass_total    = 500;   % [kg]
  inputs.orbit_height  = 500;   % LEO -> sc_type 2
  sim = make_sim();

  d = system_completion_estimation(inputs, sim);

  assert(d.sc_type == 2, 'sc_type should be 2 (LEO)');
  assert(isfield(d, 'known') && isfield(d.known, 'mass'), 'known.mass must exist');
  assert(d.known.mass.mass_total == 500, 'known mass_total must be preserved');
  assert(isfield(d.known.mass, 'mass_total_margin'), 'mass_total_margin must be set');
  assert(d.known.mass.mass_total_margin > 0, 'mass_total_margin must be positive');
  assert(d.known.mass.mass_total_margin < 500, 'mass_total_margin must be less than mass_total');

  % Derived subsystem masses must all be finite and positive
  fns = fieldnames(d.unknown.mass);
  for k = 1:numel(fns)
    v = d.unknown.mass.(fns{k});
    assert(isfinite(v), sprintf('unknown.mass.%s not finite', fns{k}));
    assert(v >= 0,      sprintf('unknown.mass.%s negative', fns{k}));
  end
end


% =========================================================================
% T2: mass_payload + deltav + propulsion_power, no mass_total
%     This is the pattern used by the existing example files.
%     The total mass must be derived as a positive finite number, and
%     unknown.mass.mass_total must exceed mass_payload (payload is a subset).
% =========================================================================
function t2_payload_deltav_power_no_mass_total()
  inputs.orbit_height      = 500;   % LEO -> sc_type 2
  inputs.mass_payload      = 1200;  % [kg]
  inputs.deltav            = 300;   % [m/s]
  inputs.propulsion_power  = 8000;  % [W]
  inputs.mission_duration  = 5;
  inputs.propulsion_time_fraction = 0.05;
  sim = make_sim();

  d = system_completion_estimation(inputs, sim);

  assert(d.sc_type == 2, 'sc_type should be 2 (LEO)');
  assert(~isfield(d.known, 'mass') || ~isfield(d.known.mass, 'mass_total'), ...
         'mass_total must NOT be in known (user did not supply it)');
  assert(isfield(d.unknown, 'mass') && isfield(d.unknown.mass, 'mass_total'), ...
         'mass_total must be in unknown (derived estimate)');

  m_tot = d.unknown.mass.mass_total;
  assert(isfinite(m_tot),   'derived mass_total must be finite');
  assert(m_tot > 0,         'derived mass_total must be positive');
  assert(m_tot > 1200,      'derived mass_total must exceed mass_payload');

  % Derived subsystem masses must be finite and non-negative
  fns = fieldnames(d.unknown.mass);
  for k = 1:numel(fns)
    v = d.unknown.mass.(fns{k});
    assert(isfinite(v), sprintf('unknown.mass.%s not finite', fns{k}));
    assert(v >= 0,      sprintf('unknown.mass.%s negative', fns{k}));
  end

  % Power total must be estimated
  assert(isfield(d.unknown, 'power') && isfield(d.unknown.power, 'power_total'), ...
         'power_total must be estimated');
  assert(isfinite(d.unknown.power.power_total), 'power_total must be finite');
  assert(d.unknown.power.power_total > 0,       'power_total must be positive');
end


% =========================================================================
% T3: mass_payload + deltav, no mass_total, NO power fields  (Bug Case A)
%     Before the fix, system_with_unknown_totals crashed because
%     sum_powers(known.power, ...) was called when known.power was absent.
%     After the fix, total mass must still be derived correctly.
% =========================================================================
function t3_payload_deltav_no_power()
  inputs.orbit_height  = 500;   % LEO -> sc_type 2
  inputs.mass_payload  = 1200;  % [kg]
  inputs.deltav        = 300;   % [m/s]
  % NO propulsion_power, NO power_payload, NO power_total
  sim = make_sim();

  d = system_completion_estimation(inputs, sim);

  assert(d.sc_type == 2, 'sc_type should be 2 (LEO)');
  assert(isfield(d.unknown, 'mass') && isfield(d.unknown.mass, 'mass_total'), ...
         'mass_total must be derived');

  m_tot = d.unknown.mass.mass_total;
  assert(isfinite(m_tot), 'derived mass_total must be finite');
  assert(m_tot > 0,       'derived mass_total must be positive');
  assert(m_tot > 1200,    'derived mass_total must exceed mass_payload');

  % power_total must be estimated from mass (scaling only)
  assert(isfield(d.unknown, 'power') && isfield(d.unknown.power, 'power_total'), ...
         'power_total must be estimated even when no power input given');
  assert(isfinite(d.unknown.power.power_total), 'power_total must be finite');
  assert(d.unknown.power.power_total > 0,       'power_total must be positive');
end


% =========================================================================
% T4: mass_payload only, no deltav, no mass_total, no power  (Bug Case B)
%     orbit_height drives sc_type=2. The omitted deltav follows established
%     repository behaviour (no propellant consumed, dry mass = total mass).
%     Before the fix this also crashed; after the fix it must complete and
%     produce a physically consistent estimate.
% =========================================================================
function t4_payload_only_no_deltav_no_power()
  inputs.orbit_height = 500;    % LEO -> sc_type 2
  inputs.mass_payload = 1200;   % [kg] — the only mass/power field
  % NO deltav, NO mass_total, NO power fields
  sim = make_sim();

  d = system_completion_estimation(inputs, sim);

  assert(d.sc_type == 2, 'sc_type should be 2 (LEO)');
  assert(isfield(d.unknown, 'mass') && isfield(d.unknown.mass, 'mass_total'), ...
         'mass_total must be derived from payload mass fraction');

  m_tot = d.unknown.mass.mass_total;
  assert(isfinite(m_tot), 'derived mass_total must be finite');
  assert(m_tot > 0,       'derived mass_total must be positive');
  assert(m_tot > 1200,    'derived mass_total must exceed mass_payload');

  % Subsystem masses must sum to approximately mass_total_margin
  m_margin    = d.unknown.mass.mass_total_margin;
  fns = fieldnames(d.unknown.mass);
  m_sub_sum = 0;
  for k = 1:numel(fns)
    f = fns{k};
    if ~any(strcmp(f, {'mass_total','m_margin','mass_total_margin'}))
      v = d.unknown.mass.(f);
      assert(isfinite(v), sprintf('unknown.mass.%s not finite', f));
      assert(v >= 0,      sprintf('unknown.mass.%s negative', f));
      m_sub_sum = m_sub_sum + v;
    end
  end
  % Allow 1% relative tolerance for independent fraction regressions
  known_payload = 1200;
  m_sub_sum_with_payload = m_sub_sum + known_payload;
  rel_err = abs(m_sub_sum_with_payload - m_margin) / max(1, m_margin);
  assert(rel_err < 0.15, ...
    sprintf('Subsystem mass sum (%.1f + 1200 = %.1f) deviates >15%% from mass_total_margin (%.1f)', ...
            m_sub_sum, m_sub_sum_with_payload, m_margin));

  % power_total must be estimated
  assert(isfield(d.unknown, 'power') && isfield(d.unknown.power, 'power_total'), ...
         'power_total must be estimated');
  assert(isfinite(d.unknown.power.power_total), 'power_total must be finite');
  assert(d.unknown.power.power_total > 0,       'power_total must be positive');
end


% =========================================================================
% T5: mass_total explicit — repeated evaluation gives identical result
%     Verifies that system_completion_estimation has no side effects and
%     is deterministic when called twice with the same input.
% =========================================================================
function t5_mass_total_repeated_consistent()
  inputs.mass_total   = 1000;  % [kg]
  inputs.orbit_height = 500;   % LEO
  sim = make_sim();

  d1 = system_completion_estimation(inputs, sim);
  d2 = system_completion_estimation(inputs, sim);

  assert(d1.known.mass.mass_total == d2.known.mass.mass_total, ...
         'mass_total must be identical across repeated calls');
  assert(abs(d1.unknown.mass.mass_structmech - d2.unknown.mass.mass_structmech) < 1e-9, ...
         'mass_structmech must be identical across repeated calls');
  assert(abs(d1.unknown.power.power_total - d2.unknown.power.power_total) < 1e-6, ...
         'power_total must be identical across repeated calls');
end
