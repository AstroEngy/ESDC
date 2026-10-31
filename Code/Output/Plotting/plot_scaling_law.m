function [fig, ax, export_info] = plot_scaling_law(law, options)
% plot_scaling_law  Create a dissertation-quality scaling law plot.
%
% [fig, ax, export_info] = plot_scaling_law(law)
% [fig, ax, export_info] = plot_scaling_law(law, options)
%
% law     - scaling law struct as returned by scaling_law_load() or
%           built by build_law_struct() in write_selected_data_to_file().
% options - optional struct:
%   .output_dir   directory for PNG/PDF output (default: 'Output/Scaling')
%   .style        style struct from plot_style() (default: plot_style())
%   .export       true/false - write file to disk (default: true)
%   .visible      true/false - show figure on screen (default: false)
%   .show_title   true/false - embed title in figure (default: false)
%
% Returns:
%   fig         - figure handle; caller is responsible for closing it
%   ax          - axes handle
%   export_info - struct from plot_export() (empty struct if export=false)

if nargin < 2; options = struct(); end

output_dir = opt(options, 'output_dir', 'Output/Scaling');
st         = opt(options, 'style',      plot_style());
do_export  = opt(options, 'export',     true);
visible    = opt(options, 'visible',    false);

% ---- Extract observations and fit curve --------------------------------
x_obs = law.model.samples.input;
y_obs = law.model.samples.output;
x_fit = law.model.fit.x;
y_fit = law.model.fit.y;

% ---- Axis labels from quantity registry --------------------------------
in_q  = safe_get(law.input,  'quantity', 'unknown');
in_u  = safe_get(law.input,  'unit',     '');
out_q = safe_get(law.output, 'quantity', 'unknown');
out_u = safe_get(law.output, 'unit',     '');

[in_lbl,  in_unit]  = plot_quantity_label(in_q,  in_u);
[out_lbl, out_unit] = plot_quantity_label(out_q, out_u);

x_axis_str = axis_label(in_lbl,  in_unit);
y_axis_str = axis_label(out_lbl, out_unit);

% ---- Legend entries ----------------------------------------------------
obs_legend = build_obs_legend(numel(x_obs));
fit_legend = build_fit_curve_label(law);

% ---- Classification and fit metadata -----------------------------------
annot_str          = classification_annotation(law);
fit_quality_lines  = build_fit_quality_lines(law, out_unit);
fit_model_lines    = build_fit_model_lines(law);

% ---- Create figure -----------------------------------------------------
vis_str = 'off';
if visible; vis_str = 'on'; end

fig = figure('Visible', vis_str, ...
             'Color',   [1 1 1], ...
             'Units',   'centimeters', ...
             'Position', [2, 2, st.fig.width_single_cm, st.fig.height_cm]);
ax = axes('Parent', fig);
hold(ax, 'on');

% ---- Observations (behind fitted curve) --------------------------------
plot(ax, x_obs, y_obs, ...
  st.marker.style_obs, ...
  'MarkerSize',      st.marker.size_obs, ...
  'Color',           st.color.observations, ...
  'MarkerFaceColor', st.color.observations, ...
  'LineStyle',       'none', ...
  'DisplayName',     obs_legend);

% ---- Fitted curve ------------------------------------------------------
plot(ax, x_fit, y_fit, '-', ...
  'LineWidth',   st.line.width_fit, ...
  'Color',       st.color.fit, ...
  'DisplayName', fit_legend);

% ---- Numerical domain boundary markers ---------------------------------
if isfield(law, 'domains') && isfield(law.domains, 'numerical')
  x_min = law.domains.numerical.min;
  x_max = law.domains.numerical.max;
  if abs(x_max - x_min) > 0
    yl = ylim(ax);
    plot(ax, [x_min x_min], yl, ':', ...
      'Color',           st.color.extrapolation, ...
      'LineWidth',       st.line.width_reference, ...
      'HandleVisibility','off');
    plot(ax, [x_max x_max], yl, ':', ...
      'Color',           st.color.extrapolation, ...
      'LineWidth',       st.line.width_reference, ...
      'HandleVisibility','off');
  end
end

% ---- Axes formatting ---------------------------------------------------
hxl = xlabel(ax, x_axis_str, 'Interpreter', st.interpreter, 'FontSize', st.font.size_axis_label);
hyl = ylabel(ax, y_axis_str, 'Interpreter', st.interpreter, 'FontSize', st.font.size_axis_label);
set(hxl, 'Clipping', 'off');
set(hyl, 'Clipping', 'off');

set(ax, 'FontName',             st.font.family, ...
        'FontSize',             st.font.size_tick, ...
        'Box',                  bool_str(st.box.on), ...
        'Color',                [1 1 1], ...
        'TickLabelInterpreter', st.interpreter);

if st.grid.on
  grid(ax, 'on');
end

