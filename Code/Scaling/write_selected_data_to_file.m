## -*- texinfo -*-
## @deftypefn {} {} write_selected_data_to_file (@var{x}, @var{y}, @var{filename}, @var{padbit})
## @deftypefnx {} {} write_selected_data_to_file (@var{x}, @var{y}, @var{filename}, @var{padbit}, @var{debug_mode})
## Write scaled data and fitted curve to CSV file with visualization.
##
## Processes x-y data pairs by sorting, fitting a polynomial curve, and writing
## both the raw data and fitted curve to a comma-separated value (CSV) file.
## Also generates a visualization graph of the data and fit.
##
## @strong{Inputs:}
## @table @var
## @item x
## Numeric vector or array of independent variable values (e.g., mass, power).
## Must have the same number of elements as @var{y}. Non-empty.
##
## @item y
## Numeric vector or array of dependent variable values corresponding to @var{x}.
## Must have the same number of elements as @var{x}. Non-empty.
##
## @item filename
## String specifying the output CSV file path (absolute or relative).
## If the file exists, it will be overwritten.
##
## @item padbit
## Logical flag (0 or 1) controlling zero-padding behavior:
## @itemize
## @item 0 - Use data as-is without padding
## @item 1 - Prepend a zero x-value point with the first y-value
## @end itemize
##
## @item debug_mode
## Optional logical flag (0 or 1) to enable detailed debug output.
## Default is 0 (off).
## @end table
##
## @strong{Outputs:}
## None (empty return).
##
## @strong{Side Effects:}
## @itemize
## @item Creates or overwrites the specified CSV file with two sections:
##   - Raw data sorted by x-values (2 rows: y-values, x-values)
##   - Fitted curve data with 100 interpolated points (2 rows: y-fit, x-fit)
## @item Displays confirmation message to console showing updated filename
## @item Generates a visualization graph via plot_scaling_law()
## @end itemize
##
## @strong{Assumptions and Special Cases:}
## @itemize
## @item If only a single data point is provided, it is duplicated with doubled
##   x and y values to enable fitting (creates linear scaling).
## @item Data is automatically sorted by x-values before processing.
## @item Polynomial fitting degree is automatically determined by data_fitting().
## @item CSV format uses comma delimiters with two row blocks (data, then fit).
## @end itemize
##
## @strong{Error Conditions:}
## @itemize
## @item Fails if @var{x} and @var{y} have different lengths
## @item Fails if @var{filename} path is invalid or not writable
## @item May produce unexpected results if @var{x} or @var{y} contain NaN or Inf
## @end itemize
##
## @strong{Example:}
## @example
## x = [1, 2, 3, 4, 5];
## y = [2.1, 4.0, 5.9, 8.2, 10.1];
## write_selected_data_to_file(x, y, 'scaling_data.csv', 0);
## @end example
##
## @seealso{sort_data_to_x, data_fitting, plot_scaling_law}
## @end deftypefn

