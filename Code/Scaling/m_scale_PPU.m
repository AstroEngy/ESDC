% PPU Mass Scaling Function
%
% Generates PPU (Power Processing Unit) mass estimations for specified
% propulsion types using predetermined propellants and power data from database
%
% Inputs:
%   P_thruster      - Thruster power [W]
%   propulsion_type - Type of propulsion system (string)
%
% Outputs:
%   m_PPU - Estimated PPU mass [kg]

function [m_PPU] = m_scale_PPU(P_thruster, propulsion_type)
    
    % Generate scaling data filename
    scaling_file = sprintf(...
        "Database/Scaling/scaling_propulsion_system_%s_ppu_mass_to_power.csv", ...
        propulsion_type);
    
    % Check if scaling data exists
    if exist(scaling_file, 'file')
        % Load scaling data from CSV
        data = dlmread(scaling_file, ",");
        
        % Reorder data rows for scaling function
        % Swap rows 1-2 and rows 3-4
        data(1:2, :) = [data(2, :); data(1, :)];
        data(3:4, :) = [data(4, :); data(3, :)];
        
        % Apply linear scaling to estimate PPU mass
        m_PPU = scaling_linear(P_thruster, data);
    else
        error('PPU scaling data file not found: %s', scaling_file);
    end
    
end