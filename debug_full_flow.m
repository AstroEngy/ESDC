% debug_full_flow.m - Test complete YAML data loading
clear all;
addpath('Code/Support');
addpath('Code/Input');

fprintf('\n╔════════════════════════════════════════════════════════╗\n');
fprintf('║     ESDC YAML Loading Debug Script                  ║\n');
fprintf('║     Date: %s UTC                 ║\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('╚════════════════════════════════════════════════════════╝\n\n');

%% Test 1: Check if read_file_auto exists
fprintf('Test 1: Checking read_file_auto function...\n');
if exist('read_file_auto', 'file')
    fprintf('  ✓ read_file_auto.m found\n\n');
else
    fprintf('  ✗ ERROR: read_file_auto.m NOT FOUND!\n');
    fprintf('  → Create Code/Input/read_file_auto.m\n\n');
    return;
end

%% Test 2: Check YAML files exist
fprintf('Test 2: Checking YAML files...\n');
yaml_files = {
    'Database/model_DOF.yaml';
    'Database/ESDC_Reference_Data_Systems.yaml';
    'Database/ESDC_Reference_Data_Spacecrafts.yaml';
    'Input/ESDC_Input.yaml';
    'Input/ESDC_Simulation_parameters.yaml'
};

all_exist = true;
for i = 1:length(yaml_files)
    if exist(yaml_files{i}, 'file')
        fprintf('  ✓ %s\n', yaml_files{i});
    else
        fprintf('  ✗ MISSING: %s\n', yaml_files{i});
        all_exist = false;
    end
end

if ~all_exist
    fprintf('\n  → Run convert_all.m to create missing YAML files\n\n');
    return;
end
fprintf('\n');

%% Test 3: Load DOF data
fprintf('Test 3: Loading DOF data...\n');
try
    DOF_data = read_file_auto('Database/model_DOF');
    fprintf('  ✓ DOF data loaded\n');
    
    if isfield(DOF_data, 'propulsion_system')
        fprintf('  ✓ Has propulsion_system field\n');
        
        ps_fields = fieldnames(DOF_data.propulsion_system);
        fprintf('  Propulsion systems found: %d\n', length(ps_fields));
        for i = 1:length(ps_fields)
            fprintf('    - %s\n', ps_fields{i});
        end
        
        % Check for gridionthruster specifically
        if isfield(DOF_data.propulsion_system, 'gridionthruster')
            fprintf('  ✓ gridionthruster exists\n');
        else
            fprintf('  ✗ gridionthruster MISSING!\n');
        end
    else
        fprintf('  ✗ No propulsion_system field!\n');
    end
catch err
    fprintf('  ✗ ERROR loading DOF: %s\n', err.message);
end
fprintf('\n');

%% Test 4: Load Reference Data (this is where your error occurs)
fprintf('Test 4: Loading Reference Data...\n');
try
    ref_data = read_file_auto('Database/ESDC_Reference_Data_Systems');
    fprintf('  ✓ Reference data loaded\n');
    
    if isfield(ref_data, 'reference_data')
        fprintf('  ✓ Has reference_data field\n');
        
        if isfield(ref_data.reference_data, 'propulsion_system')
            fprintf('  ✓ Has propulsion_system field\n');
            
            ps_fields = fieldnames(ref_data.reference_data.propulsion_system);
            fprintf('  Propulsion systems found: %d\n', length(ps_fields));
            for i = 1:length(ps_fields)
                fprintf('    - %s\n', ps_fields{i});
            end
            
            % Check for gridionthruster specifically
            if isfield(ref_data.reference_data.propulsion_system, 'gridionthruster')
                fprintf('  ✓ gridionthruster exists in reference data\n');
                
                % Check what's inside
                if isfield(ref_data.reference_data.propulsion_system.gridionthruster, 'thruster')
                    fprintf('  ✓ gridionthruster.thruster exists\n');
                else
                    fprintf('  ✗ gridionthruster.thruster MISSING\n');
                end
            else
                fprintf('  ✗ gridionthruster MISSING in reference data!\n');
            end
        else
            fprintf('  ✗ No propulsion_system field in reference_data!\n');
        end
    else
        fprintf('  ✗ No reference_data field!\n');
    end
catch err
    fprintf('  ✗ ERROR loading reference data: %s\n', err.message);
    fprintf('  Stack trace:\n');
    for i = 1:length(err.stack)
        fprintf('    %s at line %d\n', err.stack(i).name, err.stack(i).line);
    end
end
fprintf('\n');

%% Test 5: Try calling read_reference_data() directly
fprintf('Test 5: Calling read_reference_data() function...\n');
try
    database = read_reference_data();
    fprintf('  ✓ read_reference_data() succeeded\n');
    
    % Check structure
    if isfield(database, 'reference_data')
        fprintf('  ✓ Has reference_data field\n');
        
        if isfield(database.reference_data, 'propulsion_system')
            ps_fields = fieldnames(database.reference_data.propulsion_system);
            fprintf('  Propulsion systems: ');
            fprintf('%s ', ps_fields{:});
            fprintf('\n');
            
            if isfield(database.reference_data.propulsion_system, 'gridionthruster')
                fprintf('  ✓ gridionthruster exists!\n');
            else
                fprintf('  ✗ gridionthruster MISSING!\n');
            end
        end
    end
catch err
    fprintf('  ✗ ERROR: %s\n', err.message);
end
fprintf('\n');

%% Summary
fprintf('╔════════════════════════════════════════════════════════╗\n');
fprintf('║  Debug Summary                                       ║\n');
fprintf('╚════════════════════════════════════════════════════════╝\n\n');
fprintf('If all tests passed, YAML loading is working correctly.\n');
fprintf('If test 4 or 5 failed, the issue is in the YAML file structure.\n\n');