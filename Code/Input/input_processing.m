% =========================================================================
% INPUT PROCESSING
% =========================================================================
% Main function to read and process all input data including mission
% parameters, database, and simulation parameters. Performs adaptive
% preprocessing and system completion estimation.
%
% Outputs:
%   mission_parameters     - Structure containing mission configuration
%   database              - Reference data and degrees of freedom
%   simulation_parameters - Simulation configuration settings

function [mission_parameters, database, simulation_parameters] = input_processing()
    
    % ===== Input Reading =====
    mission_parameters = read_input_mission_parameter();
    
    database = read_reference_data();
    database.DOF = read_DOF();
    
    simulation_parameters = read_input_simulation_parameter();
    
    disp(' ')
    disp('Input Reading complete')
    disp(' ')
    
    % ===== Adaptive Preprocessing =====
    disp('Adaptive Input Preprocessing')
    disp(' ')
    
    % Process each input case
    % TODO: Add loop for multiple cases
    input_cases = mission_parameters.Satellite_parameters.input_case;
    
    for i = 1:size(input_cases, 2)
        current_case = mission_parameters.Satellite_parameters.input_case{i}(1, 1);
        
        % Add derived parameters
        current_case.derived = system_completion_estimation(current_case);
        
        % Initialize orbit parameters
        current_case.orbit = orbit_initialize(current_case, simulation_parameters);
        
        mission_parameters.Satellite_parameters.input_case{i}(1, 1) = current_case;
    end
    
end


% =========================================================================
% SYSTEM COMPLETION ESTIMATION
% =========================================================================
% Estimates unknown system parameters (mass and power) based on available
% data using SMAD correlations and spacecraft type determination
%
% Inputs:
%   inputs - Structure containing known system parameters
%
% Outputs:
%   derived_parameters - Structure with known/unknown categorized data

function [derived_parameters] = system_completion_estimation(inputs)
    
    derived_parameters = struct;
    
    % ===== Define Available Fields =====
    
    % Mass parameters (may be definable in external file)
    mass_fields = {
        'mass_total'
        'mass_payload'
        'mass_structmech'
        'mass_thermal'
        'mass_power'
        'mass_TTC'
        'mass_ADC'
        'mass_propulsion'
        'mass_other'
    };
    
    % Power parameters
    power_fields = {
        'power_total'
        'power_payload'
        'power_structmech'
        'power_thermal'
        'power_power'
        'power_TTC'
        'power_ADC'
        'propulsion_power'
    };
    
    % ===== Categorize Known and Unknown Parameters =====
    
    known = struct();
    unknown = struct();
    
    % Categorize mass fields
    for i = 1:numel(mass_fields)
        field_name = mass_fields{i};
        if isfield(inputs, field_name)
            known.mass.(field_name) = inputs.(field_name);
        else
            unknown.mass.(field_name) = 0;
        end
    end
    
    % Categorize power fields
    for i = 1:numel(power_fields)
        field_name = power_fields{i};
        if isfield(inputs, field_name)
            known.power.(field_name) = inputs.(field_name);
        else
            unknown.power.(field_name) = 0;
        end
    end
    
    % ===== Spacecraft Type Determination =====
    
    if isfield(inputs, 'deltav')
        data.dv = inputs.deltav;
        sc_type = determine_sc_type(data);
    else
        sc_type = 1;
    end
    derived_parameters.sc_type = sc_type;
    
    % ===== Validate Input Sufficiency =====
    
    if ~isfield(known, 'power') && ~isfield(known, 'mass')
        disp(' ')
        disp('If anything would be known - yeah - that would be great');
        disp('Define at least one system or mass - quitting ESDC');
        error('Insufficient knowns');
    end
    
    % ===== System Estimation =====
    
    % TODO: Make this a config parameter
    margin = 0.3;
    
    % Route to appropriate estimation method based on available data
    if isfield(known, 'mass') && isfield(known.mass, 'mass_total')
        [known, unknown] = system_with_known_mass_total(known, unknown, margin, sc_type);
    elseif isfield(known, 'power') && isfield(known.power, 'power_total')
        [known, unknown] = system_with_known_totalpower(known, unknown, margin, sc_type);
    elseif isfield(unknown.mass, 'mass_total') && isfield(unknown.power, 'power_total')
        [known, unknown] = system_with_unknown_totals(known, unknown, margin, sc_type);
    end
    
    derived_parameters.known = known;
    derived_parameters.unknown = unknown;
    
end


% =========================================================================
% SYSTEM WITH UNKNOWN TOTALS
% =========================================================================
% Estimates total mass and power when both are unknown, starting from
% known subsystem masses or powers

