% set_random_case_parameters — Sample random initial propulsion parameters for a population seed
%
% PURPOSE:
%   Randomly selects a propulsion system type and a set of compatible
%   propulsion parameters (propellant, c_e, thrust, power) from the hardware
%   reference database.  Called once per seed when make_population()
%   initialises the first generation.
%
% INTENT:
%   Provides diversity in the initial population by randomly sampling from
%   the full design space defined by the DOF database.  The thrust_mode
%   filter can narrow this space to high- or low-thrust technologies when
%   the user has a preference.
%
%   The function uses a two-level random selection:
%     1. Pick a random DOF index across ALL technologies × ALL DOFs.
%     2. Identify which technology that index belongs to.
%     3. Dispatch to the appropriate data-fetching function.
%
% Parameters:
%   db_data        (struct): Hardware DB and DOF definitions.
%   power_propulsion (float): Available propulsion power [W] (used as
%                  context when computing derived performance parameters).
%   thrust_mode    (string, optional, default ''): 'high', 'low', or '' (any).
%                  Filters available technologies before random selection.
%
% Returns:
%   propulsion     (string): Selected propulsion system type name.
%   propellant     (string): Selected propellant.
%   c_e            (float):  Exhaust velocity [m/s].
%   F              (float):  Thrust [N].
%   p_thr          (float):  Thruster power [W].
%   p_jet          (float):  Jet power [W].
%   eff_ppu        (float):  PPU efficiency [-].
%   eff_thruster   (float):  Thruster efficiency [-].
%
% HOW TO TEST:
%   1. Call 100 times and verify that propulsion and propellant are always
%      valid strings found in db_data.reference_data.propulsion_system.
%   2. Set thrust_mode='high'; verify only high-thrust technologies are
%      returned (e.g. cold gas, chemical — never FEEP or gridded-ion).
%   3. Verify c_e, F, p_thr are all positive and finite (non-NaN, non-Inf).
%   4. Remove all technologies except one from DOF; verify the same
%      technology is always selected (no out-of-range randi crash).
%
% SAFEGUARDS ALREADY IN PLACE:
%   - try/catch on all DB lookups with recursive retry on failure.
%   - thrust_mode filter applied before DOF counting.
%
% SAFEGUARDS TO ADD (future work):
%   - Limit recursion depth in the catch-and-retry pattern to avoid infinite
%     loops when the database has no valid entry for a technology.
%   - Validate that all returned values are finite before returning.
function [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode)
  % thrust_mode (optional): 'high', 'low', or '' (any).
  % Filters available DOFs and technologies before random selection.
  if nargin < 3
    thrust_mode = '';
  end

  % Apply thrust_mode filter to DOF struct before counting
  dof = filter_dof_by_thrust_mode(db_data.DOF, thrust_mode);

  n_DOF = num_struct_members_full(dof, 'DOF');
  n_random_case = randi(n_DOF);

  % ---- Map flat DOF index to (technology, DOF name) -----------------------
  % Each technology contributes n_sub DOF entries to the flat index space.
  % Walk through technologies accumulating index ranges until we find the
  % one that contains n_random_case.
  propulsion_systems = dof.propulsion_system;
  index_low = 0;
  names = fieldnames(propulsion_systems);

  for i=1:numel(names)
      n_sub = num_struct_members_full(propulsion_systems.(names{i}),'DOF');
      index_up=index_low+n_sub;
      % associate the correct DOF random case to the correct propulsion system one level above in XML file.
      if( index_low<= n_random_case &&  n_random_case <= index_up)
        propulsion = names{i};
        case_instance = propulsion_systems.(propulsion).DOF(n_random_case-index_low);
        break
      end
      index_low = index_up;
  end

  % ---- Dispatch to parameter-fetching logic based on sampled DOF ----------
  % Each case resolves the full set of propulsion parameters from the DB.
  % On failure, the function retries by calling itself recursively.
  switch case_instance{1,1}
    case 'propellant'
      % Primary DOF is propellant choice; c_e follows from propellant
      propellant = get_random_propellant(db_data.reference_data.propulsion_system, propulsion);
      c_e = get_random_propulsion_DOF_float(db_data.reference_data.propulsion_system, propulsion, propellant, 'c_e');
      %no random because function of given parameters
      [F p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_thrust(db_data.reference_data.propulsion_system, propulsion, propellant, c_e, power_propulsion);

    case 'thrust'
      % Primary DOF is thrust level; c_e is derived from the selected thrust/propellant pair
      try
        [F propellant]= get_random_thrust_and_propellant(db_data.reference_data.propulsion_system, propulsion);
      catch e
        warning(e.message);
        [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode);
        return;
      end
      % calculate c_e and propulsion system performance data 
      [c_e p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_c_e(db_data.reference_data.propulsion_system, propulsion, propellant, F, power_propulsion); 
      % TODO: likely inconsistent results?
    case 'thrust_high'
      try
        [F propellant]= get_random_thrust_and_propellant(db_data.reference_data.propulsion_system, propulsion, 'high');
      catch e
        warning(e.message);
        [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode);
        return;
      end
      [c_e p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_c_e(db_data.reference_data.propulsion_system, propulsion, propellant, F, power_propulsion);
    case 'thrust_low'
      try
        [F propellant]= get_random_thrust_and_propellant(db_data.reference_data.propulsion_system, propulsion, 'low');
      catch e
        warning(e.message);
        [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode);
        return;
      end
      [c_e p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_c_e(db_data.reference_data.propulsion_system, propulsion, propellant, F, power_propulsion);
    case 'c_e'
      % Primary DOF is exhaust velocity; thrust is derived from power and c_e
      try
        [c_e propellant]=get_random_c_e_and_propellant(db_data.reference_data.propulsion_system, propulsion);
      catch e
        warning(e.message);
        [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode);
        return;
      end
      [F p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_thrust(db_data.reference_data.propulsion_system, propulsion, propellant, c_e, power_propulsion);
    case 'c_e_high'
      try
        [c_e propellant]=get_random_c_e_and_propellant(db_data.reference_data.propulsion_system, propulsion, 'high');
      catch e
        warning(e.message);
        [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode);
        return;
      end
      [F p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_thrust(db_data.reference_data.propulsion_system, propulsion, propellant, c_e, power_propulsion);
    case 'c_e_low'
      try
        [c_e propellant]=get_random_c_e_and_propellant(db_data.reference_data.propulsion_system, propulsion, 'low');
      catch e
        warning(e.message);
        [propulsion propellant c_e F p_thr p_jet eff_ppu eff_thruster] = set_random_case_parameters(db_data, power_propulsion, thrust_mode);
        return;
      end
      [F p_thr p_jet eff_ppu eff_thruster] = get_propulsion_system_performance_data_wo_thrust(db_data.reference_data.propulsion_system, propulsion, propellant, c_e, power_propulsion);
      % function to look up relevant c_e s from DB, select 1 randomly from available span 
    otherwise
      disp('DOF case laws not found. Check spelling') 
  end
end
