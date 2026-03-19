function [convergence, convergence_mode] = test_lineage_convergence_simple(new_data, lineage_data, config)
  n_no_success = max(1, config.Simulation_parameters.evolver.n_fails_to_converge);
  n_bad_seed_to_converge = 3 * n_no_success;
  if isfield(config.Simulation_parameters.evolver, 'n_bad_seed_to_converge')
    n_bad_seed_to_converge = max(1, config.Simulation_parameters.evolver.n_bad_seed_to_converge);
  end

  convergence = 0;
  convergence_mode = 'active';

  % Stall convergence: if no successful mutation happened for a long time,
  % treat the lineage as a bad initial seed and stop stalling it.
  last_success_idx = 0;
  for idx = numel(lineage_data):-1:1
    if lineage_data{idx}.evolution_success
      last_success_idx = idx;
      break;
    end
  end

  if last_success_idx > 0
    n_since_success = numel(lineage_data) - last_success_idx + 1; % include new_data
    if n_since_success >= n_bad_seed_to_converge
      convergence = 1;
      convergence_mode = 'stall';
      return;
    end
  end

  % Current candidate must be a counted failed mutation to contribute.
  if new_data.evolution_success
    return;
  end
  if isfield(new_data, 'count_for_convergence') && ~new_data.count_for_convergence
    return;
  end

  % Count consecutive counted failures backwards through lineage history.
  n_counted_fail = 1; % include new_data
  for idx = numel(lineage_data):-1:1
    entry = lineage_data{idx};

    if isfield(entry, 'count_for_convergence') && ~entry.count_for_convergence
      continue;
    end

    if entry.evolution_success
      return;
    end

    n_counted_fail = n_counted_fail + 1;
    if n_counted_fail >= n_no_success
      convergence = 1;
      convergence_mode = 'local_optimum';
      return;
    end
  end
end