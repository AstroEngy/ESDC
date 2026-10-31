function [] = makePlotFullSystemComparison(input, data, analysis, config, case_type)
% EP system mass fraction vs exhaust velocity — migrated to shared plotting framework.
st = plot_style();

if config.ConsiderMargins == 1
  analysis = plot_margins(analysis, config);
end

n = size(analysis, 2);
sweeps(n) = struct('x', [], 'y', [], 'label', '', 'markers', []);
for i = 1:n
  mk(1) = struct('x', analysis(i).result.mu_EP_min_c_e, ...
                 'y', analysis(i).result.mu_EP_min, 'style', 'dr');
  mk(2) = struct('x', input(i).c_e, 'y', data.reference(i).mu_EP, 'style', 'xr');
  sweeps(i) = struct('x', analysis(i).c_e, 'y', analysis(i).result.mu_EP, ...
                     'label', analysis(i).description, 'markers', mk);
end
if config.ConsiderMargins == 1
  for i = 1:n
    sweeps(end+1) = struct('x', analysis(i).mu_min_margin_c_e, ...
      'y', analysis(i).mu_min_margin, ...
      'label', [num2str(config.margin) '% margin'], 'markers', []);
  end
end

opts.xlabel_str  = 'Effective exhaust velocity [m/s]';
opts.ylabel_str  = 'EP system mass fraction [-]';
opts.ylim        = [0, 1];
opts.style       = st;
opts.export      = true;
opts.visible     = false;
opts.output_file = fullfile('Output', ['ESDC_EP_mass_fraction_' case_type]);
opts.layout      = 'double';
plot_parameter_sweep(sweeps, opts);
disp(['Output complete: EP mass fraction comparison -- ' case_type]);
end
