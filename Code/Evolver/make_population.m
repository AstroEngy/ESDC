% make_population — Create the randomised initial generation for the evolver
%
% PURPOSE:
%   Generates an [n_cases × n_seeds] struct array where each entry is a
%   randomised spacecraft design individual.  This is generation 1 of the
%   evolutionary algorithm.  Each individual has all fields needed for the
%   evolver loop: mass, propulsion parameters, SMAD scalings, orbit,
%   power system, and convergence bookkeeping.
%
% INTENT:
%   Creates diversity at the start of evolution.  Every seed for the same
%   case starts from a different random propulsion technology/propellant/c_e
%   combination sampled uniformly from the DOF space.  The evolver then
%   drives each lineage toward the fittest design from its starting point.
%
%   Mass is taken from input (mass_total) or estimated from payload/power
%   fractions if mass_total was not given (payload-only mode).
%
% Parameters:
%   input           (struct): Mission parameters.
%       .Satellite_parameters.input_case{i}: one design case with at least
%       .derived (sc_type, estimated masses/powers) and .orbit.
%   database_data   (struct): Hardware DB and DOF definitions.
%   configuration   (struct): Simulation settings.
%       .Simulation_parameters.evolver.seed_points: number of lineages.
%
% Returns:
%   initial_population (struct [n_cases × n_seeds]): First generation.
%       Each individual contains:
%         .mass                 — total wet mass [kg]
%         .propulsion_system    — selected technology string
%         .propellant           — selected propellant string
%         .c_e                  — exhaust velocity [m/s]
%         .thrust               — thrust [N]
%         .subsystem_masses     — struct with all mass breakdown fields
%         .subsystem_powers     — struct with all power breakdown fields
%         .evolution_success    — 1 if seed meets thrust_min, else 0
%         .n_success            — 1 (always first gen)
%         .convergence          — 0 (all seeds start unconverged)
%
% HOW TO TEST:
%   1. Call and verify size(initial_population) == [n_cases, n_seeds].
%   2. Verify all .mass values match the corresponding input mass_total or
%      the derived estimate.
%   3. Verify that .propulsion_system, .propellant, .c_e, .thrust are all
%      non-empty and non-NaN for sc_type != 1.
%   4. Run with a thrust_min constraint and confirm that infeasible seeds
%      have evolution_success=0 and m_margin=0.
%   5. Run 10 times with the same random_seed; verify identical output.
%
% SAFEGUARDS ALREADY IN PLACE:
%   - Error if mass_total cannot be determined from input or derived fields.
%   - Infeasible seeds (thrust_min violated) marked evolution_success=0.
%
% SAFEGUARDS TO ADD (future work):
%   - Warn if all seeds for a case are infeasible at generation 1 (indicates
%     the input constraints are likely unsatisfiable).
%   - Validate that .subsystem_masses sums are internally consistent.

function initial_population = make_population(input, database_data, configuration)



% Number of members of each case population.
number_of_seeds = configuration.Simulation_parameters.evolver.seed_points;

% Number of degrees of freedom (total across all propulsion types in DOF file).
number_of_DOF = num_struct_members_full(database_data.DOF, 'DOF');

% Initialise the output population struct array (will be filled in loop).
initial_population = struct();

% ---- Outer loop: one set of seeds per input case -------------------------
for i = 1:numel(input.Satellite_parameters.input_case)
      % ---- Inner loop: generate each random seed -------------------------
    for j = 1:number_of_seeds
        case_parameters = input.Satellite_parameters.input_case{i};

        population_member = struct();

        % ---- Mass assignment --------------------------------------------
        % Priority: explicit mass_total > derived unknown total > derived known total.
        % The last two arise from payload-only or power-only input modes where
        % input_processing estimated the total mass via SMAD fractions.
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

        % ---- Mission constraint fields ----------------------------------
        % These are passed through from the input; may be empty if not given.
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

      

      % ---- Random propulsion parameter selection --------------------------
      % Samples one random propulsion technology + parameters from the DB.
      [population_member.propulsion_system, population_member.propellant, population_member.c_e, population_member.thrust, population_member.power_thruster, population_member.power_jet, population_member.eff_PPU, population_member.eff_thruster]  = set_random_case_parameters( database_data, population_member.propulsion_power, population_member.thrust_mode);
      
      % ---- Physical sizing ------------------------------------------------
      [population_member.subsystem_masses,population_member.subsystem_powers] = SMAD_scalings(population_member);
      population_member.system_geometry = volume_scalings(population_member);

      % ---- Thrust-min constraint check ------------------------------------
      % Derive the minimum thrust needed to complete the maneuver within the
      % allowed burn time.  Infeasible seeds are marked but kept in the
      % population so the evolver can find a better mutation from generation 2.
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
     population_member.mass_fractions= mass_fractions(population_member);
      
      % ---- Convergence bookkeeping ----------------------------------------
      % Seeds that violate thrust_min start with zero fitness; the evolver
      % will immediately seek better mutations.
     if seed_violates_thrust_min
       population_member.evolution_success = 0;
       population_member.subsystem_masses.m_margin = 0;
       population_member.subsystem_masses.mass_payload = 0;
     else
       population_member.evolution_success = 1;
     end
     population_member.n_success = 1;     % first generation = generation index 1
     population_member.convergence = 0;   % no seed starts converged
     population_member.count_for_convergence = 0; % baseline seed should not consume failure budget
     population_member.convergence_mode = 'active';
      
     % ---- Power system analysis ------------------------------------------
     population_member.system.power = analysis_power_system(population_member, input.Satellite_parameters.input_case{i},  database_data, configuration);
     population_member.orbit = input.Satellite_parameters.input_case{i}.orbit;
     
     initial_population(i,j) = population_member;
    end
  end
end

% get_field_safe — Return a struct field value or empty if missing
%
% PURPOSE:
%   Avoids verbose isfield() + struct.(field) boilerplate at every optional-
%   field access site.  Returns [] when the field is absent so callers can
%   use isempty() checks without risking a 'reference to non-existent field' error.
%
% Parameters:
%   struct (struct): Any struct.
%   field  (string): Field name to look up.
%
% Returns:
%   value: struct.(field) if the field exists, [] otherwise.
function value = get_field_safe(struct, field)
  if isfield(struct, field)
    value = struct.(field);
  else
    value = [];
  end
end