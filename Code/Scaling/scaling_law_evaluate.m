% scaling_law_evaluate  Evaluate a loaded scaling law at one or more inputs.
%
% y = scaling_law_evaluate(law, x)
%   Interpolate/extrapolate law at scalar or array x.
%   Mirrors the behaviour of scaling_linear.m exactly:
%     - Uses the dense fit grid (law.model.fit.x/y).
%     - Sorts and deduplicates the grid before interp1.
%     - Clamps negative outputs to zero.
%     - Extrapolates linearly beyond the numerical domain.
%
% y = scaling_law_evaluate(law, x, 'invert', true)
%   Evaluate the inverse mapping: use fit.y as the x-axis and fit.x as y.
%   Required by component consumers (m_scale_PPU, m_scale_thruster, m_scale_tank)
%   that stored mass→power relationships but need power→mass.
%   Equivalent to the legacy row-swap before calling scaling_linear.
%
% [y, info] = scaling_law_evaluate(...)
%   Also returns an info struct:
%     info.regime    'interpolation' | 'extrapolation'
%     info.law_id    id string from the law struct
%     info.x_min/max numerical domain bounds
%
% Inputs
%   law  — struct returned by scaling_law_load
%   x    — numeric scalar or array; input values to evaluate
%
% Outputs
%   y    — numeric, same size as x; evaluated output values (>= 0)
%   info — diagnostic struct (only when requested with nargout > 1)
function [y, info] = scaling_law_evaluate(law, x, varargin)
  invert = false;
  for k = 1:2:numel(varargin)
    if strcmpi(varargin{k}, 'invert')
      invert = logical(varargin{k+1});
    end
  end

  if invert
    xdata = law.model.fit.y(:)';
    ydata = law.model.fit.x(:)';
  else
    xdata = law.model.fit.x(:)';
    ydata = law.model.fit.y(:)';
  end

  % Sort ascending by x and deduplicate (identical to scaling_linear.m)
  [xdata, sort_idx] = sort(xdata);
  ydata = ydata(sort_idx);
  all_x = xdata;
  all_y = ydata;

  [xdata_u, ~] = unique(xdata, 'stable');
  if numel(xdata_u) < numel(all_x)
    ydata_u = zeros(size(xdata_u));
    for k = 1:numel(xdata_u)
      ydata_u(k) = mean(all_y(all_x == xdata_u(k)));
    end
    xdata = xdata_u;
    ydata = ydata_u;
  end

  % Evaluate
  if numel(xdata) < 2
    if numel(xdata) == 1 && xdata(1) ~= 0
      y = ydata(1) .* (x ./ xdata(1));
    else
      y = zeros(size(x));
    end
  else
    y = interp1(xdata, ydata, x, 'linear', 'extrap');
  end

  y(y < 0) = 0;  % clamp negatives — preserved from scaling_linear

  if nargout > 1
    x_min  = min(xdata);
    x_max  = max(xdata);
    in_dom = all(x(:) >= x_min) && all(x(:) <= x_max);
    info   = struct('regime', 'interpolation', 'law_id', law.id, ...
                    'x_min', x_min, 'x_max', x_max);
    if ~in_dom
      info.regime = 'extrapolation';
    end
  end
end
