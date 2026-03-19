% Main evolutionary algorithm function
% Initializes generations and iterates them until convergence is reached
%
% Parameters:
%   input: Structure containing input parameters for the evolutionary algorithm
%   db_data: Database data required for population initialization and evolution
%   config: Configuration parameters for the evolutionary algorithm
%   runID: Identifier for the current run of the program
%
% Returns:
%   evolution_data: Cell array containing data for all generations

function evolution_data = evolver(input, db_data, config,runID)
  disp('Starting Evolution ...');
  disp(' ');
  fflush(stdout);
  %outermost shell of the evolutionary algorithm. Initializes first generation according to data and iterates generations until convergence is met.
  generation        = {};                                                       % Initialize cell array for generations, TO THINK: is this incosistent?

  %First gen
  n_gen             = 1;                                                        % Initialize generation number
  generation{n_gen} = make_population(input, db_data, config);                  % Create the first generation

  max_generations = 500;
  if isfield(config.Simulation_parameters.evolver, 'max_generations')
    max_generations = config.Simulation_parameters.evolver.max_generations;
  end
  reached_max_generations = false;

  convergence       = 0;                                                        % Initialize all generations as not converged
  while ~convergence                                                          % Iterate until convergence is reached
    n_gen=n_gen+1;                                                              % Increment generation number

    [generation{n_gen}, convergence]= evolve_population(input, db_data, config, generation,runID);  % Add new generational data, potentially update convergence

    if ~mod(n_gen,config.Simulation_parameters.output.CLI.n_verbosity)        % CLI Output according to frequency, might be used for completition time prediction
      fprintf('Iterated generations: %d\n', n_gen);
      fflush(stdout);
    end

    if n_gen >= max_generations
      warning('evolver:max_generations_reached', 'Maximum generations (%d) reached before convergence.', max_generations);
      reached_max_generations = true;
      break;
    end
  end

  % CLI output
  if reached_max_generations && ~convergence
    fprintf('\nWarning: Evolver stopped at maximum generation limit (%d) before full convergence\n', n_gen);
  else
    fprintf('\nSuccess: Evolver has converged at %d generations\n', n_gen);
  end
  fflush(stdout);

  % Collapse to best-per-lineage snapshot.
  % During evolution the full generation cell was needed for get_lineage / convergence
  % testing. Now that the loop is done we discard failed mutants to save memory.
  % Each individual's n_success field points to the generation index that holds its
  % global optimum; copy those individuals into a single snapshot matrix.
  n_cases_ev = size(generation{1}, 1);
  n_seeds_ev  = size(generation{1}, 2);
  best_gen = generation{end};                                                   % pre-allocate with correct struct layout
  for ev_i = 1:n_cases_ev
    for ev_j = 1:n_seeds_ev
      best_gen(ev_i, ev_j) = generation{generation{end}(ev_i,ev_j).n_success}(ev_i, ev_j);
    end
  end

  if config.Simulation_parameters.output.xml.full_history
    generation{end+1} = best_gen;                                               % full history mode: keep all generations, append best as final entry
    evolution_data = generation;
  else
    evolution_data = {best_gen};                                                % default: only the best snapshot (one cell entry)
  end
end
