% scale_SMAD_parameter  Compatibility wrapper — use interp_spacecraft_param instead.
function [y, conf] = scale_SMAD_parameter(in, sc_type, param_a, param_b)
  if nargout > 1
    [y, conf] = interp_spacecraft_param(in, sc_type, param_a, param_b);
  else
    y = interp_spacecraft_param(in, sc_type, param_a, param_b);
  end
end