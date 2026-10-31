function [] = makePlotFullSystemPowerComparison(analysis, case_type)
% Jet power vs exhaust velocity — migrated to shared plotting framework.
sweeps(size(analysis,2)) = struct('x',[],'y',[],'label','','markers',[]);
for i = 1:size(analysis, 2)
  sweeps(i) = struct('x', analysis(i).c_e, 'y', analysis(i).P_jet, ...
                     'label', analysis(i).description, 'markers', []);
end
opts.xlabel_str  = 'Effective exhaust velocity [m/s]';
opts.ylabel_str  = 'Jet power [W]';
opts.export      = true;
opts.visible     = false;
opts.output_file = fullfile('Output', ['ESDC_jet_power_' case_type]);
plot_parameter_sweep(sweeps, opts);
disp(['Output complete: jet power comparison -- ' case_type]);
end
