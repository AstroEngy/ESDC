function s = plot_style(varargin)
% plot_style  Shared dissertation figure style configuration.
%
% s = plot_style()              — default style struct
% s = plot_style(key, val, ...) — override dotted fields from defaults
%
% -----------------------------------------------------------------------
% DEFAULT VALUES (documented here to avoid implicit assumptions)
% -----------------------------------------------------------------------
% Figure dimensions (centimetres):
%   s.fig.width_single_cm = 11.0  single-column width (fits long y-axis labels)
%   s.fig.width_double_cm = 17.0  double-column width
%   s.fig.height_cm       = 6.0   default height
%
% Font (points):
%   s.font.family          = 'Helvetica'
%   s.font.size_axis_label = 9
%   s.font.size_tick       = 8
%   s.font.size_legend     = 7.5
%   s.font.size_annotation = 7.5
%   s.font.size_title      = 10
%
% Lines and markers:
%   s.line.width_fit       = 1.5
%   s.line.width_series    = 1.5
%   s.line.width_reference = 0.75
%   s.marker.size_obs      = 4
%   s.marker.style_obs     = 'o'
%
% Colours:
%   s.color.observations   = [0.15 0.15 0.15]  dark grey
%   s.color.fit            = [0.12 0.47 0.71]  blue
%   s.color.extrapolation  = [0.70 0.70 0.70]  light grey
%   s.color.zero_line      = [0.50 0.50 0.50]  mid grey
%
%   s.palette    7x3 colorblind-friendly palette (Wong 2011)
%   s.linestyles 7-element cell of line style strings
%   s.markerstyles 7-element cell of marker style strings
%
% Export:
%   s.export.formats     = {'png'}
%   s.export.png_dpi     = 300
%   s.export.pdf_enabled = false
%
% Rendering:
%   s.interpreter      = 'none'  — safe for identifiers with underscores
%   s.show_title       = false   — caption supplies context in dissertation
%   s.legend.location  = 'northeast'
%   s.grid.on          = true
%   s.grid.minor       = false
%   s.box.on           = false
%
% To override a single nested field use dotted-key notation:
%   s = plot_style('fig.height_cm', 9, 'export.pdf_enabled', true);
% -----------------------------------------------------------------------

% Figure dimensions
s.fig.width_single_cm  = 11.0;  % wide enough for long y-axis labels at 9 pt
s.fig.width_double_cm  = 17.0;
s.fig.height_cm        = 8.0;

% Font
s.font.family          = 'Helvetica';
s.font.size_axis_label = 9;
s.font.size_tick       = 8;
s.font.size_legend     = 7.5;
s.font.size_annotation = 7.5;
s.font.size_title      = 10;

% Lines and markers
s.line.width_fit       = 1.5;
s.line.width_series    = 1.5;
s.line.width_reference = 0.75;
s.marker.size_obs      = 4;
s.marker.style_obs     = 'o';

% Colours
s.color.observations   = [0.15, 0.15, 0.15];
s.color.fit            = [0.12, 0.47, 0.71];
s.color.extrapolation  = [0.70, 0.70, 0.70];
s.color.zero_line      = [0.50, 0.50, 0.50];

% 7-colour colorblind-friendly palette (Wong 2011, with extensions)
s.palette = [...
  0.00, 0.45, 0.70;   % blue
  0.90, 0.62, 0.00;   % amber
  0.00, 0.62, 0.45;   % green
  0.80, 0.40, 0.00;   % vermillion
  0.35, 0.70, 0.90;   % sky blue
  0.94, 0.89, 0.26;   % yellow
  0.80, 0.60, 0.70];  % pink

% Line and marker rotation for multi-dataset plots
s.linestyles   = {'-', '--', ':', '-.', '-', '--', ':'};
s.markerstyles = {'o', 's', '^', 'd', 'v', '<', '>'};

% Export
s.export.formats     = {'png'};
s.export.png_dpi     = 300;
s.export.pdf_enabled = false;

% Rendering
s.interpreter      = 'none';
s.show_title       = false;
s.legend.location  = 'northeast';
s.grid.on          = true;
s.grid.minor       = false;
s.box.on           = false;

% Apply key-value overrides (dotted paths: 'fig.height_cm', 9)
for k = 1:2:numel(varargin)
  parts = strsplit(varargin{k}, '.');
  switch numel(parts)
    case 1
      s.(parts{1}) = varargin{k+1};
    case 2
      s.(parts{1}).(parts{2}) = varargin{k+1};
    case 3
      s.(parts{1}).(parts{2}).(parts{3}) = varargin{k+1};
    otherwise
      warning('plot_style:deep_key', 'Key ''%s'' has unsupported depth; ignored.', varargin{k});
  end
end
end