function [known, unknown] = system_with_unknown_totals(known, unknown, margin, sc_type)
    
    if isfield(known, 'mass')
        % ===== Estimate Total Mass from Known Subsystem Masses =====
        
        known_mass_fields = fieldnames(known.mass);
        
        % Calculate fractions and sum of known masses
        total_known_mass = 0;
        fractions = [];
        
        for i = 1:numel(known_mass_fields)
            field_name = known_mass_fields{i};
            mass_value = known.mass.(field_name);
            
            fraction = scale_SMAD_parameter_inverse_fraction(...
                mass_value, sc_type, 'mass_total', ['fraction_' field_name]);
            
            fractions = [fractions, fraction];
            total_known_mass = total_known_mass + mass_value;
        end
        
        total_known_fractions = sum(fractions);
        
        % Derive total mass estimates
        unknown.mass.mass_total_margin = total_known_mass / total_known_fractions;
        unknown.mass.mass_total = unknown.mass.mass_total_margin / (1 - margin);
        unknown.mass.m_margin = unknown.mass.mass_total - unknown.mass.mass_total_margin;
        
        % ===== Estimate Unknown Subsystem Masses =====
        
        unknown_mass_fields = fieldnames(unknown.mass);
        
        for i = 1:numel(unknown_mass_fields)
            field_name = unknown_mass_fields{i};
            if ~strcmp(field_name, 'mass_total')
                fraction = scale_SMAD_parameter(...
                    unknown.mass.mass_total_margin, sc_type, ...
                    'mass_total', ['fraction_' field_name]);
                
                unknown.mass.(field_name) = fraction * unknown.mass.mass_total_margin;
            end
        end
        
        % ===== Estimate All Subsystem Powers =====
        
        power_total_relevant = scale_SMAD_parameter(...
            unknown.mass.mass_total_margin, sc_type, 'mass_total', 'power_total');
        
        unknown_power_fields = fieldnames(unknown.power);
        
        for i = 1:numel(unknown_power_fields)
            field_name = unknown_power_fields{i};
            if ~strcmp(field_name, 'power_total')
                fraction = scale_SMAD_parameter(...
                    unknown.mass.mass_total_margin, sc_type, ...
                    'mass_total', ['fraction_' field_name]);
                
                unknown.power.(field_name) = fraction * power_total_relevant;
            end
        end
        
        % ===== Update Total Power =====
        
        new_power_total = sum_powers(known.power, unknown.power);
        
        if isfield(unknown.power, 'power_total')
            unknown.power.power_total = new_power_total;
        elseif isfield(known.power, 'power_total')
            if new_power_total > known.power.power_total
                disp('')
                disp(sprintf('Info: Total power estimate increased to %.1f W', new_power_total));
                disp('')
                known.power.power_total = new_power_total;
            else
                known.power.p_margin = known.power.power_total - new_power_total;
                known.power.power_total_margin = new_power_total;
            end
        end
        
        % Update power system mass
        unknown.mass.mass_power = scale_SMAD_parameter(...
            new_power_total, sc_type, 'power_total', 'fraction_mass_power') ...
            * unknown.mass.mass_total_margin;
        
        % Validate total mass
        [unknown.mass.mass_total, unknown.mass.m_margin, unknown.mass.mass_total_margin] = ...
            mass_validate(known.mass, unknown.mass);
        
    else
        % ===== Estimate from Powers to Total Power to Masses =====
        
        known_power_fields = fieldnames(known.power);
        
        % Calculate fractions and sum of known powers
        total_known_power = 0;
        fractions = [];
        
        for i = 1:numel(known_power_fields)
            field_name = known_power_fields{i};
            power_value = known.power.(field_name);
            
            fraction = scale_SMAD_parameter_inverse_fraction(...
                power_value, sc_type, 'power_total', ['fraction_' field_name]);
            
            fractions = [fractions, fraction];
            total_known_power = total_known_power + power_value;
        end
        
        total_known_fractions = sum(fractions);
        unknown.power.power_total = total_known_power / total_known_fractions;
        
        % ===== Estimate Unknown Subsystem Powers =====
        
        unknown_power_fields = fieldnames(unknown.power);
        
        for i = 1:numel(unknown_power_fields)
            field_name = unknown_power_fields{i};
            if ~strcmp(field_name, 'power_total')
                fraction = scale_SMAD_parameter(...
                    unknown.power.power_total, sc_type, ...
                    'power_total', ['fraction_' field_name]);
                
                unknown.power.(field_name) = fraction * unknown.power.power_total;
            end
        end
        
        % Update total power
        new_power_total = sum_powers(known.power, unknown.power);
        
        if new_power_total > unknown.power.power_total
            disp('')
            disp(sprintf('Info: Total power estimate increased to %.1f W', new_power_total));
            disp('')
            unknown.power.power_total = new_power_total;
            unknown.power.p_margin = 0;
            unknown.power.power_total_margin = unknown.power.power_total;
        else
            unknown.power.p_margin = unknown.power.power_total - new_power_total;
            unknown.power.power_total_margin = new_power_total;
        end
        
        % ===== Derive Total Mass from Power =====
        
        unknown.mass.mass_total = scale_SMAD_parameter(...
            unknown.power.power_total, sc_type, 'power_total', 'mass_total');
        
        unknown.mass.m_margin = unknown.mass.mass_total * margin;
        unknown.mass.mass_total_margin = unknown.mass.mass_total - unknown.mass.m_margin;
        
        % ===== Estimate All Subsystem Masses =====
        
        unknown_mass_fields = fieldnames(unknown.mass);
        
        for i = 1:numel(unknown_mass_fields)
            field_name = unknown_mass_fields{i};
            if ~strcmp(field_name, 'mass_total')
                fraction = scale_SMAD_parameter(...
                    unknown.mass.mass_total_margin, sc_type, ...
                    'mass_total', ['fraction_' field_name]);
                
                unknown.mass.(field_name) = fraction * unknown.mass.mass_total_margin;
            end
        end
        
        % Recalculate total mass from subsystems
        mass_new = 0;
        for i = 1:numel(unknown_mass_fields)
            field_name = unknown_mass_fields{i};
            if ~strcmp(field_name, 'mass_total')
                mass_new = mass_new + unknown.mass.(field_name);
            end
        end
        
        unknown.mass.mass_total_margin = mass_new;
        unknown.mass.mass_total = unknown.mass.mass_total_margin * (1 + margin);
        unknown.mass.m_margin = unknown.mass.mass_total - unknown.mass.mass_total_margin;
    end
    
