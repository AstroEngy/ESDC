%Function to advance the population by one generation. Generates newly mutated system variant. All members of a generation are the current population.
function [generation_new, convergence] = evolve_population(input, db_data, config, generation_data,runID)
  population = struct();                                                        % Initialize population struct

  %Number of cases parallely simulated
  n_cases = size(input.Satellite_parameters.input_case,2);                      % Number of different simulation cases, potential for paralelisation here
  n_seeds = config.Simulation_parameters.evolver.seed_points;                   % Number of seed points or lineages

  for i=1:n_cases                                                               % Loop  over cases
    for j=1:n_seeds                                                             % Loop over seeds or lineages
      if generation_data{end}(i,j).convergence == 1
        population(i,j) = generation_data{end}(i,j);                            % keep converged lineages fixed
        continue;
      end

      n_successor = generation_data{end}(i,j).n_success;                        % Index of latest succesfull generation, i.e. ignore newer but worse generations
      parent_individual = generation_data{n_successor}(i,j);

      %mutation handling is done here
      population(i,j) = mutate_individual(input, db_data, config, parent_individual);       % here all system mutations handled

      %refresh other system data
      [population(i,j).subsystem_masses population(i,j).subsystem_powers]= SMAD_scalings(population(i,j));
      %disp(input.Satellite_parameters.input_case{i});

      population(i,j).system.power = analysis_power_system(population(i,j), input.Satellite_parameters.input_case{i}, db_data, config);
      population(i,j).orbit = input.Satellite_parameters.input_case{i}.orbit;
      %analysis_ADC
      %analysis_TTC
      %analysis_OBC
      %analysis_TC

      %population(i,j).subsystem_masses = = mass_budget_propulsion(population(i,j), db_data);
      % here problem because inconsistent with fields of SMAD scaling format

      % add function to overwrite .subsystem_masses.propulsion with new mass()
      % add remaining mass to margin or payload ...or remove from total mass...potential for reiterate
      % change evolutionary fitness condition for minimal mass? or from maximum margin+payload mass?
      EP_scalings = mass_budget_propulsion(population(i,j), population(i,j).subsystem_masses.mass_propellant, db_data);

      %Calculate diff between smad and tool
      d_EP =  EP_scalings.total - population(i,j).subsystem_masses.mass_propulsion;

      population(i,j).subsystem_masses.mass_propulsion = EP_scalings.total;

      population(i,j).subsystem_masses.propulsion.m_tank      =  EP_scalings.tank;
      population(i,j).subsystem_masses.propulsion.m_thruster  =  EP_scalings.thruster;
      if isfield(EP_scalings,'PPU')
        population(i,j).subsystem_masses.propulsion.m_PPU       =  EP_scalings.PPU;
      end

      %TODO - recalculate power
      %TODO - reiterate power system sizing

      %adjust available margin mass accordingly

      population(i,j).subsystem_masses.m_margin = population(i,j).subsystem_masses.m_margin-d_EP;  %TODO: THINK HERE
      if population(i,j).subsystem_masses.m_margin < 0
          %disp('Alert system margin fully consumed by propulsion system')
          %population(i,j).mass = population(i,j).mass-population(i,j).subsystem_masses.m_margin;
          population(i,j).subsystem_masses.m_margin = 0;
          %TODO better handling here
      end

      d_powersys = population(i,j).subsystem_powers.propulsion_power - population(i,j).propulsion_power;

      if population(i,j).subsystem_powers.propulsion_power< population(i,j).propulsion_power
        population(i,j).subsystem_powers.propulsion_power = population(i,j).propulsion_power;
      end

      %update power_total
      power_fields = fieldnames(population(i,j).subsystem_powers);
      p_new = 0;
      for k=2:numel(power_fields)    %start with 2 as 1 is power_total itself
        p_new = p_new+population(i,j).subsystem_powers.(power_fields{k,1});
      end
%      disp(population(i,j).subsystem_powers.power_total)
%      disp(p_new)
%
%      frac_pow12 = p_new/population(i,j).subsystem_powers.power_total;
      population(i,j).subsystem_powers.power_total= p_new;
%
%      population(i,j).subsystem_masses.mass_power= population(i,j).subsystem_masses.mass_power*(frac_pow12-1);
%      disp(population(i,j).subsystem_masses.mass_power)
      sc_type = input.Satellite_parameters.input_case{i}.derived.sc_type;
      m_pow_1 = population(i,j).subsystem_masses.mass_power;
      population(i,j).subsystem_masses.mass_power = scale_SMAD_parameter(population(i,j).subsystem_powers.power_total, sc_type, "power_total", "fraction_mass_power")*population(i,j).mass;
      d_m_pow = m_pow_1-  population(i,j).subsystem_masses.mass_power;

      population(i,j).subsystem_masses.m_margin = population(i,j).subsystem_masses.m_margin-d_m_pow;
      if population(i,j).subsystem_masses.m_margin <0
          %disp('Alert system margin fully consumed by propulsion system')
          %population(i,j).mass = population(i,j).mass-population(i,j).subsystem_masses.m_margin;     %TODO: THINK HERE
          population(i,j).subsystem_masses.m_margin =0;    %TODO: THINK HERE
      end

      %total mass
      mass_fields =  fieldnames(population(i,j).subsystem_masses);
      m_new=0;
      for k=4:numel(mass_fields)-1    %start with 4 as three previous fields are irrelvant -1 is another struct - beware!
        m_new = m_new+population(i,j).subsystem_masses.(mass_fields{k,1});
      end
      population(i,j).subsystem_masses.m_dry_margin = m_new;

      population(i,j).subsystem_masses.m_dry_nomargin = population(i,j).mass-population(i,j).subsystem_masses.mass_propellant;
      population(i,j).subsystem_masses.m_margin = population(i,j).subsystem_masses.m_dry_nomargin-population(i,j).subsystem_masses.m_dry_margin;
      %population(i,j).mass_fractions= mass_fractions(population(i,j));

      % Fitness criterion: selectable via Simulation_parameters.evolver.fitness_criterion
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

      %test for improvement of pop member
      lineage = get_lineage(generation_data, i, j);
      if strcmp(fitness_criterion, 'maximize_payload_mass')
        population(i,j).evolution_success = test_maximize_parameter(population(i,j), lineage, {'subsystem_masses','mass_payload'});
      elseif strcmp(fitness_criterion, 'minimize_total_mass')
        population(i,j).evolution_success = test_minimize_parameter(population(i,j), lineage, {'mass'});
      else  % default: 'maximize_mass_margin'
        population(i,j).evolution_success = test_maximize_parameter(population(i,j), lineage, {'subsystem_masses','m_margin'});
      end

      % Reject individuals with NaN c_e or thrust — invalid propulsion solution.
      % Exception: sc_type==1 ('No Propulsion') where these fields are not applicable.
      sc_type_i = input.Satellite_parameters.input_case{i}.derived.sc_type;
      mutation_valid = true;
      if sc_type_i ~= 1 && (isnan(population(i,j).c_e) || isnan(population(i,j).thrust))
        population(i,j).evolution_success = 0;
        mutation_valid = false;
      end

      % Ignore no-op mutations for convergence counting; they should not consume the fail budget.
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
      population(i,j).count_for_convergence = mutation_valid && mutation_changed;
      population(i,j).convergence_mode = 'active';

      %refresh the number of the last sucessful lineage member here
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
