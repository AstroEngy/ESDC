% interp_spacecraft_param  Interpolate a spacecraft system parameter from the reference database.
%
% y = interp_spacecraft_param(in, sc_type, param_a, param_b)
%   Returns y by polynomial interpolation of the database-fitted curve
%   param_a -> param_b for the given spacecraft type (1-4).
%   The curve is stored in Database/Scaling/ as a 4-row CSV (raw data,
%   raw x values, fitted y curve, fitted x range).
%
% [y, conf] = interp_spacecraft_param(...)
%   Also returns a confidence struct (see scaling_confidence) describing
%   how reliable the interpolation is at 'in'.  Only computed on request.
function [y, conf] = interp_spacecraft_param(in, sc_type, param_a, param_b)
 sc_name = {'No Propulsion'; 'Low Earth'; 'High Earth'; 'Planetary'};
 filename = strcat('Database/Scaling/scaling_spacecraft_', char(sc_name{sc_type}), ...
                   '_parameter_', param_a, '_to_', param_b, '.csv');
 if exist(filename, 'file')
  data = dlmread(filename, ',');
  y = scaling_linear(in, data);
  if nargout > 1
    conf = scaling_confidence(in, data);
  end
 else
  disp('File not found.');
  disp(filename);
  y = NaN;
  if nargout > 1
    conf = struct('score', 0, 'regime', 'unknown', 'gap_fraction', NaN, ...
                  'n_source_points', 0, 'label', 'low');
  end
 end

end
