% scaling_law_validate  Check that a scaling law struct conforms to schema v1.
%
% [ok, msgs] = scaling_law_validate(law)
%   ok   — true when all required fields are present and consistent.
%   msgs — cell array of human-readable problem strings (empty when ok=true).
%
% Validation is intentionally strict for required fields (id, lifecycle,
% classification, input, output, model) and advisory for optional ones.
% An invalid schema_version causes an immediate hard reject.
function [ok, msgs] = scaling_law_validate(law)
  msgs = {};
  ok   = true;

  function reject(fmt, varargin)
    msgs{end+1} = sprintf(fmt, varargin{:});
    ok = false;
  end

  % Schema version — hard check
  if ~isfield(law, 'schema_version')
    reject('Missing schema_version');
  elseif ~isnumeric(law.schema_version) || law.schema_version ~= 1
    reject('Unsupported schema_version %s (expected 1)', num2str(law.schema_version));
  end

  % Required top-level fields
  for f = {'id', 'lifecycle', 'classification', 'input', 'output', 'model'}
    if ~isfield(law, f{1})
      reject('Missing required field: %s', f{1});
    end
  end

  % Lifecycle status
  valid_statuses = {'active', 'inactive', 'planned', 'deprecated'};
  if isfield(law, 'lifecycle') && isfield(law.lifecycle, 'status')
    if ~any(strcmp(law.lifecycle.status, valid_statuses))
      reject('Unknown lifecycle.status ''%s''', law.lifecycle.status);
    end
  elseif isfield(law, 'lifecycle')
    reject('lifecycle.status missing');
  end

  % Model kind/method
  supported_kinds    = {'interpolation'};
  supported_methods  = {'linear_on_polynomial_fit'};
  if isfield(law, 'model')
    if isfield(law.model, 'kind') && ~any(strcmp(law.model.kind, supported_kinds))
      reject('Unsupported model.kind ''%s''', law.model.kind);
    end
    if isfield(law.model, 'method') && ~any(strcmp(law.model.method, supported_methods))
      reject('Unsupported model.method ''%s''', law.model.method);
    end

    % Fit arrays
    if ~isfield(law.model, 'fit')
      reject('model.fit subsection missing');
    else
      fit = law.model.fit;
      if ~isfield(fit, 'x') || ~isfield(fit, 'y')
        reject('model.fit must have x and y arrays');
      elseif isnumeric(fit.x) && isnumeric(fit.y) && numel(fit.x) ~= numel(fit.y)
        reject('model.fit.x (%d pts) and model.fit.y (%d pts) length mismatch', ...
               numel(fit.x), numel(fit.y));
      elseif ~isnumeric(fit.x) || ~isnumeric(fit.y)
        reject('model.fit.x and model.fit.y must be numeric arrays');
      end
    end
  end
end
