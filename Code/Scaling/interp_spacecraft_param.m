% interp_spacecraft_param  Interpolate a spacecraft system parameter from the reference database.
%
% y = interp_spacecraft_param(in, sc_type, param_a, param_b)
%   Returns y by polynomial interpolation of the database-fitted curve
%   param_a -> param_b for the given spacecraft type (1-4).
%   Loads from Database/Scaling/*.yaml (falls back to *.csv with a warning).
%
% [y, conf] = interp_spacecraft_param(...)
%   Also returns a confidence struct (see scaling_confidence).
function [y, conf] = interp_spacecraft_param(in, sc_type, param_a, param_b)
  sc_name = {'No Propulsion'; 'Low Earth'; 'High Earth'; 'Planetary'};
  stem = strcat('Database/Scaling/scaling_spacecraft_', char(sc_name{sc_type}), ...
                '_parameter_', param_a, '_to_', param_b);

  if exist([stem '.yaml'], 'file') || exist([stem '.csv'], 'file')
    law = scaling_law_load(stem);
    y   = scaling_law_evaluate(law, in);
    if nargout > 1
      % Reconstruct 4-row matrix for backward-compatible scaling_confidence call
      data = [law.model.samples.output; law.model.samples.input; ...
              law.model.fit.y;          law.model.fit.x];
      conf = scaling_confidence(in, data);
    end
  else
    disp('File not found.');
    disp(stem);
    y = NaN;
    if nargout > 1
      conf = struct('score', 0, 'regime', 'unknown', 'gap_fraction', NaN, ...
                    'n_source_points', 0, 'label', 'low');
    end
  end
end
