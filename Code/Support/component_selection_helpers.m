% component_selection_helpers — Shared utility functions for component selection
%
% This module provides helper functions used across multiple component selection
% functions in the Analysis directory. These functions extract scalar values
% from database entries that may contain nested structures, ranges, or cells.
%
% Functions:
%   scalar_midpoint(entry, field)  — Extract midpoint value from entry field
%   get_str_field(entry, field, default) — Extract string field with default fallback

% =========================================================================
% SCALAR_MIDPOINT
% =========================================================================
% Returns the midpoint (min+max)/2 of a range field, or the scalar value.
% Also handles {max: X} only (returns X).
%
% Handles:
%   - Scalar numeric values: returns the value
%   - Cells: recursively searches for first numeric scalar
%   - Structs with 'nominal': returns nominal
%   - Structs with 'min' and 'max': returns (min+max)/2
%   - Structs with only 'min' or 'max': returns that value
%   - Other cases: returns NaN
function val = scalar_midpoint(entry, field)
  val = NaN;
  if ~isfield(entry, field); return; end
  v = entry.(field);
  if isnumeric(v) && isscalar(v)
    val = v;
  elseif iscell(v)
    for _ci = 1:numel(v)
      tmp.x = v{_ci};
      candidate = scalar_midpoint(tmp, 'x');
      if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        val = candidate; return;
      end
    end
  elseif isstruct(v)
    if isfield(v, 'nominal')
      val = v.nominal;
    elseif isfield(v, 'min') && isfield(v, 'max')
      val = (v.min + v.max) / 2;
    elseif isfield(v, 'min')
      val = v.min;
    elseif isfield(v, 'max')
      val = v.max;
    end
  end
end

% =========================================================================
% GET_STR_FIELD
% =========================================================================
% Returns the string value of a field if it exists and is a character array,
% otherwise returns the default value.
function s = get_str_field(entry, field, default)
  if isfield(entry, field) && ischar(entry.(field))
    s = entry.(field);
  else
    s = default;
  end
end
