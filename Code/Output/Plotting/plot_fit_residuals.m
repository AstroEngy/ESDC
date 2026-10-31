function [fig, ax, export_info] = plot_fit_residuals(law, options)
% plot_fit_residuals  Plot fit residuals for a scaling law.
%
% [fig, ax, export_info] = plot_fit_residuals(law)
% [fig, ax, export_info] = plot_fit_residuals(law, options)
%
% Residuals are computed at the original database observation points:
%
%   residual = observed_output - predicted_output
%   predicted = interp1(law.model.fit.x, law.model.fit.y, obs_input)
%
% The residual sign convention: positive residual = model under-predicts.
% Residual units are the output quantity units.
%
% options — same fields as plot_scaling_law() options struct.

if nargin < 2; options = struct(); end

output_dir = opt(options, 'output_dir', 'Output/Scaling');
st         = opt(options, 'style',      plot_style());
do_export  = opt(options, 'export',     true);
visible    = opt(options, 'visible',    false);

% ---- Compute residuals at observation points ---------------------------
x_obs = law.model.samples.input;
y_obs = law.model.samples.output;
y_pred = interp1(law.model.fit.x, law.model.fit.y, x_obs, 'linear', 'extrap');
residuals = y_obs - y_pred;

% ---- Axis labels -------------------------------------------------------
in_q  = safe_get(law.input,  'quantity', 'unknown');
in_u  = safe_get(law.input,  'unit',     '');
out_q = safe_get(law.output, 'quantity', 'unknown');
out_u = safe_get(law.output, 'unit',     '');

[in_lbl, in_unit]   = plot_quantity_label(in_q,  in_u);
[~,      out_unit2] = plot_quantity_label(out_q, out_u);
if isempty(out_unit2) || strcmp(out_unit2, '?')
  out_unit2 = out_u;
end
if isempty(out_unit2) || any(strcmp(out_unit2, {'unknown','?',''}))
  res_lbl = 'Residual (observed - predicted)';
else
  res_lbl = sprintf('Residual (observed - predicted) / %s', out_unit2);
end

x_axis_str = axis_label(in_lbl, in_unit);

% ---- Figure ------------------------------------------------------------
vis_str = 'off';
if visible; vis_str = 'on'; end

fig = figure('Visible', vis_str, ...
             'Color',   [1 1 1], ...
             'Units',   'centimeters', ...
             'Position', [2, 2, st.fig.width_single_cm, st.fig.height_cm]);
ax = axes('Parent', fig);
hold(ax, 'on');

% Zero reference line (behind data)
xl = [min(x_obs), max(x_obs)];
if xl(1) == xl(2); xl = xl + [-1, 1]; end
plot(ax, xl, [0 0], '-', ...
  'Color',           st.color.zero_line, ...
  'LineWidth',       st.line.width_reference, ...
  'HandleVisibility','off');

% Residual points
plot(ax, x_obs, residuals, ...
  st.marker.style_obs, ...
  'MarkerSize',      st.marker.size_obs, ...
  'Color',           st.color.observations, ...
  'MarkerFaceColor', st.color.observations, ...
  'LineStyle',       'none', ...
  'DisplayName',     build_obs_label(numel(x_obs)));

xlabel(ax, x_axis_str,  'Interpreter', st.interpreter, 'FontSize', st.font.size_axis_label);
ylabel(ax, res_lbl,     'Interpreter', st.interpreter, 'FontSize', st.font.size_axis_label);

set(ax, 'FontName',             st.font.family, ...
        'FontSize',             st.font.size_tick, ...
        'Box',                  bool_str(st.box.on), ...
        'Color',                [1 1 1], ...
        'TickLabelInterpreter', st.interpreter);

if st.grid.on; grid(ax, 'on'); end

legend(ax, 'Location', st.legend.location, ...
           'FontSize',  st.font.size_legend, ...
           'Interpreter', st.interpreter, ...
           'Box',       'off');

hold(ax, 'off');

% ---- Export ------------------------------------------------------------
export_info = struct();
if do_export
  law_id   = safe_get(law, 'id', 'scaling_unknown');
  out_path = fullfile(output_dir, [fs_safe(law_id) '_residuals']);
  export_info = plot_export(fig, out_path, st);
end
end

% ---- Local helpers -----------------------------------------------------
function v = opt(s, field, default)
  if isstruct(s) && isfield(s, field) && ~isempty(s.(field)); v = s.(field); else; v = default; end
end
function v = safe_get(s, field, default)
  if isstruct(s) && isfield(s, field); v = s.(field); else; v = default; end
end
function s = bool_str(b); if b; s = 'on'; else; s = 'off'; end; end
function lbl = axis_label(d, u)
  if isempty(u) || any(strcmp(u, {'unknown','?',''})); lbl = d; else; lbl = sprintf('%s / %s', d, u); end
end

function s = build_obs_label(n)
  if n == 1
    s = '1 hardware data point';
  else
    s = sprintf('%d hardware data points', n);
  end
end

function s = fs_safe(id)
  s = regexprep(id, '[/\\:*?"<>|]', '_');
  s = regexprep(s, '__+', '_');
end
