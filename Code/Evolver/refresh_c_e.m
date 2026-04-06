function c_e = refresh_c_e(individual_data)
  power_jet= individual_data.power_jet;
  thrust=individual_data.thrust;
  if isnan(thrust) || thrust <= 0 || isinf(thrust)
    c_e = NaN;
    return;
  end
  c_e = 2*power_jet/thrust; 
end