% write_selected_data_to_file  Fit data and write a YAML scaling law file.
%
% write_selected_data_to_file(x, y, filename, padbit)
% write_selected_data_to_file(x, y, filename, padbit, debug_mode)
% write_selected_data_to_file(x, y, filename, padbit, debug_mode, metadata)
%
% Fits a polynomial to (x, y), evaluates it on a dense grid, and writes
% the result as a YAML scaling law file.  No CSV is written.
%
% filename  — path used to derive the YAML stem; conventionally ends in
%             '.csv' (legacy) or '.yaml'; the YAML is written at stem+'.yaml'.
% metadata  — optional struct with extra classification fields:
%               .propellant_display — original chemical name (may contain '/')
%               .orbit_type, .system, .technology, .component, ...
function [] = write_selected_data_to_file(x, y, filename, padbit, debug_mode, metadata)
    if nargin < 5; debug_mode = 0; end
    if nargin < 6; metadata   = struct(); end

    [data] = sort_data_to_x(x, y, padbit);

    if size(data, 2) == 1
      data = [data(:,1), 2.*data(:,1)];
    end

    % Polynomial curve fitting — also returns fit quality metrics
    [data_fit, fit_metrics] = data_fitting(data);

    % Validate
    if isempty(data) || any(~isfinite(data(:)))
        error('write_selected_data_to_file: data contains empty, NaN, or Inf values');
    end
    if isempty(data_fit) || any(~isfinite(data_fit(:))) || ndims(data_fit) ~= 2 || size(data_fit,1) ~= 2
        warning('write_selected_data_to_file:bad_fit', '%s skipped: invalid fit data', filename);
        return;
    end
    if ~ischar(filename) && ~isstring(filename)
        error('write_selected_data_to_file: filename must be a string');
    end

    % Derive YAML output path from the (possibly .csv) filename
    [file_dir, stem_name, ~] = fileparts(filename);
    if ~isempty(file_dir) && ~exist(file_dir, 'dir')
        mkdir(file_dir);
    end
    yaml_path = fullfile(file_dir, [stem_name '.yaml']);

    % Build law struct
    law = build_law_struct(stem_name, data, data_fit, fit_metrics, metadata);

    % Write YAML (atomic, via temp file)
    scaling_law_write_yaml(yaml_path, law);

    % Visualization — all scaling laws receive a plot; export is best-effort
    try
      plot_opts = struct('output_dir', 'Output/Scaling', 'visible', false);
      fig = plot_scaling_law(law, plot_opts);
      close(fig);  % must close; unclosed figures accumulate and crash Magick
    catch ex
      warning('write_selected_data_to_file:plot_failed', ...
        'Visualization not generated for %s: %s', yaml_path, ex.message);
    end

    disp([yaml_path ' updated']);
end

% -------------------------------------------------------------------------
function law = build_law_struct(stem, data, data_fit, fit_metrics, metadata)
  [category, orbit, sys, tech, comp, prop_safe, fx, fy] = parse_stem_local(stem);

  % Prefer caller-supplied classification over stem-parsed values
  if isfield(metadata, 'orbit_type'); orbit = metadata.orbit_type; end
  if isfield(metadata, 'system');     sys   = metadata.system;     end
  if isfield(metadata, 'technology'); tech  = metadata.technology; end
  if isfield(metadata, 'component');  comp  = metadata.component;  end

  law_id = regexprep(strrep(stem, ' ', '_'), '[()]', '_');
  law_id = regexprep(law_id, '__+', '_');

  law.schema_version          = 1;
  law.id                      = law_id;
  law.title                   = strrep(stem, '_', ' ');
  law.lifecycle.status        = lifecycle_from_cat(category);
  law.classification.category = category;
  if ~isempty(orbit); law.classification.orbit_type = orbit; end
  if ~isempty(sys);   law.classification.system     = sys;   end
  if ~isempty(tech);  law.classification.technology = tech;  end
  if ~isempty(comp);  law.classification.component  = comp;  end
  % Propellant: keep display name if provided, safe ID otherwise
  if isfield(metadata, 'propellant_display')
    law.classification.propellant_display = metadata.propellant_display;
  elseif ~isempty(prop_safe)
    law.classification.propellant = prop_safe;
  end

  law.input.quantity          = fx;
  law.input.unit              = unit_for(fx);
  law.output.quantity         = fy;
  law.output.unit             = unit_for(fy);

  law.model.kind              = 'interpolation';
  law.model.method            = 'linear_on_polynomial_fit';
  law.model.samples.n         = size(data, 2);
  law.model.samples.provenance = 'database';
  law.model.samples.input     = data(2,:);
  law.model.samples.output    = data(1,:);
  law.model.fit.n             = size(data_fit, 2);
  law.model.fit.x             = data_fit(2,:);
  law.model.fit.y             = data_fit(1,:);
  if isstruct(fit_metrics) && isfield(fit_metrics, 'poly_degree')
    law.model.poly_degree = fit_metrics.poly_degree;
  end
  if isstruct(fit_metrics) && isfield(fit_metrics, 'poly_coeffs')
    law.model.poly_coeffs = fit_metrics.poly_coeffs;
  end

  law.domains.numerical.min   = min(data_fit(2,:));
  law.domains.numerical.max   = max(data_fit(2,:));
  law.domains.hardware_supported.status = 'unknown';
  law.domains.hardware_supported.notes  = 'Hardware validation not assessed.';

  law.evaluation.out_of_domain            = 'extrapolate';
  law.evaluation.outside_hardware_support = 'warn';

  if isstruct(fit_metrics) && isfield(fit_metrics, 'r_squared')
    fm.status             = 'computed';
    fm.evaluation_basis   = fit_metrics.evaluation_basis;
    fm.poly_degree        = fit_metrics.poly_degree;
    fm.n_observations     = fit_metrics.n_observations;
    fm.df_residual        = fit_metrics.df_residual;
    fm.rmse               = fit_metrics.rmse;
    fm.r_squared          = fit_metrics.r_squared;
    fm.r_squared_status   = fit_metrics.r_squared_status;
    if isfield(fit_metrics, 'poly_coeffs'); fm.poly_coeffs = fit_metrics.poly_coeffs; end
    law.quality.fit_metrics = fm;
  else
    law.quality.fit_metrics.status = 'not_available';
  end

  law.provenance.generated_by = 'write_selected_data_to_file + data_fitting';
  law.provenance.generator_version = '2';
