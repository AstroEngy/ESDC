% ==================================================================
% test_yaml_esdc.m - Test YAML parser for ESDC use cases
% Author: AstroEngy / GitHub CoPilot in semi Agentic Mode
% Date: 2025-10-30
% ==================================================================

function test_yaml_esdc()
    fprintf('\n╔════════════════════════════════════════════════════════╗\n');
    fprintf('║       ESDC YAML Parser Test Suite                   ║\n');
    fprintf('║       Date: 2025-10-30 10:11:35 UTC                 ║\n');
    fprintf('╚════════════════════════════════════════════════════════╝\n\n');
    
    % Run all tests
    passed = 0;
    failed = 0;
    
    tests = {
        @test_basic_scalars, 'Basic Scalars';
        @test_nested_structures, 'Nested Structures';
        @test_simple_lists, 'Simple Lists';
        @test_list_of_objects, 'List of Objects';
        @test_inline_arrays, 'Inline Arrays';
        @test_comments, 'Comments';
        @test_mixed_types, 'Mixed Types';
        @test_esdc_input, 'ESDC Input Format';
        @test_scaling_law, 'Scaling Law Format';
        @test_roundtrip, 'Round-trip (Write→Read)';
    };
    
    for i = 1:size(tests, 1)
        test_func = tests{i, 1};
        test_name = tests{i, 2};
        
        fprintf('Test %d/%d: %s\n', i, size(tests, 1), test_name);
        try
            test_func();
            fprintf('  ✓ PASSED\n\n');
            passed = passed + 1;
        catch err
            fprintf('  ✗ FAILED: %s\n\n', err.message);
            failed = failed + 1;
        end
    end
    
    % Summary
    fprintf('╔════════════════════════════════════════════════════════╗\n');
    fprintf('║  Test Summary                                        ║\n');
    fprintf('╠════════════════════════════════════════════════════════╣\n');
    fprintf('║  Total:  %2d tests                                    ║\n', passed + failed);
    fprintf('║  Passed: %2d tests ✓                                  ║\n', passed);
    fprintf('║  Failed: %2d tests ✗                                  ║\n', failed);
    fprintf('╚════════════════════════════════════════════════════════╝\n\n');
    
    if failed == 0
        fprintf('🎉 All tests passed!\n\n');
    else
        fprintf('⚠️  Some tests failed. Please review.\n\n');
    end

    % ========================================
    % CLEANUP: Delete all test YAML files
    % ========================================
    cleanup_test_files();
end

function cleanup_test_files()
    % Delete all test*.yaml files created during testing
    
    fprintf('Cleaning up test files...\n');
    
    test_files = {
        'test_basic.yaml',
        'test_nested.yaml',
        'test_lists.yaml',
        'test_objects.yaml',
        'test_inline.yaml',
        'test_comments.yaml',
        'test_mixed.yaml',
        'test_esdc_input.yaml',
        'test_scaling.yaml',
        'test_roundtrip.yaml'
    };
    
    deleted_count = 0;
    
    for i = 1:length(test_files)
        filename = test_files{i};
        if exist(filename, 'file')
            delete(filename);
            deleted_count = deleted_count + 1;
        end
    end
    
    fprintf('  ✓ Cleaned up %d test files\n\n', deleted_count);
end

% [Rest of your test functions remain the same...]

function test_basic_scalars()
    yaml = {...
        'string_value: Hello World', ...
        'integer_value: 42', ...
        'float_value: 3.14159', ...
        'scientific: 1.23e-5', ...
        'boolean_true: true', ...
        'boolean_false: false'};
    
    write_test_yaml('test_basic.yaml', yaml);
    data = esdc_yaml.read('test_basic.yaml');
    
    assert(strcmp(data.string_value, 'Hello World'));
    assert(data.integer_value == 42);
    assert(abs(data.float_value - 3.14159) < 1e-6);
    assert(abs(data.scientific - 1.23e-5) < 1e-10);
    assert(data.boolean_true == true);
    assert(data.boolean_false == false);
end

function test_nested_structures()
    yaml = {...
        'level1:', ...
        '  level2:', ...
        '    level3:', ...
        '      value: deep'};
    
    write_test_yaml('test_nested.yaml', yaml);
    data = esdc_yaml.read('test_nested.yaml');
    
    assert(strcmp(data.level1.level2.level3.value, 'deep'));
end

function test_simple_lists()
    yaml = {...
        'numbers:', ...
        '  - 1', ...
        '  - 2', ...
        '  - 3', ...
        'strings:', ...
        '  - alpha', ...
        '  - beta', ...
        '  - gamma'};
    
    write_test_yaml('test_lists.yaml', yaml);
    data = esdc_yaml.read('test_lists.yaml');
    
    assert(length(data.numbers) == 3);
    assert(data.numbers{1} == 1);
    assert(length(data.strings) == 3);
    assert(strcmp(data.strings{1}, 'alpha'));
end

