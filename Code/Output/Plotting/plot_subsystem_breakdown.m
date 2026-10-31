function [fig, ax, export_info] = plot_subsystem_breakdown(analysis_case, options)
% plot_subsystem_breakdown  Normalized subsystem mass breakdown vs. exhaust velocity.
%
% [fig, ax, export_info] = plot_subsystem_breakdown(analysis_case)
% [fig, ax, export_info] = plot_subsystem_breakdown(analysis_case, options)
%
% analysis_case — struct with fields:
%   .c_e                  — exhaust velocity sweep vector [m/s]
%   .result.EP_sys_mass   — total EP system mass vector [kg]
%   .result.PPU_mass      — PPU mass [kg]
%   .result.PV_mass       — solar panel (photovoltaic) mass [kg]
%   .result.tank_mass     — propellant tank mass [kg]
%   .result.thruster_mass — thruster mass [kg]
%   .result.structure_mass— structural mass [kg]
%   .result.propellant_mass — propellant mass [kg]
%   .result.mu_EP_min_c_e — c_e at minimum EP system mass fraction
%   .description          — label for this case (used in file name)
%
% Each subsystem is plotted as its fraction of the total EP system mass.
% The denominator (EP system mass) is stated in the axis label.
%
% options — optional struct (same fields as plot_parameter_sweep options).

if nargin < 2; options = struct(); end

st        = opt(options, 'style',   plot_style());
do_export = opt(options, 'export',  false);
visible   = opt(options, 'visible', false);

r     = analysis_case.result;
c_e   = analysis_case.c_e;
m_sys = r.EP_sys_mass;

% Guard against division by zero
if all(m_sys == 0)
  warning('plot_subsystem_breakdown:zero_mass', ...
    'EP system mass is zero; cannot compute fractions.');
  fig = figure('Visible', 'off'); ax = axes('Parent', fig); export_info = struct();
  return;
end

% Subsystems to show (label, data vector)
subsystems = { ...
  'PPU',          r.PPU_mass         ./ m_sys; ...
  'Solar panels', r.PV_mass          ./ m_sys; ...
  'Tank',         r.tank_mass        ./ m_sys; ...
  'Thruster',     r.thruster_mass    ./ m_sys; ...
  'Structure',    r.structure_mass   ./ m_sys; ...
  'Propellant',   r.propellant_mass  ./ m_sys; ...
};

vis_str = 'off';
if visible; vis_str = 'on'; end

fig = figure('Visible', vis_str, ...
             'Color',   [1 1 1], ...
             'Units',   'centimeters', ...
             'Position', [2, 2, st.fig.width_double_cm, st.fig.height_cm]);
ax = axes('Parent', fig);
hold(ax, 'on');

n = size(subsystems, 1);
for i = 1:n
  c_idx = mod(i-1, size(st.palette, 1)) + 1;
  l_idx = mod(i-1, numel(st.linestyles)) + 1;
  plot(ax, c_e, subsystems{i, 2}, st.linestyles{l_idx}, ...
    'Color',       st.palette(c_idx, :), ...
    'LineWidth',   st.line.width_series, ...
    'DisplayName', subsystems{i, 1});
end

% Minimum marker
if isfield(r, 'mu_EP_min_c_e')
  yl = ylim(ax);
  plot(ax, [r.mu_EP_min_c_e, r.mu_EP_min_c_e], [0, max(yl(2), 1)], '--', ...
    'Color',           [0.3 0.3 0.3], ...
    'LineWidth',       st.line.width_reference, ...
    'DisplayName',     'c_e at min. system mass');
end

xlabel(ax, 'Effective exhaust velocity / m/s', 'Interpreter', st.interpreter, ...
       'FontSize', st.font.size_axis_label);
ylabel(ax, 'Mass fraction (ref: EP system mass) / -', 'Interpreter', st.interpreter, ...
       'FontSize', st.font.size_axis_label);
ylim(ax, [0, 1]);

set(ax, 'FontName',             st.font.family, ...
        'FontSize',             st.font.size_tick, ...
        'Box',                  bool_str(st.box.on), ...
        'Color',                [1 1 1], ...
        'TickLabelInterpreter', st.interpreter);

if st.grid.on; grid(ax, 'on'); end

legend(ax, 'Location', 'northeast', ...
           'FontSize',  st.font.size_legend, ...
           'Interpreter', st.interpreter, ...
           'Box',       'off');

hold(ax, 'off');

export_info = struct();
if do_export
  desc     = '';
  if isfield(analysis_case, 'description') && ~isempty(analysis_case.description)
    desc = strrep(strtrim(analysis_case.description), char(10), '_');
    desc = regexprep(desc, '[/\\:*?"<>| ]', '_');
    desc = regexprep(desc, '__+', '_');
  end
  out_path    = fullfile('Output', ['subsystem_breakdown_' desc]);
  export_info = plot_export(fig, out_path, st);
end
end

% ---- Local helpers -----------------------------------------------------
function v = opt(s, field, default)
  if isstruct(s) && isfield(s, field) && ~isempty(s.(field)); v = s.(field); else; v = default; end
end
function s = bool_str(b); if b; s = 'on'; else; s = 'off'; end; end