end

function [cat, orbit, sys, tech, comp, prop, fx, fy] = parse_stem_local(stem)
  cat = 'unknown'; orbit = ''; sys = ''; tech = ''; comp = ''; prop = ''; fx = 'unknown'; fy = 'unknown';
  if length(stem) < 9 || ~strcmp(stem(1:8), 'scaling_'); return; end
  rest = stem(9:end);

  if strncmp(rest, 'spacecraft_', 11)
    cat  = 'spacecraft_system';
    rest = rest(12:end);
    pidx = strfind(rest, '_parameter_');
    if isempty(pidx); return; end
    orbit = rest(1:pidx(1)-1);
    [fx, fy] = to_split(rest(pidx(1)+11:end));
    return;
  end

  known = {'attitude_control','communication','energy_storage','power_generation', ...
           'propulsion_system','structure','thermal'};
  for k = 1:numel(known)
    if strncmp(rest, [known{k} '_'], length(known{k})+1)
      sys  = known{k}; cat = sys;
      rest = rest(length(known{k})+2:end);
      break;
    end
  end

  widx = strfind(rest, '_with_propellant_');
  if ~isempty(widx)
    prefix = rest(1:widx(1)-1);
    tail   = rest(widx(1)+17:end);
    [tech, comp] = first_split(prefix);
    midx = strfind(tail, '_mass_to_');
    if ~isempty(midx)
      prop = tail(1:midx(1)-1);
      [fx, fy] = to_split(tail(midx(1)+1:end));
    end
    return;
  end
  midx = strfind(rest, '_mass_to_');
  if ~isempty(midx)
    [tech, comp] = first_split(rest(1:midx(1)-1));
    [fx, fy] = to_split(rest(midx(1)+1:end));
    return;
  end
  [fx, fy] = to_split(rest);
end

function [a, b] = first_split(s)
  i = strfind(s, '_');
  if isempty(i); a = s; b = ''; else; a = s(1:i(1)-1); b = s(i(1)+1:end); end
end

function [fx, fy] = to_split(tail)
  i = strfind(tail, '_to_');
  if isempty(i); fx = tail; fy = 'unknown'; else; fx = tail(1:i(1)-1); fy = tail(i(1)+4:end); end
end

function s = lifecycle_from_cat(cat)
  if any(strcmp(cat, {'spacecraft_system','propulsion_system','power_generation'}))
    s = 'active';
  else
    s = 'inactive';
  end
end

function unit = unit_for(fname)
  m.mass='kg'; m.mass_total='kg'; m.mass_payload='kg'; m.mass_total_dry='kg'; m.mass_propellant='kg';
  m.power_total='W'; m.power='W'; m.power_jet='W'; m.power_nom='W'; m.power_max='W'; m.power_nominal='W';
  m.thrust='N'; m.c_e='m/s'; m.volume='m3'; m.volume_box='m3';
  m.size_x='m'; m.size_y='m'; m.size_h='m';
  m.efficiency='dimensionless'; m.TRL='dimensionless';
  m.massflow='kg/s'; m.isp='s'; m.area='m2'; m.pressure='Pa';
  if length(fname) > 9 && strcmp(fname(1:9), 'fraction_')
    unit = 'dimensionless';
  elseif isfield(m, fname)
    unit = m.(fname);
  else
    unit = 'unknown';
  end
end


