% test_scaling_law_api  Automated tests for the YAML-only scaling law infrastructure.
%
% Run from the ESDC repository root:
%   addpath(genpath('.')); test_scaling_law_api();
%
% All tests use the freshly generated YAML files in Database/Scaling/.
% Prerequisite: update_scaling_model(1) must have run successfully.

function results = test_scaling_law_api()
  results.pass = 0;
  results.fail = 0;
  results.msgs = {};

  scaling_law_cache('clear');
  fprintf('\n=== test_scaling_law_api ===\n\n');

  sample_stem = 'Database/Scaling/scaling_spacecraft_Low Earth_parameter_mass_total_to_fraction_mass_payload';
  comp_stem   = 'Database/Scaling/scaling_propulsion_system_arcjet_ppu_mass_to_power';
  h2n2_stem   = ['Database/Scaling/scaling_propulsion_system_arcjet_thruster_with_propellant_' ...
                 'H2_N2_mixtures_simulated_NH3_N2H4_decomposition_products_mass_to_power_jet'];

  % -----------------------------------------------------------------------
  % Section 1: YAML-only loading (no CSV fallback)
  % -----------------------------------------------------------------------
  fprintf('-- Section 1: YAML-only loading --\n');

  results = chk(results, exist([sample_stem '.yaml'], 'file'), ...
      'YAML file exists for sample spacecraft law');
  results = chk(results, ~exist([sample_stem '.csv'],  'file'), ...
      'No legacy CSV remains for sample law');

  law = scaling_law_load(sample_stem);
  results = chk(results, isstruct(law) && isfield(law, 'id'), ...
      'scaling_law_load returns valid struct');

  err_caught = false;
  try; scaling_law_load('Database/Scaling/nonexistent_law'); catch; err_caught = true; end
  results = chk(results, err_caught, 'Missing YAML throws error (no silent CSV fallback)');

  % -----------------------------------------------------------------------
  % Section 2: Evaluation at sample points
  % -----------------------------------------------------------------------
  fprintf('-- Section 2: Evaluation at sample points --\n');

  x_samp = law.model.samples.input;
  all_ok = true;
  for k = 1:numel(x_samp)
    y_ref = interp1(law.model.fit.x, law.model.fit.y, x_samp(k), 'linear', 'extrap');
    y_new = scaling_law_evaluate(law, x_samp(k));
    if abs(y_new - max(y_ref, 0)) > 1e-12; all_ok = false; end
  end
  results = chk(results, all_ok, 'Eval at all %d sample points matches reference', numel(x_samp));

  % -----------------------------------------------------------------------
  % Section 3: Interpolation and extrapolation
  % -----------------------------------------------------------------------
  fprintf('-- Section 3: Interpolation/extrapolation regime --\n');

  [~, info_in]  = scaling_law_evaluate(law, 1000);
  [y_ext, info_ext] = scaling_law_evaluate(law, law.domains.numerical.max * 2);
  results = chk(results, strcmp(info_in.regime,  'interpolation'),  'In-domain -> regime=interpolation');
  results = chk(results, strcmp(info_ext.regime, 'extrapolation'),  'Out-of-domain -> regime=extrapolation');
  results = chk(results, isfinite(y_ext) && y_ext >= 0, 'Extrapolation returns finite non-negative');

  % -----------------------------------------------------------------------
  % Section 4: Component law inversion
  % -----------------------------------------------------------------------
  fprintf('-- Section 4: Component law inversion --\n');

  law_ppu = scaling_law_load(comp_stem);
  m1 = scaling_law_evaluate(law_ppu, 500, 'invert', true);
  m2 = scaling_law_evaluate(law_ppu, 500, 'invert', true);
  results = chk(results, isfinite(m1) && m1 >= 0, 'Inverted eval returns finite non-negative (%.4g)', m1);
  results = chk(results, abs(m1 - m2) < 1e-12, 'Inverted eval is deterministic');

  % -----------------------------------------------------------------------
  % Section 5: Cache behavior
  % -----------------------------------------------------------------------
  fprintf('-- Section 5: Cache reuse and reload --\n');

  scaling_law_cache('clear');
  l1 = scaling_law_load(sample_stem);
  l2 = scaling_law_load(sample_stem);
  results = chk(results, isequal(l1.id, l2.id), 'Cache: second call returns same id');
  l3 = scaling_law_load(sample_stem, 'reload', true);
  results = chk(results, isequal(l3.id, l1.id), 'Reload: reloaded law has same id');

  % -----------------------------------------------------------------------
  % Section 6: Real fit quality metrics
  % -----------------------------------------------------------------------
  fprintf('-- Section 6: Fit quality metrics --\n');

  fm = law.quality.fit_metrics;
  results = chk(results, strcmp(fm.status, 'computed'), ...
      'fit_metrics.status = computed (not not_available)');
  results = chk(results, strcmp(fm.evaluation_basis, 'training_fit_only'), ...
      'evaluation_basis = training_fit_only');
  results = chk(results, isfield(fm, 'r_squared') && isfinite(fm.r_squared), ...
      'r_squared is finite (%.4f)', fm.r_squared);
  results = chk(results, isfield(fm, 'rmse') && isfinite(fm.rmse), ...
      'rmse is finite (%.6f)', fm.rmse);
  results = chk(results, isfield(fm, 'n_observations') && fm.n_observations > 0, ...
      'n_observations = %d', fm.n_observations);
  results = chk(results, ~isfield(law, 'provenance') || ...
      (~isfield(law.provenance, 'legacy_file') && ~isfield(law.provenance, 'migration_notes')), ...
      'No migration-only provenance fields in freshly generated YAML');

  % -----------------------------------------------------------------------
  % Section 7: Undefined metrics (constant output edge case)
  % -----------------------------------------------------------------------
  fprintf('-- Section 7: Undefined R2 for constant output --\n');

  [~, metrics_const] = data_fitting([0.5, 0.5; 1, 2]);
  results = chk(results, strcmp(metrics_const.r_squared_status, 'undefined_constant_output'), ...
      'Constant output -> r_squared_status = undefined_constant_output');
  results = chk(results, isnan(metrics_const.r_squared), ...
      'Constant output -> r_squared = NaN (not fabricated)');

  % -----------------------------------------------------------------------
  % Section 8: Propellant-name sanitization (regression for H2/N2 case)
  % -----------------------------------------------------------------------
  fprintf('-- Section 8: H2/N2 propellant name sanitization --\n');

  results = chk(results, exist([h2n2_stem '.yaml'], 'file'), ...
      'H2/N2 YAML exists with sanitized filename');
  law_h2 = scaling_law_load(h2n2_stem);
  results = chk(results, isfield(law_h2.classification, 'propellant_display'), ...
      'H2/N2 YAML contains propellant_display field');
  results = chk(results, ~isempty(strfind(law_h2.classification.propellant_display, 'H2/N2')), ...
      'propellant_display preserves original slash notation: %s', law_h2.classification.propellant_display);
  results = chk(results, isempty(strfind(law_h2.id, '/')), ...
      'Law id contains no slash: %s', law_h2.id);
  results = chk(results, ~exist('Database/Scaling/scaling_propulsion_system_arcjet_thruster_with_propellant_H2', 'dir'), ...
      'H2/ nested directory removed');
  safe = sanitize_identifier('H2/N2 mixtures (simulated NH3/N2H4 decomposition products)');
  results = chk(results, strcmp(safe, 'H2_N2_mixtures_simulated_NH3_N2H4_decomposition_products'), ...
      'sanitize_identifier produces correct safe ID: %s', safe);

  % -----------------------------------------------------------------------
  % Section 9: Schema validation
  % -----------------------------------------------------------------------
  fprintf('-- Section 9: Schema validation --\n');

  [ok, msgs] = scaling_law_validate(law);
  results = chk(results, ok, 'Freshly generated law passes validation');

  bad = law; bad.schema_version = 99;
  [ok2, ~] = scaling_law_validate(bad);
  results = chk(results, ~ok2, 'Wrong schema_version fails validation');

  % -----------------------------------------------------------------------
  % Section 10: No new CSVs produced during database regeneration
  % -----------------------------------------------------------------------
  fprintf('-- Section 10: YAML-only generation (no CSVs) --\n');

  csv_count = numel(dir('Database/Scaling/*.csv'));
  results = chk(results, csv_count == 0, ...
      'No scaling-law CSVs remain in Database/Scaling (%d found)', csv_count);

  % -----------------------------------------------------------------------
  % Section 11: Hash-based regeneration and cache invalidation
  % -----------------------------------------------------------------------
  fprintf('-- Section 11: Hash-based regeneration --\n');

  results = chk(results, exist('Database/ESDC_Reference_Data_Spacecrafts_hash', 'file'), ...
      'Spacecraft hash file exists');
  results = chk(results, exist('Database/ESDC_Reference_Data_Systems_hash', 'file'), ...
      'Systems hash file exists');

  scaling_law_cache('clear');
  update_scaling_model(0);  % should detect no change
  l_after = scaling_law_load(sample_stem);
  results = chk(results, isequal(l_after.id, law.id), ...
      'No-op update: law unchanged when database unchanged');

  % -----------------------------------------------------------------------
  % Section 12: Numerical regression
  % -----------------------------------------------------------------------
  fprintf('-- Section 12: Numerical regression --\n');

  test_pts = [100, 500, 1000, 2000, 5000, 10000];
  laws12   = dir('Database/Scaling/scaling_spacecraft_Low Earth_parameter_mass_total_to_*.yaml');
  max_err  = 0;
  n_chk    = 0;
  for k = 1:numel(laws12)
    s = fullfile('Database/Scaling', laws12(k).name(1:end-5));
    l = scaling_law_load(s, 'reload', true);
    for xi = 1:numel(test_pts)
      y = scaling_law_evaluate(l, test_pts(xi));
      y_ref = max(interp1(l.model.fit.x, l.model.fit.y, test_pts(xi), 'linear', 'extrap'), 0);
      err = abs(y - y_ref);
      if err > max_err; max_err = err; end
    end
    n_chk = n_chk + 1;
  end
  results = chk(results, max_err < 1e-12, ...
      'Numerical regression %d laws: max err = %.2e (tol 1e-12)', n_chk, max_err);

  fprintf('\n=== Results: %d PASS, %d FAIL ===\n\n', results.pass, results.fail);
end

function results = chk(results, cond, fmt, varargin)
  msg = sprintf(fmt, varargin{:});
  if cond
    fprintf('  PASS: %s\n', msg);
    results.pass = results.pass + 1;
  else
    fprintf('  FAIL: %s\n', msg);
    results.fail = results.fail + 1;
    results.msgs{end+1} = msg;
  end
end