end


% =========================================================================
% SYSTEM WITH KNOWN TOTAL POWER
% =========================================================================
% Estimates masses and unknown powers when total power is known

function [known, unknown] = system_with_known_totalpower(known, unknown, margin, sc_type)
    
    % ===== Derive Total Mass from Total Power =====
    
    unknown.mass.mass_total = scale_SMAD_parameter(...
        known.power.power_total, sc_type, 'power_total', 'mass_total');
    
    unknown.mass.m_margin = unknown.mass.mass_total * margin;
    unknown.mass.mass_total_margin = unknown.mass.mass_total - unknown.mass.m_margin;
    
    % ===== Estimate All Unknown Subsystem Masses =====
    
    unknown_mass_fields = fieldnames(unknown.mass);
    
    for i = 1:numel(unknown_mass_fields)
        field_name = unknown_mass_fields{i};
        if ~strcmp(field_name, 'mass_total')
            fraction = scale_SMAD_parameter(...
                unknown.mass.mass_total_margin, sc_type, ...
                'mass_total', ['fraction_' field_name]);
            
            unknown.mass.(field_name) = fraction * unknown.mass.mass_total_margin;
        end
    end
    
    % ===== Estimate Unknown Powers =====
    
    if isfield(unknown, 'power')
        unknown_power_fields = fieldnames(unknown.power);
        
        % Use mass-based power correlation for consistency
        power_total_relevant = scale_SMAD_parameter(...
            unknown.mass.mass_total_margin, sc_type, 'mass_total', 'power_total');
        
        for i = 1:numel(unknown_power_fields)
            field_name = unknown_power_fields{i};
            if ~strcmp(field_name, 'power_total')
                fraction = scale_SMAD_parameter(...
                    unknown.mass.mass_total_margin, sc_type, ...
                    'mass_total', ['fraction_' field_name]);
                
                unknown.power.(field_name) = fraction * power_total_relevant;
            end
        end
        
        % ===== Update Total Power =====
        
        new_power_total = sum_powers(known.power, unknown.power);
        
        if isfield(unknown.power, 'power_total')
            unknown.power.power_total = new_power_total;
        elseif isfield(known.power, 'power_total')
            if new_power_total > known.power.power_total
                disp('')
                disp(sprintf('Info: Total power estimate increased to %.1f W', new_power_total));
                disp('')
                known.power.power_total = new_power_total;
            else
                known.power.p_margin = known.power.power_total - new_power_total;
                known.power.power_total_margin = new_power_total;
            end
        end
        
        % Update power system mass
        unknown.mass.mass_power = scale_SMAD_parameter(...
            new_power_total, sc_type, 'power_total', 'fraction_mass_power') ...
            * unknown.mass.mass_total_margin;
    end
    
    % ===== Validate Total Mass =====
    
    [known.mass.mass_total, known.mass.m_margin, known.mass.mass_total_margin] = ...
        mass_validate(known.mass, unknown.mass);
    
end


% =========================================================================
% SYSTEM WITH KNOWN TOTAL MASS
% =========================================================================
% Estimates unknown subsystem masses and powers when total mass is known

