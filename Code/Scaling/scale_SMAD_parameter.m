% scale_SMAD_parameter  Look up a SMAD statistical scaling from CSV data.
%
% y = scale_SMAD_parameter(in, sc_type, param_a, param_b)
%   Returns the scaled value y by linear interpolation of the CSV curve
%   param_a -> param_b for the given spacecraft type (1-4).
%
% [y, conf] = scale_SMAD_parameter(...)
%   Also returns a confidence struct (see scaling_confidence) describing
%   how reliable the interpolation is at 'in'.  The conf output is only
%   computed when requested, so existing callers pay no overhead.
function [y, conf] = scale_SMAD_parameter(in, sc_type, param_a, param_b)
 sc_name= {"No Propulsion";"Low Earth";"High Earth";"Planetary"};
 filename=strcat("Database/Scaling/scaling_spacecraft_",char(sc_name{sc_type,1}),"_parameter_",param_a,"_to_",param_b,".csv");
 if exist(filename)
  data = dlmread(filename,",");
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