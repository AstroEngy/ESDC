function info = plot_export(fig, output_path, style)
% plot_export  Export a figure to disk with explicit physical dimensions.
%
% info = plot_export(fig, output_path)
% info = plot_export(fig, output_path, style)
%
% fig          — figure handle owned by the caller; not closed here
% output_path  — full output path WITHOUT extension; extensions are added
%                from style.export.formats / style.export.pdf_enabled
% style        — style struct from plot_style() (optional; defaults applied)
%
% Returns:
%   info.paths   — cell array of paths actually written (with extensions)
%   info.status  — 'ok' | 'partial' | 'failed'
%   info.errors  — cell array of error messages (empty on full success)
%
% Physical dimensions are read from the figure's current Units/Position
% and preserved in the exported file.  The output directory is created
% when missing.  White figure background is applied before export.

if nargin < 3; style = plot_style(); end

info.paths  = {};
info.status = 'ok';
info.errors = {};

% Create output directory
out_dir = fileparts(output_path);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
  [ok, msg] = mkdir(out_dir);
  if ~ok
    info.status = 'failed';
    info.errors{end+1} = sprintf('Cannot create output directory ''%s'': %s', out_dir, msg);
    return;
  end
end

% Read current figure dimensions in centimetres
prev_units = get(fig, 'Units');
set(fig, 'Units', 'centimeters');
pos = get(fig, 'Position');
fig_w = pos(3);
fig_h = pos(4);
set(fig, 'Units', prev_units);

% White background
set(fig, 'Color', [1 1 1]);

% Set paper size to match screen size (preserves layout on export)
set(fig, 'PaperUnits',        'centimeters');
set(fig, 'PaperSize',         [fig_w, fig_h]);
set(fig, 'PaperPosition',     [0, 0, fig_w, fig_h]);
set(fig, 'PaperPositionMode', 'manual');

% PNG export
if any(strcmpi(style.export.formats, 'png'))
  png_path = [output_path '.png'];
  try
    drawnow();  % flush pending draw operations before export
    print(fig, png_path, '-dpng', sprintf('-r%d', style.export.png_dpi), '-painters');
    info.paths{end+1} = png_path;
  catch ex
    info.errors{end+1} = sprintf('PNG export failed for ''%s'': %s', png_path, ex.message);
    info.status = 'partial';
  end
end

% PDF export (optional; requires the toolkit to support -dpdf)
if style.export.pdf_enabled || any(strcmpi(style.export.formats, 'pdf'))
  pdf_path = [output_path '.pdf'];
  try
    print(fig, pdf_path, '-dpdf');
    info.paths{end+1} = pdf_path;
  catch ex
    info.errors{end+1} = sprintf('PDF export failed (optional) for ''%s'': %s', pdf_path, ex.message);
    if strcmp(info.status, 'ok')
      info.status = 'partial';
    end
  end
end

if ~isempty(info.errors) && isempty(info.paths)
  info.status = 'failed';
end
end
