% test_system_scaling - Test script for system_scaling function
%
% This script tests the new system_scaling function to verify:
% 1. Basic functionality with minimal input
% 2. Compatibility with SMAD_scalings interface
% 3. Proper handling of margins and mass distribution
% 4. Correct output structure format
%
% Usage: Run this script from Octave/MATLAB command line
%        >> test_system_scaling

function test_system_scaling()
    
    disp('==================================================');
    disp('Testing system_scaling.m');
    disp('==================================================');
    disp('');
    
    % Add necessary paths
    addpath('Code/Scaling');
    addpath('Code/Support');
    
    % Test 1: Basic LEO spacecraft
    disp('Test 1: LEO spacecraft with basic parameters');
    disp('--------------------------------------------------');
    test_data_1 = struct();
    test_data_1.mass = 1000;  % 1000 kg spacecraft
    test_data_1.dv = 500;     % 500 m/s delta-v
    test_data_1.c_e = 3000;   % 3000 m/s exhaust velocity
    
    [masses_1, powers_1] = system_scaling(test_data_1);
    
    disp('Input:');
    disp(['  Total mass: ', num2str(test_data_1.mass), ' kg']);
    disp(['  Delta-v: ', num2str(test_data_1.dv), ' m/s']);
    disp(['  Exhaust velocity: ', num2str(test_data_1.c_e), ' m/s']);
    disp('');
    disp('Output masses:');
    disp(['  Dry mass (no margin): ', num2str(masses_1.m_dry_nomargin), ' kg']);
    disp(['  Margin: ', num2str(masses_1.m_margin), ' kg']);
    disp(['  Dry mass (with margin): ', num2str(masses_1.m_dry_margin), ' kg']);
    disp(['  Propellant: ', num2str(masses_1.mass_propellant), ' kg']);
    disp(['  Payload: ', num2str(masses_1.mass_payload), ' kg']);
    disp(['  Structure: ', num2str(masses_1.mass_structmech), ' kg']);
    disp(['  Power subsystem: ', num2str(masses_1.mass_power), ' kg']);
    disp('');
    disp('Output powers:');
    disp(['  Total power: ', num2str(powers_1.power_total), ' W']);
    disp(['  Payload power: ', num2str(powers_1.power_payload), ' W']);
    disp(['  ADCS power: ', num2str(powers_1.power_adc), ' W']);
    disp('');
    
    % Verify mass balance
    total_subsystem_mass = masses_1.mass_payload + masses_1.mass_structmech + ...
                          masses_1.mass_thermal + masses_1.mass_power + ...
                          masses_1.mass_ttc + masses_1.mass_adc + ...
                          masses_1.mass_propulsion + masses_1.mass_other;
    
    disp('Verification:');
    disp(['  Sum of subsystems: ', num2str(total_subsystem_mass), ' kg']);
    disp(['  Expected (m_dry_margin): ', num2str(masses_1.m_dry_margin), ' kg']);
    disp(['  Difference: ', num2str(abs(total_subsystem_mass - masses_1.m_dry_margin)), ' kg']);
    
    if abs(total_subsystem_mass - masses_1.m_dry_margin) < 0.1
        disp('  ✓ Mass balance check PASSED');
    else
        disp('  ✗ Mass balance check FAILED');
    endif
    disp('');
    
    
    % Test 2: High Earth/GEO spacecraft
    disp('Test 2: High Earth spacecraft');
    disp('--------------------------------------------------');
    test_data_2 = struct();
    test_data_2.mass = 3000;  % 3000 kg spacecraft
    test_data_2.dv = 2500;    % 2500 m/s delta-v (GEO orbit change)
    test_data_2.c_e = 3200;
    
    [masses_2, powers_2] = system_scaling(test_data_2);
    
    disp(['  Dry mass (no margin): ', num2str(masses_2.m_dry_nomargin), ' kg']);
    disp(['  Margin: ', num2str(masses_2.m_margin), ' kg']);
    disp(['  Total power: ', num2str(powers_2.power_total), ' W']);
    disp('');
    
    
    % Test 3: Spacecraft without propulsion
    disp('Test 3: Spacecraft without propulsion');
    disp('--------------------------------------------------');
    test_data_3 = struct();
    test_data_3.mass = 500;  % 500 kg spacecraft
    % No dv or c_e, so it's type 1 (no propulsion)
    
    [masses_3, powers_3] = system_scaling(test_data_3);
    
    disp(['  Dry mass: ', num2str(masses_3.m_dry_nomargin), ' kg']);
    disp(['  Propulsion mass: ', num2str(masses_3.mass_propulsion), ' kg']);
    disp(['  Payload mass: ', num2str(masses_3.mass_payload), ' kg']);
    disp('');
    
    
    % Test 4: Compare with SMAD_scalings (if it exists and works)
    disp('Test 4: Compatibility check with SMAD_scalings');
    disp('--------------------------------------------------');
    try
        [smad_masses, smad_powers] = SMAD_scalings(test_data_1);
        [new_masses, new_powers] = system_scaling(test_data_1);
        
        disp('Comparing outputs:');
        disp(['  SMAD dry mass: ', num2str(smad_masses.m_dry_nomargin), ' kg']);
        disp(['  New dry mass: ', num2str(new_masses.m_dry_nomargin), ' kg']);
        disp(['  Match: ', num2str(abs(smad_masses.m_dry_nomargin - new_masses.m_dry_nomargin) < 0.01)]);
        disp('');
        
        % Check that both have the same fields
        smad_fields = fieldnames(smad_masses);
        new_fields = fieldnames(new_masses);
        
        disp(['  SMAD fields: ', num2str(length(smad_fields))]);
        disp(['  New fields: ', num2str(length(new_fields))]);
        
        % Check for any missing fields
        missing_in_new = setdiff(smad_fields, new_fields);
        if isempty(missing_in_new)
            disp('  ✓ All SMAD mass fields present in new function');
        else
            disp('  ✗ Missing fields in new function:');
            disp(missing_in_new);
        endif
        
        smad_power_fields = fieldnames(smad_powers);
        new_power_fields = fieldnames(new_powers);
        missing_power = setdiff(smad_power_fields, new_power_fields);
        if isempty(missing_power)
            disp('  ✓ All SMAD power fields present in new function');
        else
            disp('  ✗ Missing power fields in new function:');
            disp(missing_power);
        endif
        
    catch err
        disp('Could not compare with SMAD_scalings (may not be available in this environment)');
        disp(['Error: ', err.message]);
    end
    
    disp('');
    disp('==================================================');
    disp('Testing complete');
    disp('==================================================');
    
endfunction


% Run the test if called as a script
if ~exist('octave_config_info', 'builtin')
    % MATLAB
    test_system_scaling();
else
    % Octave
    test_system_scaling();
endif
