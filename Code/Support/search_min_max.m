function [min_val max_val] = search_min_max(db_data, individual, field, required_match) % extend for potentially multiple requirements 
%function to search for the minimal and maximal values of a desired field in a given input db_data structure that matches a required field identity for a given population individual

% take direct values in case of size 1 input
if numel(db_data)==1
  if ~isfield(db_data, field)
    min_val = 0;
    max_val = 0;
    return;
  end
  [min_val, max_val] = extract_min_max(db_data, field);
else

  min_val = Inf;        %not great init, better?
  max_val = 0;
  %loop over potentially relevant db_data entries
  for i=1:numel(db_data)
    % Skip entries missing the required match or the target field
    if ~isfield(db_data{1,i}, required_match) || ~isfield(db_data{1,i}, field)
      continue;
    end
    %Check for requirement
    if strcmp(db_data{1,i}.(required_match), individual.(required_match))
      [entry_min, entry_max] = extract_min_max(db_data{1,i}, field);
      if entry_max > max_val
          max_val = entry_max;
      end
      if entry_min < min_val
          min_val = entry_min;
      end
    end
  end

  % Fallback if no matching entry found
  if min_val == Inf
    min_val = 0;
  end
end

end

function [lo, hi] = extract_min_max(s, field)
  % Extract scalar min/max from a field that may be a scalar or a min/max struct.
  val = s.(field);
  if isstruct(val)
    if isfield(val, 'min') && isfield(val, 'max')
      lo = val.min;
      hi = val.max;
    else
      lo = 0; hi = 0;
    end
  else
    lo = val;
    hi = val;
  end
end