function [known, unknown] = system_with_known_mass_total(known, unknown, margin, sc_type)
    
    % ===== Calculate Mass Margin =====
    
    known.mass.m_margin = known.mass.mass_total * margin;
    known.mass.mass_total_margin = known.mass.mass_total - known.mass.m_margin;
    
    % ===== Estimate Unknown Subsystem Masses =====
    
    if isfield(unknown, 'mass')
        unknown_mass_fields = fieldnames(unknown.mass);
        
        for i = 1:numel(unknown_mass_fields)
            field_name = unknown_mass_fields{i};
            fraction = scale_SMAD_parameter(...
                known.mass.mass_total_margin, sc_type, ...
                'mass_total', ['fraction_' field_name]);
            
            unknown.mass.(field_name) = fraction * known.mass.mass_total_margin;
        end
    end
    
    % ===== Estimate Subsystem Powers =====
    
    if isfield(unknown, 'power')
        unknown_power_fields = fieldnames(unknown.power);
        
        % Use mass-based power correlation for consistency
        power_total_relevant = scale_SMAD_parameter(...
            known.mass.mass_total_margin, sc_type, 'mass_total', 'power_total');
        
        for i = 1:numel(unknown_power_fields)
            field_name = unknown_power_fields{i};
            if ~strcmp(field_name, 'power_total')
                fraction = scale_SMAD_parameter(...
                    known.mass.mass_total_margin, sc_type, ...
                    'mass_total', ['fraction_' field_name]);
                
                unknown.power.(field_name) = fraction * power_total_relevant;
            end
        end
        
        % ===== Calculate Total Power =====
        
        if isfield(known, 'power')
            new_power_total = sum_powers(known.power, unknown.power);
        else
            % Create dummy structure for sum_powers function
            dummy_power.dummy = 0;
            new_power_total = sum_powers(dummy_power, unknown.power);
        end
        
        % ===== Update Total Power =====
        
        if isfield(unknown.power, 'power_total')
            unknown.power.power_total = new_power_total;
        elseif isfield(known.power, 'power_total')
            if new_power_total > known.power.power_total
                disp('')
                disp(sprintf('Info: Total power estimate increased to %.1f W', new_power_total));
                disp('')
                known.power.power_total = new_power_total;
            else
                known.power.p_margin = known.power.power_total - new_power_total;
                known.power.power_total_margin = new_power_total;
            end
        end
        
        % Update power system mass
        unknown.mass.mass_power = scale_SMAD_parameter(...
            new_power_total, sc_type, 'power_total', 'fraction_mass_power') ...
            * known.mass.mass_total;
    end
    
    % ===== Validate Total Mass =====
    
    if isfield(unknown, 'mass')
        [known.mass.mass_total, known.mass.m_margin, known.mass.mass_total_margin] = ...
            mass_validate(known.mass, unknown.mass);
    end
    
end


% =========================================================================
% INVERSE FRACTION SCALING
% =========================================================================
% Calculates the fraction of a parameter value relative to total by
% inverse interpolation

function [fraction] = scale_SMAD_parameter_inverse_fraction(y, sc_type, x, file_parameter)
    
    % Define orbit types
    orbit_types = {'No Propulsion', 'Low Earth', 'High Earth', 'Planetary'};
    
    % Assemble filename
    scaling_file = sprintf(...
        'Database/Scaling/scaling_spacecraft_%s_parameter_%s_to_%s.csv', ...
        orbit_types{sc_type}, x, file_parameter);
    
    % Load scaling data
    if exist(scaling_file, 'file')
        data = dlmread(scaling_file, ',');
    else
        error('ERROR: File not found: %s', scaling_file);
    end
    
    % Extract fraction and x values
    fraction_values = data(3, :);
    x_values = data(4, :);
    
    % Calculate non-fractional values
    non_fractional_values = fraction_values .* x_values;
    
    % Inverse interpolation to find x and then fraction
    x_derived = interp1(non_fractional_values, x_values, y, 'linear', 'extrap');
    fraction = y / x_derived;
    
end


% =========================================================================
% SUM POWERS
% =========================================================================
% Sums all subsystem powers from known and unknown structures

function [total_power] = sum_powers(power_known, power_unknown)
    
    total_power = 0;
    
    % Sum known subsystem powers (exclude power_total)
    known_fields = fieldnames(power_known);
    for i = 1:numel(known_fields)
        field_name = known_fields{i};
        if ~strcmp(field_name, 'power_total')
            total_power = total_power + power_known.(field_name);
        end
    end
    
    % Sum unknown subsystem powers (exclude power_total)
    unknown_fields = fieldnames(power_unknown);
    for i = 1:numel(unknown_fields)
        field_name = unknown_fields{i};
        if ~strcmp(field_name, 'power_total')
            total_power = total_power + power_unknown.(field_name);
        end
    end
    
end


% =========================================================================
% MASS VALIDATION
% =========================================================================
% Validates total mass by summing all subsystem masses and recalculating
% available margin

function [mass_total, mass_margin, mass_total_margin] = mass_validate(mass_known, mass_unknown)
    
    total_subsystem_mass = 0;
    
    % Sum unknown subsystem masses (exclude totals and margin)
    unknown_fields = fieldnames(mass_unknown);
    for i = 1:numel(unknown_fields)
        field_name = unknown_fields{i};
        if ~any(strcmp(field_name, {'mass_total', 'm_margin', 'mass_total_margin'}))
            total_subsystem_mass = total_subsystem_mass + mass_unknown.(field_name);
        end
    end
    
    % Sum known subsystem masses (exclude totals and margin)
    known_fields = fieldnames(mass_known);
    for i = 1:numel(known_fields)
        field_name = known_fields{i};
        if ~any(strcmp(field_name, {'mass_total', 'm_margin', 'mass_total_margin'}))
            total_subsystem_mass = total_subsystem_mass + mass_known.(field_name);
        end
    end
    
    % Get existing total mass and margin
    if isfield(mass_unknown, 'mass_total')
        mass_total_existing = mass_unknown.mass_total;
        mass_total_margin_existing = mass_unknown.mass_total_margin;
        mass_margin_old = mass_unknown.m_margin;
    elseif isfield(mass_known, 'mass_total')
        mass_total_existing = mass_known.mass_total;
        mass_total_margin_existing = mass_known.mass_total_margin;
        mass_margin_old = mass_known.m_margin;
    end
    
    % Calculate mass difference
    mass_difference = mass_total_margin_existing - total_subsystem_mass;
    
    % Calculate new residual margin
    mass_margin = mass_margin_old + mass_difference;
    mass_total_margin = mass_total_existing - mass_margin;
    
    % Check if total mass limit exceeded
    if (total_subsystem_mass > mass_total_existing || mass_margin < 0)
        disp('Warning: Total mass limit exceeded!');
        mass_total = total_subsystem_mass;
        mass_margin = 0;
    else
        mass_total = mass_total_existing;
    end
    
