% scaling_law_write_yaml  Serialise a scaling law struct to a YAML file.
%
% scaling_law_write_yaml(yaml_path, law)
%   Write law to yaml_path using an atomic temp-file replace so partially
%   written files are never visible to readers.
%
% The YAML is the canonical runtime format; do not regenerate CSV alongside it.
% Machine-specific absolute paths and migration-only notes are NOT written.
% Fit quality uses the struct fields set by data_fitting.m (training-fit only).
function scaling_law_write_yaml(yaml_path, law)
  % Write to a temp file first, then rename (atomic on same filesystem)
  [d, n, e] = fileparts(yaml_path);
  tmp_path = fullfile(d, [n '_tmp' e]);
  fid = fopen(tmp_path, 'w');
  if fid == -1
    error('scaling_law_write_yaml: cannot open for writing: %s', tmp_path);
  end
  try
    w(fid, '# ESDC Scaling Law — schema_version 1');
    w(fid, '');
    wkv(fid, 'schema_version', '1');
    wkv(fid, 'id',    law.id);
    if isfield(law, 'title')
      wkv(fid, 'title', squote(law.title));
    end
    w(fid, '');

    w(fid, 'lifecycle:');
    wkv(fid, '  status', law.lifecycle.status);
    w(fid, '');

    w(fid, 'classification:');
    wkv(fid, '  category', law.classification.category);
    if isfield(law.classification, 'orbit_type')
      wkv(fid, '  orbit_type', squote(law.classification.orbit_type));
    end
    if isfield(law.classification, 'system')
      wkv(fid, '  system', law.classification.system);
    end
    if isfield(law.classification, 'technology')
      wkv(fid, '  technology', squote(law.classification.technology));
    end
    if isfield(law.classification, 'component')
      wkv(fid, '  component', squote(law.classification.component));
    end
    if isfield(law.classification, 'propellant_display')
      % Human-readable chemical name; filename uses sanitized form
      wkv(fid, '  propellant_display', squote(law.classification.propellant_display));
    elseif isfield(law.classification, 'propellant')
      wkv(fid, '  propellant', squote(law.classification.propellant));
    end
    w(fid, '');

    w(fid, 'input:');
    wkv(fid, '  quantity', law.input.quantity);
    wkv(fid, '  unit',     law.input.unit);
    w(fid, '');
    w(fid, 'output:');
    wkv(fid, '  quantity', law.output.quantity);
    wkv(fid, '  unit',     law.output.unit);
    w(fid, '');

    w(fid, 'model:');
    wkv(fid, '  kind',   law.model.kind);
    wkv(fid, '  method', law.model.method);
    w(fid, '  samples:');
    wkv(fid, '    n', num2str(law.model.samples.n));
    wkv(fid, '    provenance', law.model.samples.provenance);
    wkv(fid, '    input',  farr(law.model.samples.input));
    wkv(fid, '    output', farr(law.model.samples.output));
    w(fid, '  fit:');
    wkv(fid, '    n', num2str(law.model.fit.n));
    wkv(fid, '    x', farr(law.model.fit.x));
    wkv(fid, '    y', farr(law.model.fit.y));
    if isfield(law.model, 'poly_degree')
      wkv(fid, '    poly_degree', num2str(law.model.poly_degree));
    end
    w(fid, '');

    w(fid, 'domains:');
    w(fid, '  numerical:');
    wkv(fid, '    min', sprintf('%.15g', law.domains.numerical.min));
    wkv(fid, '    max', sprintf('%.15g', law.domains.numerical.max));
    w(fid, '  hardware_supported:');
    wkv(fid, '    status', law.domains.hardware_supported.status);
    if isfield(law.domains.hardware_supported, 'notes')
      wkv(fid, '    notes', squote(law.domains.hardware_supported.notes));
    end
    w(fid, '');

    w(fid, 'evaluation:');
    wkv(fid, '  out_of_domain',            law.evaluation.out_of_domain);
    wkv(fid, '  outside_hardware_support', law.evaluation.outside_hardware_support);
    w(fid, '');

    w(fid, 'quality:');
    w(fid, '  fit_metrics:');
    write_fit_metrics(fid, law.quality.fit_metrics);
    w(fid, '');

    % Provenance: only scientific / generation metadata; no local absolute paths
    write_provenance(fid, law);

    fclose(fid);
  catch err
    fclose(fid);
    if exist(tmp_path, 'file'); delete(tmp_path); end
    rethrow(err);
  end

  % Atomic replace
  if exist(yaml_path, 'file')
    delete(yaml_path);
  end
  movefile(tmp_path, yaml_path);
end

% ---- section writers ----
function write_fit_metrics(fid, fm)
  if ~isstruct(fm) || ~isfield(fm, 'status')
    wkv(fid, '    status', 'not_available');
    return;
  end
  wkv(fid, '    status', fm.status);
  if strcmp(fm.status, 'not_available')
    return;
  end
  if isfield(fm, 'evaluation_basis')
    wkv(fid, '    evaluation_basis', fm.evaluation_basis);
    w(fid,   '    note: ''Training-fit residuals only — not independent validation.''');
  end
  if isfield(fm, 'poly_degree');  wkv(fid, '    poly_degree', num2str(fm.poly_degree)); end
  if isfield(fm, 'n_observations'); wkv(fid, '    n_observations', num2str(fm.n_observations)); end
  if isfield(fm, 'df_residual');  wkv(fid, '    df_residual',  num2str(fm.df_residual)); end
  if isfield(fm, 'rmse')
    if isnan(fm.rmse)
      wkv(fid, '    rmse', '~');
    else
      wkv(fid, '    rmse', sprintf('%.10g', fm.rmse));
    end
  end
  if isfield(fm, 'r_squared')
    if isnan(fm.r_squared)
      wkv(fid, '    r_squared', '~');
    else
      wkv(fid, '    r_squared', sprintf('%.10g', fm.r_squared));
    end
  end
  if isfield(fm, 'r_squared_status')
    wkv(fid, '    r_squared_status', fm.r_squared_status);
  end
end

function write_provenance(fid, law)
  has_useful = isfield(law, 'provenance') && ...
    (isfield(law.provenance, 'generated_by') || isfield(law.provenance, 'database_hash') || ...
     isfield(law.provenance, 'generator_version'));
  if ~has_useful; return; end
  w(fid, '');
  w(fid, 'provenance:');
  if isfield(law.provenance, 'generated_by')
    wkv(fid, '  generated_by', squote(law.provenance.generated_by));
  end
  if isfield(law.provenance, 'generator_version')
    wkv(fid, '  generator_version', squote(law.provenance.generator_version));
  end
  if isfield(law.provenance, 'database_hash')
    wkv(fid, '  database_hash', squote(law.provenance.database_hash));
  end
end

% ---- low-level helpers ----
function w(fid, line)
  fprintf(fid, '%s\n', line);
end

function wkv(fid, key, val)
  fprintf(fid, '%s: %s\n', key, val);
end

function s = squote(str)
  s = ['''' strrep(char(str), '''', '''''') ''''];
end

function s = farr(arr)
  if isempty(arr)
    s = '[]';
    return;
  end
  parts = arrayfun(@(v) sprintf('%.15g', v), arr(:)', 'UniformOutput', false);
  s = ['[', strjoin(parts, ', '), ']'];
end

