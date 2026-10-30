% migrate_csv_to_yaml  Convert all legacy scaling CSV files to YAML format.
%
% report = migrate_csv_to_yaml()
%   Scans Database/Scaling/*.csv and writes a *.yaml companion for each.
%   Existing YAML files are skipped unless 'force' is true.
%
% report = migrate_csv_to_yaml('force', true)
%   Overwrite existing YAML files.
%
% report = migrate_csv_to_yaml('dir', '/path/to/Scaling')
%   Scan a custom directory instead of Database/Scaling.
%
% Returns struct with: migrated, skipped, failed, messages, dir.
%
% HOW TO USE
%   Run once after checkout to migrate all CSVs:
%     report = migrate_csv_to_yaml();
%
%   Then verify a sample law loads:
%     law = scaling_law_load('Database/Scaling/scaling_spacecraft_Low Earth_parameter_mass_total_to_fraction_mass_payload');
%
%   Re-run with force=true after database regeneration:
%     migrate_csv_to_yaml('force', true);
%
% Inactive selectors (attitude_control, communication, etc.) are migrated
% with lifecycle.status = 'inactive' to preserve planned-future status.
%
% IMPORTANT
%   Do not delete legacy CSVs yet — they serve as the fallback for
%   scaling_law_load until the migration is fully verified in production.
%   Remove CSVs only after all consumers have been confirmed working with YAML.
function report = migrate_csv_to_yaml(varargin)
  scaling_dir = 'Database/Scaling';
  force = false;
  for k = 1:2:numel(varargin)
    switch lower(varargin{k})
      case 'force'; force = logical(varargin{k+1});
      case 'dir';   scaling_dir = varargin{k+1};
    end
  end

  csv_files = dir(fullfile(scaling_dir, '*.csv'));

  % NOTE: One file cannot be migrated automatically:
  %   scaling_propulsion_system_arcjet_thruster_with_propellant_H2/<...>.csv
  % The propellant name "H2/N2 mixtures..." contains a forward-slash that
  % created a subdirectory on the original file system. It falls back to CSV
  % at runtime via scaling_law_load's legacy fallback. To fix, rename the
  % propellant entry in the reference database to remove the '/' character.

  report.migrated = 0;
  report.skipped  = 0;
  report.failed   = 0;
  report.messages = {};
  report.dir      = scaling_dir;

  for i = 1:numel(csv_files)
    csv_path  = fullfile(csv_files(i).folder, csv_files(i).name);
    stem      = csv_files(i).name(1:end-4);  % strip .csv
    yaml_path = fullfile(scaling_dir, [stem '.yaml']);

    if exist(yaml_path, 'file') && ~force
      report.skipped = report.skipped + 1;
      continue;
    end

    try
      data = dlmread(csv_path, ',');
      if size(data, 1) < 4
        error('CSV has only %d rows (expected 4)', size(data, 1));
      end

      law = build_law(stem, csv_path, data);
      scaling_law_write_yaml(yaml_path, law);

      report.migrated = report.migrated + 1;
    catch err
      report.failed = report.failed + 1;
      msg = sprintf('FAILED %s: %s', csv_files(i).name, err.message);
      report.messages{end+1} = msg;
      fprintf('%s\n', msg);
    end
  end

  fprintf('\nMigration complete: %d migrated, %d skipped, %d failed (dir: %s)\n', ...
          report.migrated, report.skipped, report.failed, scaling_dir);
end

% =========================================================================
function law = build_law(stem, csv_path, data)
  % Rows: 1=y_raw, 2=x_raw, 3=y_fit(dense), 4=x_fit(dense)
  x_raw = data(2,:);
  y_raw = data(1,:);
  x_fit = data(4,:);
  y_fit = data(3,:);

  [category, orbit_type, sys, tech, comp, propellant, field_x, field_y] = parse_stem(stem);

  law_id = regexprep(strrep(stem, ' ', '_'), '[()]', '_');
  law_id = regexprep(law_id, '__+', '_');

  law.schema_version          = 1;
  law.id                      = law_id;
  law.title                   = build_title(category, orbit_type, tech, comp, propellant, field_x, field_y);
  law.lifecycle.status        = lifecycle_status(category, sys);
  law.classification.category = category;
  if ~isempty(orbit_type); law.classification.orbit_type = orbit_type; end
  if ~isempty(sys);        law.classification.system     = sys;        end
  if ~isempty(tech);       law.classification.technology = tech;       end
  if ~isempty(comp);       law.classification.component  = comp;       end
  if ~isempty(propellant); law.classification.propellant = propellant; end
  law.input.quantity          = field_x;
  law.input.unit              = field_to_unit(field_x);
  law.output.quantity         = field_y;
  law.output.unit             = field_to_unit(field_y);
  law.model.kind              = 'interpolation';
  law.model.method            = 'linear_on_polynomial_fit';
  law.model.samples.n         = numel(x_raw);
  law.model.samples.provenance = 'legacy_csv';
  law.model.samples.input     = x_raw;
  law.model.samples.output    = y_raw;
  law.model.fit.n             = numel(x_fit);
  law.model.fit.x             = x_fit;
  law.model.fit.y             = y_fit;
  law.domains.numerical.min   = min(x_fit);
  law.domains.numerical.max   = max(x_fit);
  law.domains.hardware_supported.status = 'unknown';
  law.domains.hardware_supported.notes  = ...
    'Hardware validation not assessed. Range derived from legacy CSV sample span.';
  law.evaluation.out_of_domain            = 'extrapolate';
  law.evaluation.outside_hardware_support = 'warn';
  law.quality.fit_metrics.status = 'not_available';
  law.quality.fit_metrics.notes  = ...
    'Polynomial fit quality not recorded during original CSV generation.';
  law.provenance.legacy_file     = strrep(csv_path, '\', '/');
  law.provenance.migration_notes = ...
    'Migrated by migrate_csv_to_yaml.m. Row convention: row1=y_raw, row2=x_raw, row3=y_fit, row4=x_fit.';
end

% =========================================================================
function [cat, orbit, sys, tech, comp, propellant, fx, fy] = parse_stem(stem)
  cat = 'unknown'; orbit = ''; sys = ''; tech = ''; comp = ''; propellant = ''; fx = 'unknown'; fy = 'unknown';

  if length(stem) < 9 || ~strcmp(stem(1:8), 'scaling_')
    return;
  end
  rest = stem(9:end);

  if strncmp(rest, 'spacecraft_', 11)
    cat  = 'spacecraft_system';
    rest = rest(12:end);
    pidx = strfind(rest, '_parameter_');
    if isempty(pidx); return; end
    orbit = rest(1:pidx(1)-1);
    [fx, fy] = split_to(rest(pidx(1)+11:end));
    return;
  end

  known_sys = {'attitude_control', 'communication', 'energy_storage', ...
               'power_generation', 'propulsion_system', 'structure', 'thermal'};
  for k = 1:numel(known_sys)
    pfx = [known_sys{k} '_'];
    if strncmp(rest, pfx, length(pfx))
      sys  = known_sys{k};
      cat  = sys;
      rest = rest(length(pfx)+1:end);
      break;
    end
  end

  % Check for propellant subdivision: _with_propellant_
  widx = strfind(rest, '_with_propellant_');
  if ~isempty(widx)
    prefix = rest(1:widx(1)-1);
    tail   = rest(widx(1)+17:end);
    [tech, comp] = split_first(prefix);
    midx = strfind(tail, '_mass_to_');
    if ~isempty(midx)
      propellant = tail(1:midx(1)-1);
      [fx, fy] = split_to(tail(midx(1)+1:end));
    end
    return;
  end

  % Generic component: tech_comp_mass_to_y
  midx = strfind(rest, '_mass_to_');
  if ~isempty(midx)
    [tech, comp] = split_first(rest(1:midx(1)-1));
    [fx, fy] = split_to(rest(midx(1)+1:end));
    return;
  end

  % Fallback: just extract field_x/y from _to_
  [fx, fy] = split_to(rest);
end

function [a, b] = split_first(str)
  idx = strfind(str, '_');
  if isempty(idx)
    a = str; b = '';
  else
    a = str(1:idx(1)-1);
    b = str(idx(1)+1:end);
  end
end

function [fx, fy] = split_to(tail)
  idx = strfind(tail, '_to_');
  if isempty(idx)
    fx = tail; fy = 'unknown';
  else
    fx = tail(1:idx(1)-1);
    fy = tail(idx(1)+4:end);
  end
end

% =========================================================================
function status = lifecycle_status(category, sys)
  active_cats = {'spacecraft_system', 'propulsion_system', 'power_generation'};
  if any(strcmp(category, active_cats))
    status = 'active';
  else
    status = 'inactive';
  end
end

% =========================================================================
function title = build_title(cat, orbit, tech, comp, prop, fx, fy)
  fx_h = strrep(fx, '_', ' ');
  fy_h = strrep(fy, '_', ' ');
  if strcmp(cat, 'spacecraft_system')
    title = sprintf('%s spacecraft: %s to %s', orbit, fx_h, fy_h);
  else
    parts = {};
    if ~isempty(tech); parts{end+1} = tech; end
    if ~isempty(comp); parts{end+1} = comp; end
    if ~isempty(prop); parts{end+1} = ['propellant ' prop]; end
    title = sprintf('%s: %s to %s', strjoin(parts, ' '), fx_h, fy_h);
  end
end

% =========================================================================
function unit = field_to_unit(fname)
  lookup.mass         = 'kg';  lookup.mass_total       = 'kg';
  lookup.mass_payload = 'kg';  lookup.mass_total_dry   = 'kg';
  lookup.mass_propellant = 'kg';
  lookup.power_total  = 'W';   lookup.power_payload    = 'W';
  lookup.power        = 'W';   lookup.power_jet        = 'W';
  lookup.power_nom    = 'W';   lookup.power_max        = 'W';
  lookup.power_nominal = 'W';
  lookup.thrust       = 'N';   lookup.c_e              = 'm/s';
  lookup.volume       = 'm3';  lookup.volume_box       = 'm3';
  lookup.size_x       = 'm';   lookup.size_y           = 'm';
  lookup.size_h       = 'm';
  lookup.efficiency   = 'dimensionless';
  lookup.TRL          = 'dimensionless';
  lookup.massflow     = 'kg/s';
  lookup.isp          = 's';
  lookup.delta_v      = 'm/s';
  lookup.impulse_tot  = 'N*s'; lookup.total_impulse    = 'N*s';
  lookup.minimum_impulse_bit = 'N*s';
  lookup.capacity     = 'Ah';
  lookup.energy       = 'Wh';  lookup.energy_density   = 'Wh/kg';
  lookup.specific_energy = 'Wh/kg';
  lookup.voltage_nominal = 'V';
  lookup.area         = 'm2';
  lookup.pressure     = 'Pa';

  if length(fname) > 9 && strcmp(fname(1:9), 'fraction_')
    unit = 'dimensionless';
    return;
  end
  if isfield(lookup, fname)
    unit = lookup.(fname);
  else
    unit = 'unknown';
  end
end
