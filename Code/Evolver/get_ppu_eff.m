function eff_ppu = get_ppu_eff(data)
 %todo: update this to not consider the average of all relevant PPUs but look for data adaptive estimate
  n_ppu = size(data,2);
  if n_ppu==1
    if isfield(data, 'efficiency')
      eff_ppu = scalar_field(data, 'efficiency');
    else
      eff_ppu = 1;  % assume ideal PPU if no efficiency data available
    end
  else
    eff_ppu_list = [];
    for i=1:n_ppu
      if isfield(data{i}, 'efficiency')
        val = scalar_field(data{i}, 'efficiency');
        if ~isnan(val)
          eff_ppu_list = [eff_ppu_list; val];
        end
      end
    end
    if isempty(eff_ppu_list)
      eff_ppu = 1;  % assume ideal PPU if no efficiency data available
    else
      eff_ppu = average_array(eff_ppu_list);
    end
  end
end

function val = scalar_field(s, fname)
  % Extract a scalar from a field that may be a scalar, a min/max struct, or a
  % cell array (from duplicate XML tags). In the cell case, recurse on the first
  % element that resolves to a finite scalar.
  if ~isfield(s, fname)
    val = NaN;
  elseif iscell(s.(fname))
    val = NaN;
    for _ci = 1:numel(s.(fname))
      tmp_s.(fname) = s.(fname){_ci};
      candidate = scalar_field(tmp_s, fname);
      if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        val = candidate;
        break;
      end
    end
  elseif isstruct(s.(fname))
    if isfield(s.(fname), 'nominal')
      val = s.(fname).nominal;
    elseif isfield(s.(fname), 'min') && isfield(s.(fname), 'max')
      val = (s.(fname).min + s.(fname).max) / 2;
    elseif isfield(s.(fname), 'min')
      val = s.(fname).min;
    elseif isfield(s.(fname), 'max')
      val = s.(fname).max;
    else
      val = NaN;
    end
  else
    val = s.(fname);
  end
end
