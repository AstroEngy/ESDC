function [] = makePlotNormalizedSystemFunction(input)
% Normalized subsystem mass fractions vs c_e — migrated to shared framework.
opts.export  = true;
opts.visible = false;
opts.style   = plot_style();
plot_subsystem_breakdown(input, opts);
disp(['Output complete: subsystem breakdown -- ' strtrim(strrep(input.description, char(10), ' '))]);
end