function test_list_of_objects()
    yaml = {...
        'thrusters:', ...
        '  - name: Velarc', ...
        '    mass: 0.3', ...
        '    thrust: 0.04002', ...
        '  - name: ARTUS', ...
        '    mass: 0.732', ...
        '    thrust: 0.1069'};
    
    write_test_yaml('test_objects.yaml', yaml);
    data = esdc_yaml.read('test_objects.yaml');
    
    assert(length(data.thrusters) == 2);
    assert(strcmp(data.thrusters{1}.name, 'Velarc'));
    assert(data.thrusters{1}.mass == 0.3);
    assert(strcmp(data.thrusters{2}.name, 'ARTUS'));
end

function test_inline_arrays()
    yaml = {...
        'coefficients: [0.0012, 0.45, 2.1]', ...
        'integers: [1, 2, 3, 4, 5]', ...
        'sources: [ATOS, MR-509, ESEX]'};
    
    write_test_yaml('test_inline.yaml', yaml);
    data = esdc_yaml.read('test_inline.yaml');
    
    assert(isequal(data.coefficients, [0.0012, 0.45, 2.1]));
    assert(isequal(data.integers, [1, 2, 3, 4, 5]));
    assert(length(data.sources) == 3);
end

function test_comments()
    yaml = {...
        '# This is a file comment', ...
        'value1: 100  # Inline comment', ...
        '# Another comment', ...
        'value2: 200'};
    
    write_test_yaml('test_comments.yaml', yaml);
    data = esdc_yaml.read('test_comments.yaml');
    
    assert(data.value1 == 100);
    assert(data.value2 == 200);
end

function test_mixed_types()
    yaml = {...
        'mission:', ...
        '  name: "Test Mission"', ...
        '  mass: 155.5', ...
        '  active: true', ...
        '  components:', ...
        '    - thruster', ...
        '    - ppu', ...
        '  coefficients: [1, 2, 3]'};
    
    write_test_yaml('test_mixed.yaml', yaml);
    data = esdc_yaml.read('test_mixed.yaml');
    
    assert(strcmp(data.mission.name, 'Test Mission'));
    assert(data.mission.mass == 155.5);
    assert(data.mission.active == true);
    assert(length(data.mission.components) == 2);
end

function test_esdc_input()
    yaml = {...
        '# ESDC Mission Input', ...
        'satellite_parameters:', ...
        '  input_cases:', ...
        '    - name: Mission 1', ...
        '      mass_total: 155', ...
        '      deltav: 685.97', ...
        '      propulsion_power: 202.9', ...
        '    - name: Mission 2', ...
        '      mass_total: 500', ...
        '      deltav: 526.25', ...
        '      propulsion_power: 202.9'};
    
    write_test_yaml('test_esdc_input.yaml', yaml);
    data = esdc_yaml.read('test_esdc_input.yaml');
    
    assert(length(data.satellite_parameters.input_cases) == 2);
    assert(data.satellite_parameters.input_cases{1}.mass_total == 155);
    assert(data.satellite_parameters.input_cases{2}.mass_total == 500);
end

function test_scaling_law()
    yaml = {...
        'scaling_laws:', ...
        '  propulsion_system:', ...
        '    arcjet:', ...
        '      ppu:', ...
        '        mass_to_power:', ...
        '          fit:', ...
        '            type: polynomial', ...
        '            degree: 2', ...
        '            coefficients: [0.0012, 0.45, 2.1]', ...
        '          statistics:', ...
        '            r_squared: 0.982', ...
        '            rmse: 0.15', ...
        '            n_data_points: 15', ...
        '          valid_range:', ...
        '            x_min: 100.0', ...
        '            x_max: 5000.0'};
    
    write_test_yaml('test_scaling.yaml', yaml);
    data = esdc_yaml.read('test_scaling.yaml');
    
    law = data.scaling_laws.propulsion_system.arcjet.ppu.mass_to_power;
    assert(strcmp(law.fit.type, 'polynomial'));
    assert(law.fit.degree == 2);
    assert(isequal(law.fit.coefficients, [0.0012, 0.45, 2.1]));
    assert(law.statistics.r_squared == 0.982);
    assert(law.valid_range.x_min == 100.0);
end

function test_roundtrip()
    % Create structure
    original = struct();
    original.name = 'Test';
    original.value = 42.5;
    original.array = [1, 2, 3];
    original.nested.key = 'value';
    original.list = {'a', 'b', 'c'};
    
    % Write to YAML
    esdc_yaml.write('test_roundtrip.yaml', original, 'header', false);
    
    % Read back
    loaded = esdc_yaml.read('test_roundtrip.yaml');
    
    % Verify
    assert(strcmp(loaded.name, original.name));
    assert(loaded.value == original.value);
    assert(isequal(loaded.array, original.array));
    assert(strcmp(loaded.nested.key, original.nested.key));
end

function write_test_yaml(filename, lines)
    % Helper to write test YAML files
    fid = fopen(filename, 'w');
    for i = 1:length(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);
end