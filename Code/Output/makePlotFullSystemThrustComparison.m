function [] = makePlotFullSystemThrustComparison(analysis, case_type)
% Thrust vs exhaust velocity — migrated to shared plotting framework.
sweeps(size(analysis,2)) = struct('x',[],'y',[],'label','','markers',[]);
for i = 1:size(analysis, 2)
  F = 2 * analysis(i).P_jet ./ analysis(i).c_e;
  sweeps(i) = struct('x', analysis(i).c_e, 'y', F, ...
                     'label', analysis(i).description, 'markers', []);
end
opts.xlabel_str  = 'Effective exhaust velocity [m/s]';
opts.ylabel_str  = 'Thrust [N]';
opts.export      = true;
opts.visible     = false;
opts.output_file = fullfile('Output', ['ESDC_thrust_' case_type]);
plot_parameter_sweep(sweeps, opts);
disp(['Output complete: thrust comparison -- ' case_type]);
end
