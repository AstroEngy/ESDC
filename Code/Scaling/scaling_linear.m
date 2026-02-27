function [x] = scaling_linear(y, data)
    % Interpolate for known data, extrapolate beyond.

    xdata = data(4,:);
    ydata = data(3,:);

    % Sort by X (required for monotonicity) and deduplicate (average Y for equal X)
    [xdata, sort_idx] = sort(xdata);
    ydata = ydata(sort_idx);
    [xdata, ia] = unique(xdata, 'stable');
    if numel(xdata) < numel(sort_idx)
      % some duplicates were removed — recompute averaged Y values
      all_xdata = data(4, sort_idx);
      all_ydata = data(3, sort_idx);
      unique_ydata = zeros(size(xdata));
      for k = 1:numel(xdata)
        unique_ydata(k) = mean(all_ydata(all_xdata == xdata(k)));
      endfor
      ydata = unique_ydata;
    endif

    % Need at least 2 points for interp1; if only 1, assume proportional scaling
    if numel(xdata) < 2
      if numel(xdata) == 1 && xdata(1) ~= 0
        x = ydata(1) * (y / xdata(1));
      else
        x = 0;
      end
    else
      x = interp1(xdata, ydata, y, 'linear', 'extrap');
    end

    if x < 0      %exclude negatives
      x = 0;
    end
endfunction