function initial_population = make_population(input, database_data, configuration)
% make_population generates a randomized initial population for the evolutionary algorithm function.
%
% This function produces a randomized initial population from different starting cases.
% The initial population is created based on input parameters, database data, and configuration settings.
%
% Parameters:
%   input (struct): Structure containing input parameters for the evolutionary algorithm.
%   database_data (struct): Database data required for population initialization and evolution.
%   configuration (struct): Configuration parameters for the evolutionary algorithm.
%
% Returns:
%   initial_population (struct): Structure containing the initial population with various properties.
%
% The function performs the following steps:
%   1. Initializes the number of seeds and degrees of freedom.
%   2. Iterates over each input case and each seed to generate initial population members.
%   3. Assigns mass, total impulse, delta-v, and propulsion power values based on the input case.
%   4. Sets random case parameters for each population member.
%   5. Calculates system masses, mission parameters, mass fractions, and evolution relevant parameters.
%   6. Calculates the power system and assigns the orbit for each population member.
%
% Example:
%   initial_population = make_population(input, database_data, configuration);
%
% See also: set_random_case_parameters, SMAD_scalings, mission_parameters, mass_fractions, analysis_power_system



% Number of members of each case population.
number_of_seeds = configuration.Simulation_parameters.evolver.seed_points;

% Number of degrees of freedom.
number_of_DOF = num_struct_members_full(database_data.DOF, 'DOF');

% Initialize the initial population structure.
initial_population = struct();

% Iterate over each input case.
for i = 1:numel(input.Satellite_parameters.input_case)
      % Iterate over the number of seeds.
    for j = 1:number_of_seeds
        case_parameters = input.Satellite_parameters.input_case{i};

        % Create a temporary structure for the population member.
        population_member = struct();

        % Mass assignment with fallback to derived estimate when mass_total not given directly.
        if isfield(case_parameters, 'mass_total')
            population_member.mass = case_parameters.mass_total;
        elseif isfield(case_parameters, 'derived') && isfield(case_parameters.derived, 'unknown') && ...
               isfield(case_parameters.derived.unknown, 'mass') && isfield(case_parameters.derived.unknown.mass, 'mass_total')
            population_member.mass = case_parameters.derived.unknown.mass.mass_total;
        elseif isfield(case_parameters, 'derived') && isfield(case_parameters.derived, 'known') && ...
               isfield(case_parameters.derived.known, 'mass') && isfield(case_parameters.derived.known.mass, 'mass_total')
            population_member.mass = case_parameters.derived.known.mass.mass_total;
        else
            error('make_population: cannot determine mass_total from input or derived data for case %d', i);
        end

        % Conditional assignments if parameters are part of the input
        population_member.totalimpulse = get_field_safe(case_parameters, 'totalimpulse');
        population_member.deltav = get_field_safe(case_parameters, 'deltav');
        population_member.propulsion_power = get_field_safe(case_parameters, 'propulsion_power');
        thrust_mode = get_field_safe(case_parameters, 'thrust_mode');
        % xml2struct returns elements with attributes as struct(Attributes=..., Text='value').
        % typeset_struct only unwraps when Text is the first field; if Attributes comes first
        % the struct is left intact. Extract the text explicitly to get a plain string.
        if isstruct(thrust_mode) && isfield(thrust_mode, 'Text')
          thrust_mode = thrust_mode.Text;
        end
        if isempty(thrust_mode)
          thrust_mode = '';
        end
        population_member.thrust_mode = thrust_mode;

        % Carry the derived sc_type (orbit_height > dv priority, resolved at input_processing)
        % so that SMAD_scalings, volume_scalings, and derive_thrust_min_from_time all use the
        % same classification without re-inferring from delta-v alone.
        population_member.sc_type = case_parameters.derived.sc_type;

        % Mission time constraint fields
        population_member.mission_duration         = get_field_safe(case_parameters, 'mission_duration');        % [years]
        population_member.maneuver_duration_max    = get_field_safe(case_parameters, 'maneuver_duration_max');   % [s]
        population_member.propulsion_time_fraction = get_field_safe(case_parameters, 'propulsion_time_fraction'); % [-]

        % Payload constraints — only applied as hard evolver floors when mass_total was
        % directly given by the user.  When mass_total is absent (payload-only mode),
        % mass_payload and power_payload were the drivers for the mass estimate; they
        % must not additionally constrain the evolver or every mutation will be rejected.
        if isfield(case_parameters, 'mass_total')
          population_member.required_mass_payload  = get_field_safe(case_parameters, 'mass_payload');   % [kg]
          population_member.required_power_payload = get_field_safe(case_parameters, 'power_payload');  % [W]
        else
          population_member.required_mass_payload  = [];  % free variable: total mass already derived from payload
          population_member.required_power_payload = [];  % free variable: total mass already derived from payload
        end

      

      % determine respective random case DOF parameters
      %disp(input)
      %here issue with fractions later...
      [population_member.propulsion_system, population_member.propellant, population_member.c_e, population_member.thrust, population_member.power_thruster, population_member.power_jet, population_member.eff_PPU, population_member.eff_thruster]  = set_random_case_parameters( database_data, population_member.propulsion_power, population_member.thrust_mode);
      
      %calculate system masses and mission parameters
%     population_member.subsystem_masses = mass_budget_propulsion(population_member);
      %disp(input)
      

      [population_member.subsystem_masses,population_member.subsystem_powers] = SMAD_scalings(population_member);
      population_member.system_geometry = volume_scalings(population_member);

      % Derive minimum thrust from mission/maneuver time constraint
      population_member.thrust_min = derive_thrust_min_from_time(population_member, case_parameters, configuration);

      % Validate the initial seed against the thrust_min constraint.
      % If a seed (e.g. HET with low propulsion_power) cannot produce enough thrust
      % to meet the maneuver-time constraint, mark it infeasible: zero its mass margin
      % and set evolution_success=0 so the first valid mutation (chemical) beats it
      % in the fitness comparison.  Do NOT clamp thrust upward — the evolver must find
      % a technology that genuinely satisfies the constraint.
      thrust_min_val = population_member.thrust_min;
      seed_violates_thrust_min = population_member.sc_type ~= 1 ...
        && ~isnan(thrust_min_val) && thrust_min_val > 0 ...
        && ~isnan(population_member.thrust) && population_member.thrust < thrust_min_val;

     population_member.mission_parameters = mission_parameters(population_member);
      
      % add mission scenario parameter calculations
     population_member.mass_fractions= mass_fractions(population_member);
      
      % calculate evolution relevant parameters  
     if seed_violates_thrust_min
       population_member.evolution_success = 0;
       population_member.subsystem_masses.m_margin = 0;
       population_member.subsystem_masses.mass_payload = 0;
     else
       population_member.evolution_success = 1;
     end
     population_member.n_success = 1;
     population_member.convergence = 0;
      population_member.count_for_convergence = 0; % baseline seed should not consume failure budget
      population_member.convergence_mode = 'active';
      
     population_member.system.power = analysis_power_system(population_member, input.Satellite_parameters.input_case{i},  database_data, configuration);
     population_member.orbit = input.Satellite_parameters.input_case{i}.orbit;
     
     % Assign the temporary structure to the initial population array.
      initial_population(i,j) = population_member;
      
     % disp(population_member); % Debugging only
    end
  end
end

function value = get_field_safe(struct, field)
% Helper function to safely get a field value. Serving as a shortcut to avoid excessive isfield checking.
  if isfield(struct, field)
    value = struct.(field);
  else
    value = [];
  end
end