if st.show_title && isfield(law, 'title')
  title(ax, strrep(law.title, '_', ' '), ...
        'Interpreter', st.interpreter, 'FontSize', st.font.size_title);
end

% ---- Legend ------------------------------------------------------------
ax_pos = get(ax, 'Position');
legend(ax, 'Location', st.legend.location, ...
           'FontSize', st.font.size_legend, ...
           'Interpreter', st.interpreter, ...
           'Box', 'off');
set(ax, 'Position', ax_pos);

% ---- Classification annotation (top-left) ------------------------------
h_ann = [];
if ~isempty(annot_str)
  h_ann = text(ax, 0.02, 0.98, annot_str, ...
    'Units',              'normalized', ...
    'VerticalAlignment',  'top', ...
    'HorizontalAlignment','left', ...
    'FontSize',           st.font.size_annotation, ...
    'Interpreter',        st.interpreter, ...
    'Color',              [0.40, 0.40, 0.40]);
end

% ---- Fit metadata boxes -------------------------------------------------
gap = 0.03;
y_cursor = 0.98;
if ~isempty(h_ann)
  drawnow();
  y_cursor = box_bottom(h_ann) - gap;
end

h_q = [];
if ~isempty(fit_quality_lines)
  h_q = add_info_box(ax, 0.02, y_cursor, fit_quality_lines, st, st.font.size_annotation);
  drawnow();
  y_cursor = box_bottom(h_q) - gap;
end

if ~isempty(fit_model_lines)
  % Keep model details readable without colliding with quality box.
  x_model = 0.02;
  y_model = y_cursor;

  if y_model < 0.14
    x_model = 0.52;
    y_model = 0.64;
  end

  h_m = add_info_box(ax, x_model, y_model, fit_model_lines, st, st.font.size_annotation - 0.5);
  drawnow();

  if ~isempty(h_q) && boxes_overlap(h_q, h_m)
    set(h_m, 'Position', [0.52, 0.50, 0]);
    drawnow();
  end
end

hold(ax, 'off');

% ---- Export ------------------------------------------------------------
export_info = struct();
if do_export
  law_id   = safe_get(law, 'id', 'scaling_unknown');
  safe_id  = fs_safe(law_id);
  out_path = fullfile(output_dir, safe_id);
  export_info = plot_export(fig, out_path, st);
end
end

% =========================================================================
% Local helpers
% =========================================================================

function v = opt(s, field, default)
  if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
    v = s.(field);
  else
    v = default;
  end
end

function v = safe_get(s, field, default)
  if isstruct(s) && isfield(s, field)
    v = s.(field);
  else
    v = default;
  end
end

function s = bool_str(b)
  if b; s = 'on'; else; s = 'off'; end
end

function lbl = axis_label(disp_label, unit_str)
  if isempty(unit_str) || any(strcmp(unit_str, {'unknown', '?', ''}))
    lbl = disp_label;
  else
    lbl = sprintf('%s / %s', disp_label, unit_str);
  end
end

function s = classification_annotation(law)
  parts = {};
  if ~isfield(law, 'classification'); s = ''; return; end
  cl = law.classification;
  if isfield(cl, 'orbit_type')         && ~isempty(cl.orbit_type);         parts{end+1} = cl.orbit_type; end
  if isfield(cl, 'technology')         && ~isempty(cl.technology);         parts{end+1} = cl.technology; end
  if isfield(cl, 'component')          && ~isempty(cl.component);          parts{end+1} = cl.component;  end
  if isfield(cl, 'propellant_display') && ~isempty(cl.propellant_display)
    prop = cl.propellant_display;
    if numel(prop) > 40; prop = [prop(1:37) '...']; end
    parts{end+1} = prop;
  elseif isfield(cl, 'propellant') && ~isempty(cl.propellant)
    parts{end+1} = strrep(cl.propellant, '_', ' ');
  end
  s = strjoin(parts, ', ');
end

function s = build_obs_legend(n_obs)
  if n_obs == 1
    s = '1 hardware data point';
  else
    s = sprintf('%d hardware data points', n_obs);
  end
end

function s = build_fit_curve_label(law)
  deg = NaN;
  if isfield(law, 'model') && isfield(law.model, 'poly_degree')
    deg = law.model.poly_degree;
  elseif isfield(law, 'quality') && isfield(law.quality, 'fit_metrics') && ...
      isfield(law.quality.fit_metrics, 'poly_degree')
    deg = law.quality.fit_metrics.poly_degree;
  end

  if isnan(deg)
    s = 'Polynomial fit';
  else
    s = sprintf('%s-degree polynomial fit', degree_ordinal(deg));
  end
end

