% test_plotting  Automated tests for the dissertation plotting framework.
%
% Run from the ESDC repository root:
%   addpath(genpath('.')); test_plotting();
%
% Prerequisites: update_scaling_model(1) must have run successfully so
% that YAML files exist in Database/Scaling/.
%
% Tests cover:
%   1. plot_style defaults and overrides
%   2. plot_quantity_label — known, fraction_*, dimensionless, unknown
%   3. plot_scaling_law — figure handles, metadata-driven labels
%   4. Fit quality legend entries — computed, undefined, unavailable
%   5. plot_fit_residuals — residual computation and handles
%   6. plot_export — file creation, output directory, filesystem-safe names
%   7. Headless execution (visible=false) without leaking open figures
%   8. Representative graph generation (spacecraft, component, propellant)
%   9. No legacy make_makeshift_graph reference survives

function results = test_plotting()
  % Ensure path includes all plotting modules
  this_dir = fileparts(mfilename('fullpath'));
  repo_root = fullfile(this_dir, '..', '..', '..');
  addpath(fullfile(repo_root, 'Code', 'Output', 'Plotting'));
  addpath(fullfile(repo_root, 'Code', 'Scaling'));
  addpath(fullfile(repo_root, 'Code', 'Support'));

  results.pass = 0;
  results.fail = 0;
  results.msgs = {};

  fprintf('\n=== test_plotting ===\n\n');

  % Convenience law stems
  sc_stem   = 'Database/Scaling/scaling_spacecraft_Low Earth_parameter_mass_total_to_fraction_mass_payload';
  comp_stem = 'Database/Scaling/scaling_propulsion_system_arcjet_ppu_mass_to_power';
  h2n2_stem = ['Database/Scaling/scaling_propulsion_system_arcjet_thruster_with_propellant_' ...
               'H2_N2_mixtures_simulated_NH3_N2H4_decomposition_products_mass_to_power_jet'];

  % -----------------------------------------------------------------------
  % Section 1: plot_style defaults and overrides
  % -----------------------------------------------------------------------
  fprintf('-- Section 1: plot_style --\n');

  st = plot_style();
  results = chk(results, isstruct(st), 'plot_style returns struct');
  results = chk(results, isfield(st, 'fig') && isfield(st.fig, 'width_single_cm'), ...
      'fig.width_single_cm field exists');
  results = chk(results, st.fig.width_single_cm == 11.0, ...
      'fig.width_single_cm == 11.0 cm (%.1f)', st.fig.width_single_cm);
  results = chk(results, st.fig.width_double_cm == 17.0, ...
      'fig.width_double_cm == 17.0 cm');
  results = chk(results, st.export.png_dpi == 300, 'export.png_dpi == 300');
  results = chk(results, strcmp(st.interpreter, 'none'), ...
      'interpreter = ''none'' (safe for underscores)');

  % Override via dotted key
  st2 = plot_style('fig.height_cm', 9.0, 'export.pdf_enabled', true);
  results = chk(results, st2.fig.height_cm == 9.0, 'Override fig.height_cm -> 9.0');
  results = chk(results, st2.export.pdf_enabled == true, 'Override export.pdf_enabled -> true');
  results = chk(results, st2.export.png_dpi == 300, 'Non-overridden field unchanged');

  % -----------------------------------------------------------------------
  % Section 2: plot_quantity_label
  % -----------------------------------------------------------------------
  fprintf('-- Section 2: plot_quantity_label --\n');

  [lbl, unit] = plot_quantity_label('c_e');
  results = chk(results, strcmp(lbl, 'Effective exhaust velocity'), ...
      'c_e -> ''Effective exhaust velocity''');
  results = chk(results, strcmp(unit, 'm/s'), 'c_e unit -> ''m/s''');

  [lbl2, unit2] = plot_quantity_label('mass_payload');
  results = chk(results, strcmp(lbl2, 'Payload mass'), 'mass_payload label');
  results = chk(results, strcmp(unit2, 'kg'),           'mass_payload unit = kg');

  [lbl3, unit3] = plot_quantity_label('fraction_mass_ADC');
  results = chk(results, ~isempty(lbl3) && ~strcmp(lbl3, 'fraction mass ADC'), ...
      'fraction_mass_ADC has registry entry: ''%s''', lbl3);
  results = chk(results, strcmp(unit3, '-'), 'fraction_mass_ADC unit = -');

  [lbl4, unit4] = plot_quantity_label('efficiency');
  results = chk(results, strcmp(unit4, '-'), 'efficiency unit = - (dimensionless)');

  % Unknown identifier — should warn, not error; fallback must be non-empty
  warn_caught = false;
  orig = warning('off', 'plot_quantity_label:unknown');
  try
    [lbl5, unit5] = plot_quantity_label('totally_unknown_qty', 'frobnitz');
    warn_caught = true;
  catch
  end
  warning(orig);
  results = chk(results, warn_caught && ~isempty(lbl5), ...
      'Unknown quantity: fallback label non-empty');
  results = chk(results, strcmp(unit5, 'frobnitz'), ...
      'Unknown quantity: unit_hint used as fallback');

  % -----------------------------------------------------------------------
  % Section 3: plot_scaling_law — handles and metadata
  % -----------------------------------------------------------------------
  fprintf('-- Section 3: plot_scaling_law --\n');

  if ~exist([sc_stem '.yaml'], 'file')
    fprintf('  SKIP: YAML not found — run update_scaling_model(1) first\n');
  else
    scaling_law_cache('clear');
    law = scaling_law_load(sc_stem);
    [fig, ax, ~] = plot_scaling_law(law, struct('export', false, 'visible', false));
    results = chk(results, ishandle(fig) && strcmp(get(fig,'Type'),'figure'), ...
        'plot_scaling_law returns valid figure handle');
    results = chk(results, ishandle(ax) && strcmp(get(ax,'Type'),'axes'), ...
        'plot_scaling_law returns valid axes handle');

    % Axis labels must not contain filename fragments or raw identifiers
    xl = get(get(ax,'XLabel'),'String');
    yl = get(get(ax,'YLabel'),'String');
    results = chk(results, ~isempty(xl) && isempty(strfind(xl,'mass_total')), ...
        'X label is human-readable (no raw identifier): ''%s''', xl);
    results = chk(results, ~isempty(yl) && isempty(strfind(yl,'fraction_mass_payload')), ...
        'Y label is human-readable (no raw identifier): ''%s''', yl);

    % Fit line and observation line must have correct DisplayName properties
    lines    = findobj(ax, 'Type', 'line');
    dns      = get_display_names(lines);
    has_fit_dn = any(cellfun(@(s) ~isempty(strfind(lower(s),'polynomial fit')), dns));
    has_obs_dn = any(cellfun(@(s) ~isempty(strfind(lower(s),'hardware data point')), dns));
    results = chk(results, has_fit_dn, 'Fit line has polynomial fit DisplayName');
    results = chk(results, has_obs_dn, 'Observation line has hardware data point DisplayName');

    close(fig);
  end

  % -----------------------------------------------------------------------
  % Section 4: Fit quality text-box content
  % -----------------------------------------------------------------------
  fprintf('-- Section 4: Fit quality text boxes --\n');

  if exist([sc_stem '.yaml'], 'file')
    law = scaling_law_load(sc_stem);

    % Inspect DisplayName on plotted lines — independent of legend object type
    [fig2, ax2, ~] = plot_scaling_law(law, struct('export', false, 'visible', false));
    lines2    = findobj(ax2, 'Type', 'line');
    dns2      = get_display_names(lines2);
    poly_idx2 = find(cellfun(@(s) ~isempty(strfind(lower(s),'polynomial fit')), dns2), 1);
    fit_dn    = '';
    if ~isempty(poly_idx2); fit_dn = dns2{poly_idx2}; end
    results = chk(results, ~isempty(fit_dn), 'Fit line DisplayName contains ''polynomial fit''');

    tx2 = findobj(ax2, 'Type', 'text');
    txt2 = text_strings_joined(tx2);
    results = chk(results, ~isempty(strfind(txt2, 'R²:')) || ~isempty(strfind(txt2, 'R\^2:')), ...
      'Fit quality text contains R²');
    results = chk(results, ~isempty(strfind(txt2, 'RMSE:')), ...
      'Fit quality text contains RMSE');
    results = chk(results, isempty(strfind(fit_dn, 'R2')) && isempty(strfind(fit_dn, 'RMSE')), ...
      'Fit DisplayName excludes R2/RMSE metrics');
    close(fig2);

    % Law with no fit metrics: must degrade gracefully
    law_nm = law;
    law_nm.quality = rmfield(law_nm.quality, 'fit_metrics');
    [fig3, ~, ~] = plot_scaling_law(law_nm, struct('export', false, 'visible', false));
    results = chk(results, ishandle(fig3), 'No-metrics law: figure still created');
    close(fig3);

    % Undefined R2 (constant-output edge case)
    [~, mc] = data_fitting([0.5, 0.5; 1, 2]);
    law_const = law; mc.status = 'computed';
    law_const.quality.fit_metrics = mc;
    [fig4, ax4, ~] = plot_scaling_law(law_const, struct('export', false, 'visible', false));
    lines4  = findobj(ax4, 'Type', 'line');
    dns4    = get_display_names(lines4);
    idx4    = find(cellfun(@(s) ~isempty(strfind(lower(s),'polynomial fit')), dns4), 1);
    entry4  = '';
    if ~isempty(idx4); entry4 = dns4{idx4}; end
    tx4   = findobj(ax4, 'Type', 'text');
    txt4  = text_strings_joined(tx4);
    results = chk(results, ~isempty(strfind(txt4, 'undefined')), ...
      'Undefined R² labelled in fit quality text');
    close(fig4);
  end

  % -----------------------------------------------------------------------
  % Section 5: plot_fit_residuals
  % -----------------------------------------------------------------------
  fprintf('-- Section 5: plot_fit_residuals --\n');

  if exist([comp_stem '.yaml'], 'file')
    law_c = scaling_law_load(comp_stem);
    [fig5, ax5, ~] = plot_fit_residuals(law_c, struct('export', false, 'visible', false));
    results = chk(results, ishandle(fig5), 'plot_fit_residuals: valid figure');
    results = chk(results, ishandle(ax5),  'plot_fit_residuals: valid axes');

    % Y label must mention residual and output unit
    yl5 = get(get(ax5,'YLabel'),'String');
    results = chk(results, ~isempty(strfind(lower(yl5),'residual')), ...
        'Residuals y-label contains ''residual'': ''%s''', yl5);
    close(fig5);
  end

  % -----------------------------------------------------------------------
  % Section 6: plot_export — file creation and filesystem-safe names
  % -----------------------------------------------------------------------
  fprintf('-- Section 6: plot_export --\n');

  if exist([sc_stem '.yaml'], 'file')
    law = scaling_law_load(sc_stem);
    tmp_dir = fullfile(tempdir(), 'esdc_test_plotting');
    if ~exist(tmp_dir, 'dir'); mkdir(tmp_dir); end

    [fig6, ~, ~] = plot_scaling_law(law, struct('export', false, 'visible', false));
    info6 = plot_export(fig6, fullfile(tmp_dir, law.id));
    results = chk(results, strcmp(info6.status, 'ok') || strcmp(info6.status, 'partial'), ...
        'plot_export status: ok or partial (got ''%s'')', info6.status);
    results = chk(results, ~isempty(info6.paths), 'plot_export wrote at least one file');
    if ~isempty(info6.paths)
      results = chk(results, exist(info6.paths{1}, 'file') == 2, ...
          'Exported PNG file exists on disk: %s', info6.paths{1});
    end
    close(fig6);

    % Export to a new non-existent subdirectory — mkdir must be automatic
    new_sub = fullfile(tmp_dir, 'sub1', 'sub2');
    [fig7, ~, ~] = plot_scaling_law(law, struct('export', false, 'visible', false));
    info7 = plot_export(fig7, fullfile(new_sub, 'test_export'));
    results = chk(results, ~strcmp(info7.status, 'failed'), ...
        'plot_export creates missing directories automatically');
    close(fig7);
  end

  % -----------------------------------------------------------------------
  % Section 7: Headless execution — no figure windows leak
  % -----------------------------------------------------------------------
  fprintf('-- Section 7: Headless execution (no figure leaks) --\n');

  if exist([sc_stem '.yaml'], 'file')
    before = numel(findall(0, 'Type', 'figure'));
    law = scaling_law_load(sc_stem);
    [fig8, ~, ~] = plot_scaling_law(law, struct('export', false, 'visible', false));
    results = chk(results, strcmp(get(fig8,'Visible'), 'off'), ...
        'visible=false: figure is invisible');
    close(fig8);
    after = numel(findall(0, 'Type', 'figure'));
    results = chk(results, after == before, ...
        'No figure leaks after close: before=%d, after=%d', before, after);
  end

  % -----------------------------------------------------------------------
  % Section 8: Representative graph generation (real YAMLs)
  % -----------------------------------------------------------------------
  fprintf('-- Section 8: Representative graph generation --\n');

  tmp_out = fullfile(tempdir(), 'esdc_test_plots');
  test_cases = {sc_stem, 'spacecraft low earth, dimensionless output'; ...
                comp_stem, 'component law, dimensional output'; ...
                h2n2_stem, 'H2/N2 propellant display name'};

  for k = 1:size(test_cases, 1)
    stem = test_cases{k, 1};
    desc = test_cases{k, 2};
    if ~exist([stem '.yaml'], 'file')
      fprintf('  SKIP (%s): YAML not found\n', desc); continue;
    end
    try
      l = scaling_law_load(stem, 'reload', true);
      opts8 = struct('output_dir', tmp_out, 'export', true, 'visible', false);
      [fig9, ~, info9] = plot_scaling_law(l, opts8);
      ok = ishandle(fig9) && ~strcmp(info9.status, 'failed');
      results = chk(results, ok, 'Representative plot (%s): status=%s', desc, info9.status);
      close(fig9);
    catch ex
      results = chk(results, false, 'Representative plot (%s): EXCEPTION: %s', desc, ex.message);
    end
  end

  % H2/N2 law: propellant_display must appear in annotation (not raw identifier)
  if exist([h2n2_stem '.yaml'], 'file')
    lh2 = scaling_law_load(h2n2_stem, 'reload', true);
    results = chk(results, isfield(lh2.classification, 'propellant_display'), ...
        'H2/N2 law has propellant_display field');
    [fig10, ax10, ~] = plot_scaling_law(lh2, struct('export', false, 'visible', false));
    % The annotation text object should contain 'H2/N2'
    txt_objs = findobj(ax10, 'Type', 'Text');
    found_h2n2 = false;
    for t = 1:numel(txt_objs)
      if ~isempty(strfind(get(txt_objs(t),'String'),'H2/N2'))
        found_h2n2 = true; break;
      end
    end
    results = chk(results, found_h2n2, ...
        'H2/N2 propellant_display visible in figure annotation');
    close(fig10);
  end

  % -----------------------------------------------------------------------
  % Section 9: No legacy make_makeshift_graph
  % -----------------------------------------------------------------------
  fprintf('-- Section 9: No legacy makeshift references --\n');

  results = chk(results, exist('make_makeshift_graph', 'file') == 0, ...
      'make_makeshift_graph.m deleted from path');
  % Confirm it is not called from write_selected_data_to_file either
  wsdf = fullfile('Code', 'Scaling', 'write_selected_data_to_file.m');
  if exist(wsdf, 'file')
    src = fileread(wsdf);
    results = chk(results, isempty(strfind(src, 'make_makeshift_graph(')), ...
        'write_selected_data_to_file no longer calls make_makeshift_graph');
  end

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

function dns = get_display_names(handles)
% Return cell array of DisplayName strings from a handle array.
  dns = cell(1, numel(handles));
  for k = 1:numel(handles)
    dns{k} = get(handles(k), 'DisplayName');
  end
end

function joined = text_strings_joined(text_handles)
% Return all text object strings as one searchable string.
  chunks = {};
  for k = 1:numel(text_handles)
    s = get(text_handles(k), 'String');
    if ischar(s)
      chunks{end+1} = s;
    elseif iscell(s)
      chunks{end+1} = strjoin(s, ' | ');
    end
  end
  if isempty(chunks)
    joined = '';
  else
    joined = strjoin(chunks, ' || ');
  end
end