end


% =========================================================================
% ORBIT INITIALIZATION
% =========================================================================
% Initializes orbit parameters based on mission inputs or defaults

function [mission_parameters] = orbit_initialize(mission_inputs, sim)
    
    mission_parameters = struct;
    
    % ===== Determine Orbit Height =====
    
    if isfield(mission_inputs, 'orbit_height')
        % Use provided orbit height (ensure minimum altitude)
        if mission_inputs.orbit_height > sim.Simulation_parameters.defaults.orbit_min
            height = mission_inputs.orbit_height;
        else
            height = sim.Simulation_parameters.defaults.orbit_min;
        end
    else
        % Use default height based on spacecraft type
        switch mission_inputs.derived.sc_type
            case 1  % No propulsion
                height = sim.Simulation_parameters.defaults.orbit.no_propulsion;
            case 2  % Low Earth Orbit
                height = sim.Simulation_parameters.defaults.orbit.Low_Earth;
            case 3  % High Earth Orbit (GEO)
                height = sim.Simulation_parameters.defaults.orbit.High_Earth;
            otherwise  % Space probe or other
                height = sim.Simulation_parameters.defaults.orbit_min;
        end
    end
    
    % ===== Calculate Orbit Parameters =====
    
    mission_parameters.orbit = orbit_parameters_Earth(height);
    
end


% =========================================================================
% function [mission_parameters database simulation_parameters]= input_processing()
%  %InputReading
%     % Mission Parameters
%     [mission_parameters] =  read_input_mission_parameter();
    
%     % Database     
%     [database]    =  read_reference_data();
%     database.DOF  =  read_DOF();
    
%     % Simulation Parameters
%     [simulation_parameters] = read_input_simulation_parameter();
    
%     disp(' ')
%     disp('Input Reading complete')
%     disp(' ')
    
%     disp('Adaptive Input Preprocessing')
%     disp(' ')
    
%     % Add derived parameters to input case
    
