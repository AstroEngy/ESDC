% ==================================================================
% convert_all.m - Batch convert all ESDC XML files to YAML
% Author: AstroEngy
% Date: 2025-10-30
% ==================================================================
%THIS FILE SHOULD GO INTO ROOT WHEN IN USE
function convert_all()
    addpath('Code/Support')
    
    fprintf('\n╔════════════════════════════════════════════════════════╗\n');
    fprintf('║     ESDC XML to YAML Batch Converter                ║\n');
    fprintf('║     Date: %s UTC          ║\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf('╚════════════════════════════════════════════════════════╝\n\n');
    
    % List of ALL XML files in the repository
    xml_files = {
        % === Input/ (Root level - ACTIVE INPUT FILES) ===
        'Input/ESDC_Input.xml';
        'Input/ESDC_Simulation_parameters.xml';
        'Input/ESDC_Simulation_parameters_v2.xml';
        'Input/visualization.xml';
        
        % === DCEP_IO_Def/Input/ (Template/Definition files) ===
        'DCEP_IO_Def/Input/ESDC_Input.xml';
        'DCEP_IO_Def/Input/ESDC_Simulation_parameters.xml';
        'DCEP_IO_Def/Input/visualization.xml';
        'DCEP_IO_Def/Input/ESDC_Input_previous_version.xml';
        'DCEP_IO_Def/Input/ESDC_Simulation_parameters_v2.xml';
        'DCEP_IO_Def/Input/ESDC_Input_all_fields_template_revision.xml';
        'DCEP_IO_Def/Input/ESDC_Input_all_fields_template_revision_v2.xml';
        
        % === DCEP_IO_Def/BU/ (Backups) ===
        'DCEP_IO_Def/BU/ESDC_Input.xml';
        'DCEP_IO_Def/BU/ESDC_Simulation_parameters.xml';
        
        % === DCEP_IO_Def/Output/ (Output templates/examples) ===
        'DCEP_IO_Def/Output/ESDC_best_candidates.xml';
        'DCEP_IO_Def/Output/ESDC_best_candidates_revision_v2.xml';
        
        % === Database/ ===
        'Database/ESDC_Reference_Data_Systems.xml';
        'Database/ESDC_Reference_Data_Systems_Unused.xml';
        'Database/ESDC_Reference_Data_Spacecrafts.xml';
        'Database/model_DOF.xml';
        'Database/ESDC_variable_attributes.xml';
        
        % === Documentation/Example Files/Input/ ===
        'Documentation/Example Files/Input/ESDC_Input.xml';
        'Documentation/Example Files/Input/ESDC_Simulation_parameters.xml';
        'Documentation/Example Files/Input/visualization.xml'
    };
    
    n_success = 0;
    n_failed = 0;
    n_skipped = 0;
    total_xml_size = 0;
    total_yaml_size = 0;
    
    fprintf('Found %d XML files to convert\n\n', length(xml_files));
    
    for i = 1:length(xml_files)
        xml_file = xml_files{i};
        
        % Generate YAML filename (same directory, .yaml extension)
        [filepath, name, ~] = fileparts(xml_file);
        yaml_file = fullfile(filepath, [name '.yaml']);
        
        if ~exist(xml_file, 'file')
            fprintf('⚠ [%d/%d] Skipping (not found): %s\n', i, length(xml_files), xml_file);
            n_skipped = n_skipped + 1;
            continue;
        end
        
        try
            fprintf('[%d/%d] Converting: %s\n', i, length(xml_files), xml_file);
            convert_xml_to_yaml(xml_file, yaml_file);
            
            % Accumulate sizes
            xml_info = dir(xml_file);
            yaml_info = dir(yaml_file);
            total_xml_size = total_xml_size + xml_info.bytes;
            total_yaml_size = total_yaml_size + yaml_info.bytes;
            
            n_success = n_success + 1;
            
        catch err
            fprintf('✗ Failed: %s\n  Error: %s\n\n', xml_file, err.message);
            n_failed = n_failed + 1;
        end
    end
    
    % Summary
    fprintf('\n╔════════════════════════════════════════════════════════╗\n');
    fprintf('║  Conversion Summary                                  ║\n');
    fprintf('╠════════════════════════════════════════════════════════╣\n');
    fprintf('║  Successfully converted: %2d files                    ║\n', n_success);
    fprintf('║  Failed:                 %2d files                    ║\n', n_failed);
    fprintf('║  Skipped (not found):    %2d files                    ║\n', n_skipped);
    fprintf('╠════════════════════════════════════════════════════════╣\n');
    fprintf('║  Total XML size:  %8d bytes                   ║\n', total_xml_size);
    fprintf('║  Total YAML size: %8d bytes                   ║\n', total_yaml_size);
    
    if total_yaml_size < total_xml_size
        reduction = 100 * (1 - total_yaml_size / total_xml_size);
        fprintf('║  Overall reduction: %.1f%%                          ║\n', reduction);
    end
    
    fprintf('╚════════════════════════════════════════════════════════╝\n\n');
    
    if n_success > 0
        fprintf('✓ YAML files created in their original directories:\n');
        fprintf('  • Input/ (ACTIVE FILES - main input directory)\n');
        fprintf('  • DCEP_IO_Def/Input/ (templates/definitions)\n');
        fprintf('  • DCEP_IO_Def/BU/ (backups)\n');
        fprintf('  • DCEP_IO_Def/Output/ (output templates)\n');
        fprintf('  • Database/ (reference data)\n');
        fprintf('  • Documentation/Example Files/Input/ (examples)\n\n');
        fprintf('You can now use either .xml or .yaml files\n\n');
    end
end