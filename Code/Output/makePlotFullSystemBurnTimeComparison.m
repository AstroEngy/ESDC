function [] = makePlotFullSystemBurnTimeComparison(analysis, case_type)
% Burn time vs exhaust velocity — migrated to shared plotting framework.
sweeps(size(analysis,2)) = struct('x',[],'y',[],'label','','markers',[]);
for i = 1:size(analysis, 2)
  t_burn = (analysis(i).result.propellant_mass ./ analysis(i).m_dot) / (60*60*24);
  fprintf('  %s  max burn time: %.1f days\n', analysis(i).description, max(t_burn));
  sweeps(i) = struct('x', analysis(i).c_e, 'y', t_burn, ...
                     'label', analysis(i).description, 'markers', []);
end
opts.xlabel_str  = 'Effective exhaust velocity [m/s]';
opts.ylabel_str  = 'Burn time [days]';
opts.export      = true;
opts.visible     = false;
opts.output_file = fullfile('Output', ['ESDC_burn_time_' case_type]);
plot_parameter_sweep(sweeps, opts);
disp(['Output complete: burn time comparison -- ' case_type]);
end