%     %TODO add loop for multiple cases
%     input_cases = mission_parameters.Satellite_parameters.input_case;
%     for i= 1:size(input_cases,2)
%       mission_parameters.Satellite_parameters.input_case{i}(1,1).derived = system_completion_estimation(mission_parameters.Satellite_parameters.input_case{i}(1,1));
%       mission_parameters.Satellite_parameters.input_case{i}(1,1).orbit = orbit_initialize(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
%     end
    
    
%     %disp(mission_parameters.Satellite_parameters)
% end

% function [derived_parameters]   = system_completion_estimation(inputs)
%   %disp(inputs)
%   %disp(inputs.mass_total) // field accessing example
%   derived_parameters = struct;
  
%   %Available mass fields          %may or may not be defineable in external file
%   masses = {
%   'mass_total'
%   %'mass_propellant'
%   'mass_payload'
%   'mass_structmech'
%   'mass_thermal'
%   'mass_power'
%   'mass_TTC'
%   'mass_ADC'
%   'mass_propulsion'
%   'mass_other'
%   };
  
%   %Available power fields
%   powers = {
%   'power_total'
%   'power_payload'
%   'power_structmech'
%   'power_thermal'
%   'power_power'
%   'power_TTC'
%   'power_ADC'
%   'propulsion_power'
%   };
  
%   % Create structures for known and unknown data
%   known = struct();
%   unknown = struct();
  
%   % Make structures for known and unknown inputs masses
%   for i=1:numel(masses)
%     if isfield(inputs,cellstr(masses{i}))
%       known.mass.(masses{i})=inputs.(masses{i});
%     else
%       unknown.mass.(masses{i})=0;
%     end
%   endfor
  
%   % Make structure for known and unknown input powers
%   for i=1:numel(powers)
%     if isfield(inputs,cellstr(powers{i}))
%       known.power.(powers{i})=inputs.(powers{i});
%     else
%       unknown.power.(powers{i})=0;
%     end
%   endfor

%    %disp(known)
  
% % spacecraft type derivation 
%   if isfield(inputs, 'deltav')
%     data.dv=inputs.deltav;
%     sc_type =  determine_sc_type(data);
%   else
%     sc_type = 1;
%   endif
%   derived_parameters.sc_type= sc_type;
  
%   %if no knowns, nothing to do
%   if not(isfield(known,'power')) && not(isfield(known,'mass'))
%     disp(' ')
%     disp('If anything would be known - yeah - that d great');
%     disp('Define at least one system or mass - quitting ESDC');
%     error('Insufficient knowns');
%   endif
  
%   margin = 0.3; %TODO config parameter
  
%   if isfield(known,'mass') && isfield(known.mass,'mass_total')
%     [known unknown]  = system_with_known_mass_total(known, unknown, margin, sc_type);
%   elseif isfield(known,'power') &&isfield(known.power,'power_total')
%     [known unknown] = system_with_known_totalpower(known, unknown, margin, sc_type);
%   elseif isfield(unknown.mass,'mass_total') && isfield(unknown.power,'power_total')
%     [known unknown] = system_with_unknown_totals(known, unknown, margin, sc_type);
%   endif
  
%   %disp(unknown);
%   %disp(known);
  
%   derived_parameters.known = known;
%   derived_parameters.unknown = unknown;
% endfunction

% function [known unknown]        = system_with_unknown_totals(known, unknown, margin, sc_type)
%   %known processing

%   if isfield(known,'mass')
%     unknown_parameters = fieldnames(unknown.mass);
%     known_parameters = fieldnames(known.mass);
    
%     all_known_masses = 0;
%     fracs = [];
%     for i=1:numel(known_parameters)
%     fracs = [fracs scale_SMAD_parameter_inverse_fraction(known.mass.(known_parameters{i}), sc_type, 'mass_total',strcat('fraction_', known_parameters{i}))];
%     all_known_masses = all_known_masses +known.mass.(known_parameters{i});
%     end
    
%     all_known_fractions = sum(fracs);
    
%     %get mass estimates 
%     unknown.mass.mass_total_margin = all_known_masses/all_known_fractions;
%     unknown.mass.mass_total = unknown.mass.mass_total_margin/(1-margin);
%     unknown.mass.m_margin = unknown.mass.mass_total-unknown.mass.mass_total_margin;
    
%     %get all system estimates
%     for i=1:numel(unknown_parameters)
%       if not(strcmp(unknown_parameters{i},'mass_total'))
%         unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*unknown.mass.mass_total_margin;
%       endif
%     endfor
    
%     unknown_parameters = fieldnames(unknown.power);
%     %get all system powerset
%     power_tot_relevant = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total','power_total');

%     for i=1:numel(fieldnames(unknown.power))
%         if not(strcmp(unknown_parameters{i},'power_total'))
%         unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*power_tot_relevant;
%         end
%     endfor
    
%     %restablish sum of total power
%     new_power_tot = sum_powers(known.power, unknown.power);
    
%      %update total power
%     if isfield(unknown.power, 'power_total')
%       unknown.power.power_total = new_power_tot;
%     elseif isfield(known.power, 'power_total')
%       if new_power_tot >  known.power.power_total
%         disp('')
%         disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
%         disp('')
%         known.power.power_total = new_power_tot;
%       else 
%         known.power.p_margin = known.power.power_total-new_power_tot;
%         known.power.power_total_margin = new_power_tot;
%       end
%     end
%     unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, 'power_total','fraction_mass_power')*unknown.mass.mass_total_margin;
    
%     [unknown.mass.mass_total unknown.mass.m_margin unknown.mass.mass_total_margin] = mass_validate(known.mass,unknown.mass);
%   else
%     % go from powers to total power to total mass to masses  
    
%     unknown_parameters = fieldnames(unknown.power);
%     known_parameters = fieldnames(known.power);
    
%     all_known_powers = 0;
%     fracs = [];
%     for i=1:numel(known_parameters)
%     fracs = [fracs scale_SMAD_parameter_inverse_fraction(known.power.(known_parameters{i}), sc_type, 'power_total',strcat('fraction_', known_parameters{i}))];
%     all_known_powers = all_known_powers +known.power.(known_parameters{i});
%     end
    
%     all_known_fractions = sum(fracs);
    
%     unknown.power.power_total = all_known_powers/(all_known_fractions);
    
%     unknown_parameters = fieldnames(unknown.power);
%     for i=1:numel(fieldnames(unknown.power))
%         if not(strcmp(unknown_parameters{i},'power_total'))
%         unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.power.power_total, sc_type, 'power_total',strcat('fraction_',unknown_parameters{i}))*unknown.power.power_total;
%         end   
%     endfor
    
%     new_power_tot = sum_powers(known.power, unknown.power);
    
%     if new_power_tot >  unknown.power.power_total
%         disp('')
%         disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
%         disp('')
%         unknown.power.power_total = new_power_tot;
%         unknown.power.p_margin = 0;
%         unknown.power.power_total_margin = unknown.power.power_total;
%       else 
%         unknown.power.p_margin = unknown.power.power_total-new_power_tot;
%         unknown.power.power_total_margin = new_power_tot;
%       end
    
