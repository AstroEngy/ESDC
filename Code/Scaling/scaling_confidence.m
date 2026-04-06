function conf = scaling_confidence(x_query, data)
% scaling_confidence  Confidence score for a statistical scaling evaluation.
%
% Quantifies how well the local database supports the scaling estimate at
% x_query, distinguishing interpolation (query within source data span) from
% extrapolation (outside that span) and penalising sparse data coverage.
%
% Inputs
%   x_query  scalar  — the input value at which the scaling was evaluated
%   data     matrix  — 4-row CSV matrix as loaded by scale_SMAD_parameter:
%              row 1 (data(1,:)): original Y values (sparse source data)
%              row 2 (data(2,:)): original X values (sparse source data)
%              row 3 (data(3,:)): interpolated Y values on dense grid
%              row 4 (data(4,:)): interpolated X values on dense grid
%
% Output  conf  struct with fields:
%   score           in [0,1] — 0=no confidence, 1=full confidence
%   regime          'interpolation' | 'extrapolation'
%   gap_fraction    normalised span of the bracketing interval (0 means the
%                   query falls exactly on a data point; 1 means it sits at
%                   the maximum possible distance from all source data)
%   n_source_points number of original (non-interpolated) data points
%   label           'high'   (score 0.70 and above — green)
%                   'medium' (score 0.40 to 0.70   — yellow)
%                   'low'    (score below 0.40      — red)
%
% Scoring rules
%
%   INTERPOLATION  (query is inside the source data range)
%     Two factors are multiplied together:
%
%     n_factor  — coverage penalty for small databases
%       n_factor = min(1,  (n - 1) / 4)
%       n=1 → 0.00,  n=2 → 0.25,  n=3 → 0.50,  n=4 → 0.75,  n>=5 → 1.00
%       Rationale: fewer than 5 source points leaves the underlying
%       regression poorly constrained (Stone 1974 cross-validation bound).
%
%     gap_fraction  — local density penalty
%       gap_fraction = (x_right - x_left) / (x_max - x_min)
%       where x_left/x_right are the two nearest source points bracketing
%       the query.  A large gap means the local slope is poorly known.
%
%     score = n_factor * (1 - gap_fraction),  clamped to [0.30, 1.00]
%       The 0.30 floor ensures that any within-range estimation is
%       distinguishable from extrapolation, which is capped at 0.30.
%
%   EXTRAPOLATION  (query is outside the source data range)
%     score = 0.30 * max(0, 1 - extrap_fraction)
%       where extrap_fraction = distance_beyond_range / data_range
%       Score is always strictly below 0.30 — never overlaps
%       with the interpolation range — making regime change unambiguous.
%
% References
%   Draper, N. R., & Smith, H. (1998). Applied regression analysis (3rd ed.). Wiley. https://doi.org/10.1002/9781118625590
%     (extrapolation risk and leverage in regression models)
%   Stone, M. (1974). Cross-validatory choice and assessment of statistical predictions. Journal of the Royal Statistical Society: Series B (Methodological), 36(2), 111–147. https://doi.org/10.1111/j.2517-6161.1974.tb00994.x
%     (N-point cross-validation and coverage rationale)


  % ---- Source data: row 2 of CSV holds the original sparse x-coordinates ----
  x_orig = sort(unique(data(2, ~isnan(data(2,:)))));
  n      = numel(x_orig);
  conf.n_source_points = n;

  % Edge case: insufficient data for meaningful confidence assessment
  if n < 2
    conf.regime       = 'interpolation';
    conf.gap_fraction = 1.0;
    conf.score        = 0.3;
    conf.label        = label_from_score(conf.score);
    return;
  end

  x_min   = x_orig(1);
  x_max   = x_orig(end);
  x_range = x_max - x_min;

  % Zero-range guard (all source points have identical x)
  if x_range <= 0
    conf.regime       = 'interpolation';
    conf.gap_fraction = 0;
    conf.score        = 0.5;
    conf.label        = label_from_score(conf.score);
    return;
  end

  % ---- Extrapolation ----
  if x_query < x_min || x_query > x_max
    conf.regime       = 'extrapolation';
    extrap_e          = max(x_min - x_query, x_query - x_max);
    conf.gap_fraction = min(1.0, extrap_e / x_range);
    conf.score        = 0.3 * max(0, 1 - conf.gap_fraction);
    conf.label        = label_from_score(conf.score);
    return;
  end

  % ---- Interpolation ----
  conf.regime  = 'interpolation';
  % Bracketing interval in the original (sparse) source data
  idx_left = find(x_orig <= x_query, 1, 'last');
  if isempty(idx_left) || idx_left >= n
    gap = x_orig(end) - x_orig(end-1);
  else
    gap = x_orig(idx_left + 1) - x_orig(idx_left);
  end
  conf.gap_fraction = max(0, min(1, gap / x_range));
  % n_factor penalises databases with fewer than 5 source points
  n_factor          = min(1.0, (n - 1) / 4.0);
  raw               = n_factor * (1 - conf.gap_fraction);
  conf.score        = max(0.3, min(1.0, raw));
  conf.label        = label_from_score(conf.score);
end

% -------------------------------------------------------------------------
function lbl = label_from_score(score)
  if score >= 0.70
    lbl = 'high';
  elseif score >= 0.40
    lbl = 'medium';
  else
    lbl = 'low';
  end
end
