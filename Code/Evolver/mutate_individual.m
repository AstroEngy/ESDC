% mutate_individual — Apply one random mutation to a spacecraft design individual
%
% PURPOSE:
%   Randomly selects one Degree of Freedom (DOF) from the set available for
%   the individual's current propulsion system and applies the corresponding
%   mutation operator (c_e, thrust, propellant, or propulsion_system change).
%   Returns a new individual that is identical to the parent except in the
%   mutated DOF.
%
% INTENT:
%   Keeps the mutation logic configurable via the DOF database: adding a new
%   mutable parameter only requires updating model_DOF, not this function.
%   The thrust_mode filter narrows the DOF space when the user requires
%   high-thrust or low-thrust propulsion, preventing incompatible mutations.
%
% Parameters:
%   input          (struct): Mission parameters (used to pass context to
%                  sub-mutation functions where needed).
%   db_data        (struct): Hardware DB and DOF definitions.
%   config         (struct): Simulation settings (evolver sub-struct).
%   individual_old (struct): Current population member to be mutated.
%
% Returns:
%   individual_new (struct): Mutated copy of individual_old.  If the
%                  individual is already converged, it is returned unchanged.
%
% HOW TO TEST:
%   1. Pass an individual with convergence=1; verify the output is byte-for-
%      byte identical to the input (early return, no mutation applied).
%   2. Set n_DOF=1 (only one propulsion type, one DOF); run 100 times and
%      verify only that specific DOF changes each time.
%   3. Set thrust_mode='high'; verify that low-thrust technologies
%      (FEEP, gridded-ion) never appear in the output's propulsion_system.
%   4. Trigger the 'mutation law not found' warning by injecting an unknown
%      DOF name into db_data.DOF; confirm the warning fires and the output
%      individual equals the input.
%
% SAFEGUARDS ALREADY IN PLACE:
%   - Early return for converged individuals.
%   - thrust_mode filter restricts available mutations to compatible technologies.
%   - Unknown DOF triggers a warning rather than a silent no-op or crash.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that at least one DOF remains after filtering; if n_DOF==0
%     return the parent unchanged (instead of a randi(0) crash).
%   - Log the chosen mutation type per call for diagnosability.
function [individual_new] = mutate_individual(input, db_data, config, individual_old)

  individual_new= individual_old;

  % Converged individuals are frozen — no further mutation attempted.
  if individual_new.convergence ==1
    return
  end

  % ---- Determine the available DOFs for the current propulsion type -------
  % n_DOF counts the mutable parameters; cases holds their names.
  n_DOF = num_struct_members_full(db_data.DOF.propulsion_system.(individual_old.propulsion_system), 'DOF');
  cases = db_data.DOF.propulsion_system.(individual_old.propulsion_system).DOF;

  % If more than one propulsion system exists, add a DOF to mutate the
  % propulsion system type itself (cross-technology mutation).
  if numel(fieldnames(db_data.DOF.propulsion_system))>1
    n_DOF = n_DOF+1;
    cases{1,end+1}='propulsion_system';
  end

  % Apply thrust_mode filter: restricts available technologies and DOFs
  % when the user specified 'high' or 'low' thrust preference.
  thrust_mode = '';
  if isfield(individual_old, 'thrust_mode') && ~isempty(individual_old.thrust_mode)
    thrust_mode = individual_old.thrust_mode;
  end
  if ~isempty(thrust_mode)
    dof_filtered = filter_dof_by_thrust_mode(db_data.DOF, thrust_mode);
    if isfield(dof_filtered.propulsion_system, individual_old.propulsion_system)
      cases = dof_filtered.propulsion_system.(individual_old.propulsion_system).DOF;
    end
    % Only allow propulsion_system mutation if >1 compatible system remains
    if numel(fieldnames(dof_filtered.propulsion_system)) > 1
      cases{1,end+1} = 'propulsion_system';
    end
  end
  n_DOF = numel(cases);

  % ---- Randomly select which DOF to mutate --------------------------------
  n_mutation_case = randi(n_DOF);

  evolver_config = config.Simulation_parameters.evolver;

  % ---- Dispatch to the appropriate mutation operator ----------------------
  switch cases{1,n_mutation_case}
    case {'c_e', 'c_e_high', 'c_e_low'}
      % Mutate exhaust velocity (specific impulse); propellant and thrust unchanged.
      [individual_new] = mutate_c_e(individual_old, db_data, evolver_config);

    case {'thrust', 'thrust_high', 'thrust_low'}
      % Mutate thrust level; c_e and propellant may adjust accordingly.
      [individual_new] = mutate_thrust(individual_old, db_data, evolver_config);

    case 'propellant'
      % Change propellant within the same propulsion technology family.
      [individual_new] = mutate_propellant(individual_old, db_data);

    case  'propulsion_system'
      % Cross-technology mutation: switch to a different propulsion system class.
      [individual_new] = mutate_propulsion_system(individual_old, db_data);

    otherwise
      warning('mutate_individual: mutation law not found for DOF: %s', cases{1,n_mutation_case});
  end

end