%     %do mass total 
%       unknown.mass.mass_total= scale_SMAD_parameter(unknown.power.power_total,sc_type,'power_total', 'mass_total');
%       unknown_parameters = fieldnames(unknown.mass);
%       unknown.mass.m_margin = unknown.mass.mass_total*margin;
%       unknown.mass.mass_total_margin = unknown.mass.mass_total-unknown.mass.m_margin;
      
      
%      for i=1:numel(unknown_parameters)
%       if not(strcmp(unknown_parameters{i},'mass_total'))
%        unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*unknown.mass.mass_total_margin;
%       endif
%      endfor
     
%      mass_new=0;
%     for i=1:numel(unknown_parameters)
%       if not(strcmp(unknown_parameters{i},'mass_total'))
%       mass_new = mass_new +unknown.mass.(unknown_parameters{i});
%       endif
%     endfor
%     unknown.mass.mass_total_margin = mass_new;
%     unknown.mass.mass_total = unknown.mass.mass_total_margin*(1+margin);
%     unknown.mass.m_margin = unknown.mass.mass_total-unknown.mass.mass_total_margin;
    

%   end
%   % cases for zero known masses and zero known powerset
% endfunction 

% function [fraction]             = scale_SMAD_parameter_inverse_fraction(y,sc_type,x, file_parameter)
%   % assemble filename
  
%   orbits = {'No Propulsion','Low Earth', 'High Earth','Planetary'};
%   filename = strcat('Database/Scaling/scaling_spacecraft_',orbits{sc_type},'_parameter_',x,'_to_',file_parameter,'.csv');
  
%   if exist(filename)
%     data = dlmread(filename,",");
%     %disp(data)
%   else
%     disp(filename);
%     error(strcat('ERROR: File not found: ', filename));
%   end
  
%   frac_vals =data(3,:);
%   x_vals = data(4,:);
  
%   non_frac_vals = frac_vals.*x_vals;
  
%   x_derived= interp1(non_frac_vals,x_vals, y,'linear','extrap');
%   fraction= y/x_derived;
% endfunction



% function [known unknown]        = system_with_known_totalpower(known, unknown, margin, sc_type)               % when only total mass is known, this. % missing case with total
%     unknown_parameters = fieldnames(unknown.mass);
    
%     % get unknown total mass first % inverse search here from correlation power total to total mass 
%     unknown.mass.mass_total =  scale_SMAD_parameter(known.power.power_total, sc_type, 'power_total','mass_total');  % redefine as unknown here
%     unknown.mass.m_margin = unknown.mass.mass_total*margin;
%     unknown.mass.mass_total_margin = unknown.mass.mass_total- unknown.mass.m_margin;
    
%     for i=1:numel(unknown_parameters)
%       %known.mass.mass_total
%       if not(strcmp(fieldnames(unknown.mass){i},'mass_total'))
%         unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*unknown.mass.mass_total_margin;
%       end
%     endfor
    
%     %unknown power estimate handling
%     if isfield(unknown,'power')
%       unknown_parameters = fieldnames(unknown.power);
      
%       % for consistence in power estimates, do not apply a given power total
%       power_tot_relevant = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total','power_total');
      
%       for i=1:numel(fieldnames(unknown.power))
%           if not(strcmp(unknown_parameters{i},'power_total'))
%           unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*power_tot_relevant;
%           end
%       endfor

%       %restablish sum of total power
%       new_power_tot = sum_powers(known.power, unknown.power);
      
%        %update total power
%       if isfield(unknown.power, 'power_total')
%         unknown.power.power_total = new_power_tot;
%       elseif isfield(known.power, 'power_total')
%         if new_power_tot >  known.power.power_total
%           disp('')
%           disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
%           disp('')
%           known.power.power_total = new_power_tot;
%         else 
%           known.power.p_margin = known.power.power_total-new_power_tot;
%           known.power.power_total_margin = new_power_tot;
%         end
%       end
    
%     %update mass of power system
%     unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, 'power_total','fraction_mass_power')*unknown.mass.mass_total_margin;
%     end
  
%     % total mass check
%     [known.mass.mass_total known.mass.m_margin known.mass.mass_total_margin] = mass_validate(known.mass,unknown.mass);
% endfunction

% function [known unknown]        = system_with_known_mass_total(known, unknown, margin, sc_type)                % when only total mass is known, this. % missing case with total power?
  
%     if isfield(unknown,'mass')
%       %disp(unknown)
%       unknown_parameters = fieldnames(unknown.mass);
      
%       known.mass.m_margin = known.mass.mass_total*margin;
%       known.mass.mass_total_margin = known.mass.mass_total- known.mass.m_margin;
      
%       for i=1:numel(fieldnames(unknown.mass))
%         %known.mass.mass_total
%         unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*known.mass.mass_total_margin;
%       endfor
%     end 
    
    
%     %power handling
%     if isfield(unknown,'power')
%       unknown_parameters = fieldnames(unknown.power);
      
%       % for consistence in power estimates, do not apply a given power total
%       power_tot_relevant = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total','power_total');
      
%       for i=1:numel(fieldnames(unknown.power))
%           if not(strcmp(unknown_parameters{i},'power_total'))
%             unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*power_tot_relevant;
%           end
%       endfor

