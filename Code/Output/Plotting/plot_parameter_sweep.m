function [fig, ax, export_info] = plot_parameter_sweep(sweeps, options)
% plot_parameter_sweep  Multi-series line plot for parameter sweep results.
%
% [fig, ax, export_info] = plot_parameter_sweep(sweeps)
% [fig, ax, export_info] = plot_parameter_sweep(sweeps, options)
%
% sweeps     — struct array, one element per series:
%   sweeps(i).x      row/col vector of x-axis values
%   sweeps(i).y      row/col vector of y-axis values (same length as x)
%   sweeps(i).label  display string for the legend
%   sweeps(i).markers  (optional) struct array of special points to mark:
%     .x, .y, .style (e.g. 'dr')
%
% options — optional struct:
%   .xlabel_str   x-axis label string (default: '')
%   .ylabel_str   y-axis label string (default: '')
%   .ylim         [ymin ymax] (default: auto)
%   .output_file  output path without extension (default: 'Output/parameter_sweep')
%   .style        plot_style() struct (default: plot_style())
%   .export       true/false (default: false — caller requests export explicitly)
%   .visible      true/false (default: false)
%   .show_title   true/false (default: false)
%   .title_str    title string when show_title=true
%   .layout       'single' | 'double' (default: 'single')

if nargin < 2; options = struct(); end

st          = opt(options, 'style',       plot_style());
xlabel_str  = opt(options, 'xlabel_str',  '');
ylabel_str  = opt(options, 'ylabel_str',  '');
output_file = opt(options, 'output_file', 'Output/parameter_sweep');
do_export   = opt(options, 'export',      false);
visible     = opt(options, 'visible',     false);
layout      = opt(options, 'layout',      'single');

xlabel_str = normalize_axis_label(xlabel_str);
ylabel_str = normalize_axis_label(ylabel_str);

fig_w = st.fig.width_single_cm;
if strcmp(layout, 'double'); fig_w = st.fig.width_double_cm; end

vis_str = 'off';
if visible; vis_str = 'on'; end

fig = figure('Visible', vis_str, ...
             'Color',   [1 1 1], ...
             'Units',   'centimeters', ...
             'Position', [2, 2, fig_w, st.fig.height_cm]);
ax = axes('Parent', fig);
hold(ax, 'on');

n = numel(sweeps);
for i = 1:n
  c_idx = mod(i-1, size(st.palette, 1)) + 1;
  l_idx = mod(i-1, numel(st.linestyles)) + 1;
  col   = st.palette(c_idx, :);
  ls    = st.linestyles{l_idx};
  lbl   = '';
  if isfield(sweeps, 'label') && ~isempty(sweeps(i).label)
    lbl = sweeps(i).label;
  end
  plot(ax, sweeps(i).x, sweeps(i).y, ls, ...
    'Color',       col, ...
    'LineWidth',   st.line.width_series, ...
    'DisplayName', lbl);

  % Optional special markers (e.g. design-point or minimum)
  if isfield(sweeps(i), 'markers') && ~isempty(sweeps(i).markers)
    for m = 1:numel(sweeps(i).markers)
      mk = sweeps(i).markers(m);
      ms = 'dk';
      if isfield(mk, 'style'); ms = mk.style; end
      plot(ax, mk.x, mk.y, ms, 'HandleVisibility', 'off');
    end
  end
end

xlabel(ax, xlabel_str, 'Interpreter', st.interpreter, 'FontSize', st.font.size_axis_label);
ylabel(ax, ylabel_str, 'Interpreter', st.interpreter, 'FontSize', st.font.size_axis_label);

set(ax, 'FontName',             st.font.family, ...
        'FontSize',             st.font.size_tick, ...
        'Box',                  bool_str(st.box.on), ...
        'Color',                [1 1 1], ...
        'TickLabelInterpreter', st.interpreter);

if st.grid.on; grid(ax, 'on'); end

if isfield(options, 'ylim') && ~isempty(options.ylim)
  ylim(ax, options.ylim);
end

if st.show_title && isfield(options, 'title_str') && ~isempty(options.title_str)
  title(ax, options.title_str, 'Interpreter', st.interpreter, 'FontSize', st.font.size_title);
end

% Only show legend when at least one series has a non-empty label
has_labels = any(cellfun(@(l) ~isempty(l), {sweeps.label}));
if has_labels
  legend(ax, 'Location', st.legend.location, ...
             'FontSize',  st.font.size_legend, ...
             'Interpreter', st.interpreter, ...
             'Box',       'off');
end

hold(ax, 'off');

export_info = struct();
if do_export
  out_path    = fs_safe_path(output_file);
  export_info = plot_export(fig, out_path, st);
end
end

% ---- Local helpers -----------------------------------------------------
function v = opt(s, field, default)
  if isstruct(s) && isfield(s, field) && ~isempty(s.(field)); v = s.(field); else; v = default; end
end
function s = bool_str(b); if b; s = 'on'; else; s = 'off'; end; end
function lbl = normalize_axis_label(lbl)
  if ~ischar(lbl) || isempty(lbl)
    return;
  end
  tok = regexp(lbl, '^(.+?)\s*\[([^\]]+)\]\s*(\(.*\))?\s*$', 'tokens', 'once');
  if isempty(tok)
    return;
  end

  base = strtrim(tok{1});
  unit = strtrim(tok{2});
  suffix = '';
  if numel(tok) >= 3 && ~isempty(tok{3})
    suffix = [' ' strtrim(tok{3})];
  end
  lbl = sprintf('%s%s / %s', base, suffix, unit);
end

function p = fs_safe_path(p)
  % Sanitise only the filename part, not directory separators
  [d, n, e] = fileparts(p);
  n = regexprep(n, '[/\\:*?"<>|]', '_');
  n = regexprep(n, '__+', '_');
  p = fullfile(d, [n e]);
end
