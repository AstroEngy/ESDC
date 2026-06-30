% evolve_population — Advance every lineage by one evolutionary generation
%
% PURPOSE:
%   Mutates each individual in the current population, evaluates the
%   physical validity of the resulting design (mass budget, power system,
%   propulsion sizing, hard constraints), decides whether the mutation was
%   an improvement, and checks whether each lineage has converged.
%
% INTENT:
%   One call = one generation step for all cases × all seeds.
%   The function is intentionally self-contained: it receives the full
%   generation history as read-only context (for lineage analysis and
%   convergence testing) and returns only the new population.
%
%   Physical evaluation pipeline per individual:
%     1. mutate_individual  — randomly modify one DOF (c_e / thrust / propellant /
%                             propulsion_system).
%     2. SMAD_scalings      — recompute all subsystem masses and powers.
%     3. analysis_power_system — update power generation sizing (PV, battery).
%     4. mass_budget_propulsion — refine propulsion system mass (tank, thruster, PPU).
%     5. margin accounting  — redistribute propulsion and power mass delta to margin.
%     6. Hard-constraint rejection — NaN values, payload floor, thrust_min.
%     7. Fitness evaluation — improvement test relative to lineage history.
%     8. test_lineage_convergence_simple — check if lineage has converged.
%
% Parameters:
%   input           (struct): Mission parameters (input_case with .orbit).
%   db_data         (struct): Hardware DB and DOF definitions.
%   config          (struct): Simulation settings (evolver, output).
%   generation_data (cell):   Full generation history up to this point.
%   runID           (integer): For progress logging.
%
% Returns:
%   generation_new (struct array [n_cases × n_seeds]): New generation.
%   convergence    (logical): 1 when ALL lineages have converged.
%
% HOW TO TEST:
%   1. Pass a converged individual (convergence==1); verify it passes through
%      unchanged (no mutation applied).
%   2. Verify that an individual with NaN c_e gets evolution_success=0.
%   3. Verify that an individual whose thrust < thrust_min gets rejected.
%   4. Verify that required_mass_payload constraint rejects under-payload designs.
%   5. After many generations, check that m_margin >= 0 for all individuals.
%
% SAFEGUARDS ALREADY IN PLACE:
%   - NaN c_e/thrust hard-reject.
%   - Payload mass/power floor hard-reject.
%   - thrust_min hard-reject (mission time constraint).
%   - m_margin clamped to 0 rather than allowed to go negative.
%
% SAFEGUARDS TO ADD (future work):
%   - Assert mass_total > 0 and power_total > 0 after SMAD_scalings.
%   - Log the distribution of accepted/rejected mutations per generation
%     to detect pathological input configurations early.
function [generation_new, convergence] = evolve_population(input, db_data, config, generation_data,runID)
  population = struct();                                                        % Initialize population struct

  %Number of cases parallely simulated
  n_cases = size(input.Satellite_parameters.input_case,2);                      % Number of different simulation cases, potential for paralelisation here
  n_seeds = config.Simulation_parameters.evolver.seed_points;                   % Number of seed points or lineages

  for i=1:n_cases                                                               % Loop  over cases
    for j=1:n_seeds                                                             % Loop over seeds or lineages
      if generation_data{end}(i,j).convergence == 1
        population(i,j) = generation_data{end}(i,j);                            % keep converged lineages fixed — no further mutation needed
        continue;
      end

      % Point to the best individual in this lineage (may be older than the
      % last generation if recent mutations were all improvements-free).
      n_successor = generation_data{end}(i,j).n_success;                        % Index of latest succesfull generation, i.e. ignore newer but worse generations
      parent_individual = generation_data{n_successor}(i,j);

      % ---- Step 1: Mutate one random DOF ----------------------------------
      population(i,j) = mutate_individual(input, db_data, config, parent_individual);       % here all system mutations handled

      % ---- Step 2: Recompute all subsystem masses and powers (SMAD) -------
      [population(i,j).subsystem_masses population(i,j).subsystem_powers]= SMAD_scalings(population(i,j));

      % ---- Step 3: Update power system sizing for this orbit/design point -
      population(i,j).system.power = analysis_power_system(population(i,j), input.Satellite_parameters.input_case{i}, db_data, config);
      population(i,j).orbit = input.Satellite_parameters.input_case{i}.orbit;

      % ---- Step 4: Refine propulsion mass budget --------------------------
      % mass_budget_propulsion returns per-component masses (tank, thruster, PPU)
      % which are more accurate than the generic SMAD fraction.
      EP_scalings = mass_budget_propulsion(population(i,j), population(i,j).subsystem_masses.mass_propellant, db_data);

      % Delta between refined propulsion mass and the SMAD estimate.
      % Positive d_EP means the real system is heavier than SMAD predicted.
      d_EP =  EP_scalings.total - population(i,j).subsystem_masses.mass_propulsion;

      population(i,j).subsystem_masses.mass_propulsion = EP_scalings.total;

      population(i,j).subsystem_masses.propulsion.m_tank      =  EP_scalings.tank;
      population(i,j).subsystem_masses.propulsion.m_thruster  =  EP_scalings.thruster;
      if isfield(EP_scalings,'PPU')
        population(i,j).subsystem_masses.propulsion.m_PPU       =  EP_scalings.PPU;
      end

      %TODO - recalculate power
      %TODO - reiterate power system sizing

      % ---- Step 5: Redistribute mass delta to margin ----------------------
      % If propulsion grew heavier, it comes from margin.
      population(i,j).subsystem_masses.m_margin = population(i,j).subsystem_masses.m_margin-d_EP;  %TODO: THINK HERE
      if population(i,j).subsystem_masses.m_margin < 0
          % Margin fully consumed: clamp to 0.  Total mass will be slightly
          % over-budget; a more rigorous treatment would grow mass_total.
          population(i,j).subsystem_masses.m_margin = 0;
          %TODO better handling here
      end

      d_powersys = population(i,j).subsystem_powers.propulsion_power - population(i,j).propulsion_power;

      if population(i,j).subsystem_powers.propulsion_power< population(i,j).propulsion_power
        population(i,j).subsystem_powers.propulsion_power = population(i,j).propulsion_power;
      end

      % Recompute total power as the sum of all subsystem powers (subsystem
      % index 1 is power_total itself, so start from index 2).
      power_fields = fieldnames(population(i,j).subsystem_powers);
      p_new = 0;
      for k=2:numel(power_fields)    %start with 2 as 1 is power_total itself
        p_new = p_new+population(i,j).subsystem_powers.(power_fields{k,1});
      end
      population(i,j).subsystem_powers.power_total= p_new;

      % Update power system mass to reflect new total power demand.
      sc_type = input.Satellite_parameters.input_case{i}.derived.sc_type;
      m_pow_1 = population(i,j).subsystem_masses.mass_power;
      population(i,j).subsystem_masses.mass_power = scale_SMAD_parameter(population(i,j).subsystem_powers.power_total, sc_type, "power_total", "fraction_mass_power")*population(i,j).mass;
      d_m_pow = m_pow_1-  population(i,j).subsystem_masses.mass_power;

      population(i,j).subsystem_masses.m_margin = population(i,j).subsystem_masses.m_margin-d_m_pow;
      if population(i,j).subsystem_masses.m_margin <0
          population(i,j).subsystem_masses.m_margin =0;    %TODO: THINK HERE
      end

      % Recompute total dry mass (fields 4..end-1; first 3 are m_dry_nomargin,
      % m_margin, m_dry_margin; last 1 is the nested propulsion sub-struct).
      mass_fields =  fieldnames(population(i,j).subsystem_masses);
      m_new=0;
      for k=4:numel(mass_fields)-1    %start with 4 as three previous fields are irrelvant -1 is another struct - beware!
        m_new = m_new+population(i,j).subsystem_masses.(mass_fields{k,1});
      end
      population(i,j).subsystem_masses.m_dry_margin = m_new;

      population(i,j).subsystem_masses.m_dry_nomargin = population(i,j).mass-population(i,j).subsystem_masses.mass_propellant;
      population(i,j).subsystem_masses.m_margin = population(i,j).subsystem_masses.m_dry_nomargin-population(i,j).subsystem_masses.m_dry_margin;

      % ---- Step 6: Select fitness criterion and evaluate ------------------
      % Fitness criterion is configurable; default maximises dry mass margin
      % (most slack in the mass budget → most robust design).
      % Options: 'maximize_mass_margin' | 'maximize_payload_mass' | 'minimize_total_mass'
      if isfield(config.Simulation_parameters.evolver, 'fitness_criterion')
        fitness_criterion = config.Simulation_parameters.evolver.fitness_criterion;
      else
        fitness_criterion = 'maximize_mass_margin';
      end

      % For minimize_total_mass: retain 20% of m_dry_nomargin as minimum margin;
      % shed anything above that so total mass reflects propulsion efficiency gains.
      if strcmp(fitness_criterion, 'minimize_total_mass')
        min_margin = 0.20 * population(i,j).subsystem_masses.m_dry_nomargin;
        excess_margin = population(i,j).subsystem_masses.m_margin - min_margin;
        if excess_margin > 0
          population(i,j).mass = population(i,j).mass - excess_margin;
          population(i,j).subsystem_masses.m_margin = min_margin;
        end
      end

      population(i,j).system_geometry = volume_scalings(population(i,j));
      population(i,j).mission_parameters = mission_parameters(population(i,j));

      % Recompute minimum thrust from mission/maneuver time constraint
      % (mass_propellant and c_e may have changed since the parent was seeded)
      population(i,j).thrust_min = derive_thrust_min_from_time(population(i,j), input.Satellite_parameters.input_case{i}, config);

      % Determine fitness: compare individual against lineage history.
      lineage = get_lineage(generation_data, i, j);
      if strcmp(fitness_criterion, 'maximize_payload_mass')
        population(i,j).evolution_success = test_maximize_parameter(population(i,j), lineage, {'subsystem_masses','mass_payload'});
      elseif strcmp(fitness_criterion, 'minimize_total_mass')
        population(i,j).evolution_success = test_minimize_parameter(population(i,j), lineage, {'mass'});
      else  % default: 'maximize_mass_margin'
        population(i,j).evolution_success = test_maximize_parameter(population(i,j), lineage, {'subsystem_masses','m_margin'});
      end

      % ---- Step 7: Hard-constraint rejection ------------------------------
      % These checks override fitness: a physically invalid individual can
      % never be accepted regardless of its fitness score.

      % Reject individuals with NaN c_e or thrust — invalid propulsion solution.
      % Exception: sc_type==1 ('No Propulsion') where these fields are not applicable.
      sc_type_i = input.Satellite_parameters.input_case{i}.derived.sc_type;
      mutation_valid = true;
      if sc_type_i ~= 1 && (isnan(population(i,j).c_e) || isnan(population(i,j).thrust))
        population(i,j).evolution_success = 0;
        mutation_valid = false;
      end

      % Hard-reject mutations that violate a user-given payload mass floor.
      % Only enforced when required_mass_payload was explicitly provided as input;
      % when empty (payload is a free variable) no constraint is applied.
      req_m_pl = population(i,j).required_mass_payload;
      if ~isempty(req_m_pl) && ~isnan(req_m_pl) && req_m_pl > 0
        if population(i,j).subsystem_masses.mass_payload < req_m_pl
          population(i,j).evolution_success = 0;
          mutation_valid = false;
        end
      end

      % Hard-reject mutations that violate a user-given payload power floor.
      req_p_pl = population(i,j).required_power_payload;
      if ~isempty(req_p_pl) && ~isnan(req_p_pl) && req_p_pl > 0
        if population(i,j).subsystem_powers.power_payload < req_p_pl
          population(i,j).evolution_success = 0;
          mutation_valid = false;
        end
      end

      % Hard-reject mutations that violate the mission time constraint.
      % F_min = m_prop * c_e / t_burn_max ensures maneuver fits within allowed burn time.
      thrust_min_req = population(i,j).thrust_min;
      if sc_type_i ~= 1 && ~isnan(thrust_min_req) && thrust_min_req > 0 ...
          && population(i,j).thrust < thrust_min_req
        population(i,j).evolution_success = 0;
        mutation_valid = false;
      end

      % ---- Step 8: Convergence bookkeeping --------------------------------
      % No-op mutations (parent and child are numerically identical) are excluded
      % from the convergence counter to avoid premature stall detection.
      mutation_changed = false;
      if ~strcmp(population(i,j).propulsion_system, parent_individual.propulsion_system)
        mutation_changed = true;
      elseif ~strcmp(population(i,j).propellant, parent_individual.propellant)
        mutation_changed = true;
      elseif abs(population(i,j).c_e - parent_individual.c_e) > max(1, abs(parent_individual.c_e))*1e-12
        mutation_changed = true;
      elseif abs(population(i,j).thrust - parent_individual.thrust) > max(1, abs(parent_individual.thrust))*1e-12
        mutation_changed = true;
      end
      population(i,j).count_for_convergence = double(mutation_valid && mutation_changed);
      population(i,j).convergence_mode = 'active';

      % Record the generation index of the new best solution (used by evolver
      % to retrieve the globally best individual after the loop ends).
      if population(i,j).evolution_success== 1
        population(i,j).n_success = size(generation_data,2)+1;
      end

       %test for convergence here, maybe add number of non convergence gere
      [population(i,j).convergence, population(i,j).convergence_mode] = test_lineage_convergence_simple(population(i,j), lineage, config);  % add a parmeter specific epsilon convergence test
    end
  end

  %aggregate output
  generation_new = population;

  %full convergence testing is done here.
  [convergence n_convergence] = test_full_convergence(population);


if ~mod(size(generation_data, 2), config.Simulation_parameters.output.CLI.n_verbosity)
    n_total = size(input.Satellite_parameters.input_case, 2) * config.Simulation_parameters.evolver.seed_points;
    n_local_optimum = 0; n_stall = 0;
    for cli_i = 1:size(population,1)
      for cli_j = 1:size(population,2)
        if isfield(population(cli_i,cli_j),'convergence_mode')
          if strcmp(population(cli_i,cli_j).convergence_mode,'local_optimum'); n_local_optimum = n_local_optimum+1; end
          if strcmp(population(cli_i,cli_j).convergence_mode,'stall');          n_stall  = n_stall+1;  end
        end
      end
    end
    disp(sprintf('Converged lineages: %d / %d  (local_optimum: %d, stall: %d)', n_convergence, n_total, n_local_optimum, n_stall));
    completed_percentage = floor(n_convergence / n_total * 100);
    if completed_percentage >= 100
      completed_percentage = 99;
    end
    DCEP_log_string = strcat('DCEP_STATUS: RUNNING_', num2str(completed_percentage), '%');
    appendToLogFileDCEP(DCEP_log_string, 0,runID);
    fflush(stdout);
end

end