%       %restablish sum of total power
%       if isfield(known,'power')
%         new_power_tot = sum_powers(known.power, unknown.power);
%       else
%         standin.variable.name = 0
%         new_power_tot = sum_powers(standin.variable, unknown.power);
%       endif

    
    
%        %update total power
%       if isfield(unknown.power, 'power_total')
%         unknown.power.power_total = new_power_tot;
%       elseif isfield(known.power, 'power_total')
%         if new_power_tot >  known.power.power_total
%           disp('')
%           disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
%           disp('')
%           known.power.power_total = new_power_tot;
%         else 
%           known.power.p_margin = known.power.power_total-new_power_tot;
%           known.power.power_total_margin = new_power_tot;
%         end
%       end
      
%       %update mass of power system
%       unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, 'power_total','fraction_mass_power')*known.mass.mass_total;
%     end
%     % total mass check
%     if isfield(unknown,'mass')
%       [known.mass.mass_total known.mass.m_margin known.mass.mass_total_margin] = mass_validate(known.mass, unknown.mass);
%     end
% endfunction

% function [p_new]   = sum_powers(p_known, p_unknown)                                              % updates: the total system power input fields of known and unknown.power
  
%   % case handling if known or unknown power total
%     %disp(p_known);
%     %disp(p_unknown);
%     p_new = 0;
%     %add derived system powers
%     parameters= fieldnames(p_known);
%     for i=1:numel(parameters)
%       if not(strcmp(parameters{i},'power_total'))
%       p_new = p_new+p_known.(parameters{i});
%       end
%     end
    
%     %add known system powers
%     parameters= fieldnames(p_unknown);
%     for i=1:numel(parameters)
%       if not(strcmp(parameters{i},'power_total'))
%         p_new = p_new + p_unknown.(parameters{i});
%       end
%     end
    
% endfunction

% function [mass_total m_margin mass_total_margin] = mass_validate(m_known,m_unknown);                              % checks the applicable masses of the system, recalculates the available margin
  
%   m_new = 0;
%   % add derived system masses
%   parameters= fieldnames(m_unknown);
%   for i=1:numel(parameters)
%     if not(strcmp(parameters{i},'mass_total') || strcmp(parameters{i},'m_margin') || strcmp(parameters{i},'mass_total_margin'))
%       m_new=m_new +m_unknown.(parameters{i});
%     endif
%   endfor

%   % add known system masses
%   parameters= fieldnames(m_known);
%   for i=1:numel(parameters)
%     if not(strcmp(parameters{i},'mass_total') || strcmp(parameters{i},'m_margin') || strcmp(parameters{i},'mass_total_margin'))
%       m_new=m_new +m_known.(parameters{i});
%     endif
%   endfor

%   if isfield(m_unknown, 'mass_total')
%       m_tot         = m_unknown.mass_total;
%       m_tot_margin  = m_unknown.mass_total_margin;
%       m_margin_old  = m_unknown.m_margin;
%   elseif isfield(m_known, 'mass_total')
%       m_tot         = m_known.mass_total;
%       m_tot_margin  = m_known.mass_total_margin;
%       m_margin_old  = m_known.m_margin;
%   end
%   % compare sum to previous margin sum

%   diff_m = m_tot_margin - m_new;
  
%   %new residual margin mass 
%   m_margin = m_margin_old + diff_m;
%   mass_total_margin = m_tot - m_margin; 

%   if (m_new > m_tot || m_margin < 0)
%     disp('Warning: Total mass limit exceeded!');
%     mass_total = m_new;
%     m_margin =0;
%   else 
%     mass_total  = m_tot;
%   endif

% endfunction


% function [mission_parameters] = orbit_initialize(mission_inputs, sim)
%   mission_parameters = struct;
%   %disp(mission_inputs)
%   %disp(sim.Simulation_parameters)
%   if isfield(mission_inputs,'orbit_height')                                                                  % case for given orbit height
%     if (mission_inputs.orbit_height > sim.Simulation_parameters.defaults.orbit_min)                           % compare if min is correct
%       height = mission_inputs.orbit_height;
%     else
%       height = sim.Simulation_parameters.defaults.orbit_min;
%     end
%     mission_parameters.orbit =  orbit_parameters_Earth(height);
%   else                                                                                                      % case for unknown orbit height, but use default from orbit type (no prop, LEO, GEO, probe)
%     if mission_inputs.derived.sc_type == 1
%       height = sim.Simulation_parameters.defaults.orbit.no_propulsion;
%     elseif mission_inputs.derived.sc_type == 2
%       height = sim.Simulation_parameters.defaults.orbit.Low_Earth;
%     elseif mission_inputs.derived.sc_type == 3
%       height = sim.Simulation_parameters.defaults.orbit.High_Earth;
%     else
%       height = sim.Simulation_parameters.defaults.orbit_min;
%     end           
%     mission_parameters.orbit =  orbit_parameters_Earth(height);    % missing case for space probe
%   end
%   %disp(height)
%   %disp(mission_parameters)
%   % if not, do estimate by orbit type bla 
  
% endfunction
