% scaling_law_load  Load a scaling law from YAML (with legacy CSV fallback).
%
% law = scaling_law_load(path_stem)
%   Load the scaling law whose YAML file is path_stem + '.yaml'.
%   If no YAML is found, attempts path_stem + '.csv' and converts on-the-fly
%   (legacy fallback; migrate with migrate_csv_to_yaml to eliminate this).
%   Results are cached by path_stem — repeated calls for the same stem are free.
%
% law = scaling_law_load(path_stem, 'reload', true)
%   Bypass cache and reload from disk (use after updating a YAML file).
%
% The returned struct always contains:
%   law.schema_version         integer 1
%   law.id                     stable string identifier
%   law.lifecycle.status       'active' | 'inactive' | 'planned' | 'deprecated'
%   law.classification.*       category, orbit_type / system / technology / component
%   law.input.quantity / unit  input parameter name and unit
%   law.output.quantity / unit output parameter name and unit
%   law.model.fit.x            dense x grid (numeric row vector, N points)
%   law.model.fit.y            dense y values (numeric row vector, N points)
%   law.model.samples.input    sparse raw x values
%   law.model.samples.output   sparse raw y values
%   law.domains.numerical.min/max  evaluation domain
%   law.evaluation.*           policy fields
%   law.quality.fit_metrics.*  fit quality metadata
%   law.provenance.*           source file and migration notes
%
% Raises an error when neither YAML nor CSV is found.
% Emits a warning (not an error) when validation fails on a loaded file.
function law = scaling_law_load(path_stem, varargin)
  reload = false;
  for k = 1:2:numel(varargin)
    if strcmpi(varargin{k}, 'reload')
      reload = logical(varargin{k+1});
    end
  end

  cache_key = path_stem;

  if ~reload
    [cached, found] = scaling_law_cache('get', cache_key);
    if found
      law = cached;
      return;
    end
  end

  % Resolve YAML and CSV candidate paths
  yaml_path = resolve_path(path_stem, '.yaml');
  csv_path  = resolve_path(path_stem, '.csv');

  if exist(yaml_path, 'file')
    law = load_from_yaml(yaml_path);
  else
    error('scaling_law_load:not_found', ...
          ['Scaling law YAML not found: %s\n' ...
           'Run update_scaling_model(1) to regenerate all scaling laws from the database.'], ...
          yaml_path);
  end

  [ok, msgs] = scaling_law_validate(law);
  if ~ok
    warning('scaling_law_load:invalid', ...
            'Scaling law ''%s'' has validation issues:\n  %s', ...
            path_stem, strjoin(msgs, '\n  '));
  end

  scaling_law_cache('set', cache_key, law);
end

% -------------------------------------------------------------------------
function p = resolve_path(stem, ext)
  [d, n, old_ext] = fileparts(stem);
  if ~isempty(old_ext)
    p = fullfile(d, [n ext]);
  else
    p = [stem ext];
  end
end

% -------------------------------------------------------------------------
function law = load_from_yaml(yaml_path)
  raw = esdc_yaml.read(yaml_path);

  % Ensure fit arrays are numeric row vectors (esdc_yaml may return cell for inline lists)
  if isfield(raw, 'model') && isfield(raw.model, 'fit')
    raw.model.fit.x = to_row_vec(raw.model.fit.x);
    raw.model.fit.y = to_row_vec(raw.model.fit.y);
  end
  if isfield(raw, 'model') && isfield(raw.model, 'samples')
    if isfield(raw.model.samples, 'input')
      raw.model.samples.input  = to_row_vec(raw.model.samples.input);
    end
    if isfield(raw.model.samples, 'output')
      raw.model.samples.output = to_row_vec(raw.model.samples.output);
    end
  end

  law = raw;
end

% -------------------------------------------------------------------------
function law = load_from_csv(csv_path)
  data = dlmread(csv_path, ',');

  [~, stem] = fileparts(csv_path);
  law_id    = regexprep(strrep(stem, ' ', '_'), '[()]', '_');

  law.schema_version                = 1;
  law.id                            = law_id;
  law.title                         = strrep(stem, '_', ' ');
  law.lifecycle.status              = 'active';
  law.classification.category       = 'legacy';
  law.input.quantity                = 'unknown';
  law.input.unit                    = 'unknown';
  law.output.quantity               = 'unknown';
  law.output.unit                   = 'unknown';
  law.model.kind                    = 'interpolation';
  law.model.method                  = 'linear_on_polynomial_fit';
  law.model.samples.input           = data(2,:);
  law.model.samples.output          = data(1,:);
  law.model.samples.n               = size(data, 2);
  law.model.samples.provenance      = 'legacy_csv';
  law.model.fit.x                   = data(4,:);
  law.model.fit.y                   = data(3,:);
  law.model.fit.n                   = size(data, 2);
  law.domains.numerical.min         = min(data(4,:));
  law.domains.numerical.max         = max(data(4,:));
  law.domains.hardware_supported.status = 'unknown';
  law.evaluation.out_of_domain          = 'extrapolate';
  law.evaluation.outside_hardware_support = 'warn';
  law.quality.fit_metrics.status    = 'not_available';
  law.provenance.legacy_file        = csv_path;
  law.provenance.migration_notes    = 'Auto-loaded from legacy CSV; run migrate_csv_to_yaml.';
end

% -------------------------------------------------------------------------
function v = to_row_vec(v)
  if iscell(v)
    try
      v = cell2mat(v);
    catch
      v = [];
    end
  end
  if isnumeric(v)
    v = v(:)';
  end
end
