% evolver — Top-level evolutionary optimisation loop
%
% PURPOSE:
%   Iterates the spacecraft population through successive generations until
%   all lineages converge (or max_generations is reached).  Returns the
%   best individual from each lineage — or, in full-history mode, all
%   generations plus the best snapshot appended as the final entry.
%
% INTENT:
%   Implements a steady-state evolution strategy: each lineage evolves
%   independently.  A lineage tracks the best solution found so far
%   (n_success pointer); mutations that are worse are discarded but the
%   lineage continues from the previous best.  Convergence is declared per
%   lineage when no improvement is observed over a configurable window.
%
%   The outer loop here only handles lifecycle management (init, iterate,
%   stop, collapse).  All physical evaluation (SMAD scalings, power
%   analysis, mass budget) is performed inside evolve_population().
%
% Parameters:
%   input       (struct): Mission parameters (input_case structs with .derived
%               and .orbit).  Provides mass, delta-v, power, sc_type.
%   db_data     (struct): Hardware reference data and DOF definitions.
%   config      (struct): Simulation parameters.  Relevant fields:
%       .Simulation_parameters.evolver.seed_points   — number of lineages
%       .Simulation_parameters.evolver.max_generations
%       .Simulation_parameters.evolver.random_seed   (0 = non-deterministic)
%       .Simulation_parameters.output.xml.full_history
%       .Simulation_parameters.output.CLI.n_verbosity
%   runID       (integer): Passed through to evolve_population for logging.
%
% Returns:
%   evolution_data (cell array): In default mode, {best_gen} — a 1x1 cell
%       containing an [n_cases × n_seeds] struct array of best individuals.
%       In full_history mode, all generations plus the best snapshot at end.
%
% HOW TO TEST:
%   1. Set random_seed to a fixed value and run twice; verify identical
%      evolution_data output (determinism test).
%   2. Set max_generations=1 and verify the function terminates with a
%      "maximum generations reached" warning after a single iteration.
%   3. Use an infeasible input (thrust_min impossible for all technologies);
%      verify the 'evolver:all_lineages_stalled' error is thrown.
%   4. Run with full_history=true and verify size(evolution_data) == n_gen+1
%      with the final entry matching the best_gen snapshot.
%   5. After a normal run, verify all individuals in evolution_data{end}
%      have a valid (non-NaN) c_e and thrust for sc_type != 1.
%
% SAFEGUARDS ALREADY IN PLACE:
%   - max_generations hard stop prevents infinite loops.
%   - all_lineages_stalled check detects infeasible problem formulations.
%   - NaN c_e/thrust hard-reject in evolve_population.
%
% SAFEGUARDS TO ADD (future work):
%   - Log per-lineage convergence generation counts for diagnostics.
%   - Optionally checkpoint evolution_data to disk every N generations so
%     a long run is recoverable after a crash.

function evolution_data = evolver(input, db_data, config,runID)
  disp('Starting Evolution ...');
  disp(' ');
  fflush(stdout);
  % Outermost shell of the evolutionary algorithm.
  % Initialises the first generation and iterates until convergence.
  generation        = {};                                                       % Initialize cell array for generations, TO THINK: is this incosistent?

  % ---- First generation: random initialisation ----------------------------
  n_gen             = 1;
  generation{n_gen} = make_population(input, db_data, config);                  % Create the first generation with random propulsion parameters

  max_generations = 500;
  if isfield(config.Simulation_parameters.evolver, 'max_generations')
    max_generations = config.Simulation_parameters.evolver.max_generations;
  end
  reached_max_generations = false;

  convergence       = 0;                                                        % Initialize all generations as not converged
  while ~convergence                                                          % Iterate until convergence is reached
    n_gen=n_gen+1;                                                              % Increment generation number

    % Produce next generation by mutating survivors; update convergence flag.
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

  % ---- Convergence / termination status report ----------------------------
  if reached_max_generations && ~convergence
    fprintf('\nWarning: Evolver stopped at maximum generation limit (%d) before full convergence\n', n_gen);
  else
    fprintf('\nSuccess: Evolver has converged at %d generations\n', n_gen);
  end
  fflush(stdout);

  % ---- Stall detection: all lineages failed without a valid solution ------
  % Indicates the problem is infeasible (e.g. thrust_min unachievable,
  % no matching propellant in DB, or payload constraints too tight).
  n_cases_chk = size(generation{end}, 1);
  n_seeds_chk = size(generation{end}, 2);
  all_stalled = true;
  for chk_i = 1:n_cases_chk
    for chk_j = 1:n_seeds_chk
      ind = generation{end}(chk_i, chk_j);
      if ~(isfield(ind, 'convergence_mode') && strcmp(ind.convergence_mode, 'stall') ...
           && isfield(ind, 'n_success') && ind.n_success == 1)
        all_stalled = false;
        break;
      end
    end
    if ~all_stalled; break; end
  end
  if all_stalled
    error('evolver:all_lineages_stalled', ...
      ['All %d lineages stalled without finding a valid solution.\n' ...
       'Possible causes: payload/power constraints unsatisfiable, thrust_min too high,\n' ...
       'or no propulsion technology in the database matches the input requirements.'], ...
      n_cases_chk * n_seeds_chk);
  end

  % ---- Collapse to best-per-lineage snapshot ------------------------------
  % During evolution the full generation cell was needed for get_lineage /
  % convergence testing.  Now that the loop is done we extract the globally
  % best individual for each lineage (identified by n_success, which points
  % to the generation index where the best solution was found).
  n_cases_ev = size(generation{1}, 1);
  n_seeds_ev  = size(generation{1}, 2);
  best_gen = generation{end};                                                   % pre-allocate with correct struct layout
  for ev_i = 1:n_cases_ev
    for ev_j = 1:n_seeds_ev
      best_gen(ev_i, ev_j) = generation{generation{end}(ev_i,ev_j).n_success}(ev_i, ev_j);
    end
  end

  % ---- Attach scaling quality metrics to each best candidate --------------
  % Computed post-evolution so the inner loop carries no overhead.
  % scaling_quality quantifies how well the SMAD correlations apply to
  % this particular design point (extrapolation distance, data sparsity).
  for ev_i = 1:n_cases_ev
    for ev_j = 1:n_seeds_ev
      try
        [~, ~, best_gen(ev_i, ev_j).scaling_quality] = SMAD_scalings(best_gen(ev_i, ev_j));
      catch
        % Malformed individual (e.g. no-propulsion edge case): skip silently.
      end
    end
  end

  if config.Simulation_parameters.output.xml.full_history
    generation{end+1} = best_gen;                                               % full history mode: keep all generations, append best as final entry
    evolution_data = generation;
  else
    evolution_data = {best_gen};                                                % default: only the best snapshot (one cell entry)
  end
end
