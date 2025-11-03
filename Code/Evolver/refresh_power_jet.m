function [power_jet] = refresh_power_jet(individual_data)
 eff_PPU = individual_data.eff_PPU;
 eff_thruster = individual_data.eff_thruster;
 propulsion_power = individual_data.propulsion_power;
 
 power_jet = eff_PPU*eff_thruster*propulsion_power;
end