function lines = build_fit_quality_lines(law, out_unit)
  lines = {};
  if ~isfield(law, 'quality') || ~isfield(law.quality, 'fit_metrics')
    return;
  end

  fm = law.quality.fit_metrics;
  if ~isfield(fm, 'status') || ~strcmp(fm.status, 'computed')
    return;
  end

  lines{end+1} = 'FIT QUALITY';

  if isfield(fm, 'r_squared_status') && strcmp(fm.r_squared_status, 'undefined_constant_output')
    lines{end+1} = 'R²: undefined (constant output)';
  elseif isfield(fm, 'r_squared') && isfinite(fm.r_squared)
    lines{end+1} = sprintf('R²: %.3f', fm.r_squared);
  end

  if isfield(fm, 'rmse') && isfinite(fm.rmse)
    if isempty(out_unit) || any(strcmp(out_unit, {'-', 'dimensionless', 'unknown', '?', ''}))
      lines{end+1} = sprintf('RMSE: %.3g', fm.rmse);
    else
      lines{end+1} = sprintf('RMSE: %.3g %s', fm.rmse, out_unit);
    end
  end

  if isfield(fm, 'n_observations') && fm.n_observations > 0
    lines{end+1} = sprintf('n: %d', fm.n_observations);
  end
end

function lines = build_fit_model_lines(law)
  lines = {};
  deg = NaN;
  coeffs = [];

  if isfield(law, 'model') && isfield(law.model, 'poly_degree')
    deg = law.model.poly_degree;
  elseif isfield(law, 'quality') && isfield(law.quality, 'fit_metrics') && ...
      isfield(law.quality.fit_metrics, 'poly_degree')
    deg = law.quality.fit_metrics.poly_degree;
  end

  if isfield(law, 'model') && isfield(law.model, 'poly_coeffs')
    coeffs = law.model.poly_coeffs;
  elseif isfield(law, 'quality') && isfield(law.quality, 'fit_metrics') && ...
      isfield(law.quality.fit_metrics, 'poly_coeffs')
    coeffs = law.quality.fit_metrics.poly_coeffs;
  end

  if isnan(deg) && isempty(coeffs)
    return;
  end

  lines{end+1} = 'FIT MODEL';

  if isnan(deg)
    lines{end+1} = 'polynomial fit';
  else
    lines{end+1} = sprintf('%s-degree polynomial', degree_ordinal(deg));
  end

  if isempty(coeffs)
    lines{end+1} = 'Coefficients: unavailable';
    return;
  end

  terms = cell(1, numel(coeffs));
  for k = 1:numel(coeffs)
    p = numel(coeffs) - k;
    terms{k} = sprintf('a%d=%.3g', p, coeffs(k));
  end

  max_terms_per_line = 3;
  n_lines = ceil(numel(terms) / max_terms_per_line);
  for i = 1:n_lines
    i0 = (i - 1) * max_terms_per_line + 1;
    i1 = min(i0 + max_terms_per_line - 1, numel(terms));
    if i == 1
      lines{end+1} = ['Coeff: ' strjoin(terms(i0:i1), ', ')];
    else
      lines{end+1} = ['       ' strjoin(terms(i0:i1), ', ')];
    end
  end
end

function h = add_info_box(ax, x, y, lines, st, fsize)
  if nargin < 6 || isempty(fsize)
    fsize = st.font.size_annotation;
  end
  h = text(ax, x, y, lines, ...
    'Units',              'normalized', ...
    'VerticalAlignment',  'top', ...
    'HorizontalAlignment','left', ...
    'FontSize',           fsize, ...
    'Interpreter',        st.interpreter, ...
    'Color',              [0.10, 0.10, 0.10], ...
    'BackgroundColor',    [0.98, 0.98, 0.98]);
  if isprop(h, 'EdgeColor'); set(h, 'EdgeColor', [0.72, 0.72, 0.72]); end
  if isprop(h, 'LineWidth'); set(h, 'LineWidth', 0.6); end
  if isprop(h, 'Margin');    set(h, 'Margin', 4); end
end

function y = box_bottom(h)
  ext = get(h, 'Extent');
  y = ext(2);
end

function tf = boxes_overlap(h1, h2)
  e1 = get(h1, 'Extent');
  e2 = get(h2, 'Extent');
  tf = ~(e1(1)+e1(3) < e2(1) || e2(1)+e2(3) < e1(1) || ...
         e1(2)+e1(4) < e2(2) || e2(2)+e2(4) < e1(2));
end

function s = degree_ordinal(deg)
  deg = round(deg);
  mod100 = mod(deg, 100);
  if mod100 >= 11 && mod100 <= 13
    suf = 'th';
  else
    switch mod(deg, 10)
      case 1
        suf = 'st';
      case 2
        suf = 'nd';
      case 3
        suf = 'rd';
      otherwise
        suf = 'th';
    end
  end
  s = sprintf('%d%s', deg, suf);
end

function s = fs_safe(id)
% Replace filesystem-unsafe characters in the output filename.
  s = regexprep(id, '[/\\:*?"<>|]', '_');
  s = regexprep(s, '__+', '_');
end
