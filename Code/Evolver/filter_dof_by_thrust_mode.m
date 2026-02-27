function dof = filter_dof_by_thrust_mode(dof, thrust_mode)
  % Filter the DOF struct based on the user-specified thrust operating mode.
  %
  % Physical basis:
  %   High thrust <-> low c_e (low Isp), low efficiency   (P_jet = 0.5*F*c_e, fixed power)
  %   Low  thrust <-> high c_e (high Isp), high efficiency
  %
  % Technology classification:
  %   'high' only : chemical, resistojet
  %   'low'  only : gridionthruster, FEEP, electrospray, RF_plasma
  %   'both'      : arcjet, HET  (have explicit _high/_low DOF variants)
  %
  % DOF pairing for 'both' technologies:
  %   thrust_mode='high' -> keep thrust_high + c_e_low  (high F, low Isp)
  %   thrust_mode='low'  -> keep thrust_low  + c_e_high (low F, high Isp)
  %   'propellant' and 'propulsion_system' are always kept.

  if nargin < 2 || isempty(thrust_mode) || strcmp(thrust_mode, 'any')
    return;  % no filtering
  end

  if ~strcmp(thrust_mode, 'high') && ~strcmp(thrust_mode, 'low')
    warning('filter_dof_by_thrust_mode: unknown thrust_mode "%s", no filtering applied', thrust_mode);
    return;
  end

  % --- Technology regime classification ---
  high_only = {'chemical', 'resistojet'};
  low_only  = {'gridionthruster', 'FEEP', 'electrospray', 'RF_plasma'};
  % 'both' technologies (arcjet, HET, etc.) are everything else — their DOF
  % lists are filtered by string, not by wholesale removal.

  % --- DOF strings to remove per mode for 'both' technologies ---
  % High thrust = high F + low c_e: drop low-thrust DOFs and high-c_e DOFs
  % Low  thrust = low  F + high c_e: drop high-thrust DOFs and low-c_e DOFs
  if strcmp(thrust_mode, 'high')
    excluded_tech = low_only;   % remove entire low-thrust-only technologies
    excluded_dof  = {'thrust_low', 'c_e_high'};
  else
    excluded_tech = high_only;  % remove entire high-thrust-only technologies
    excluded_dof  = {'thrust_high', 'c_e_low'};
  end

  systems = fieldnames(dof.propulsion_system);
  for i = 1:numel(systems)
    sys = systems{i};

    % Remove technologies that belong exclusively to the excluded regime
    if any(strcmp(sys, excluded_tech))
      dof.propulsion_system = rmfield(dof.propulsion_system, sys);
      continue;
    end

    % For remaining technologies: filter their DOF string list
    cases = dof.propulsion_system.(sys).DOF;
    keep = true(1, numel(cases));
    for k = 1:numel(cases)
      if any(strcmp(cases{k}, excluded_dof))
        keep(k) = false;
      end
    endfor
    filtered = cases(keep);

    % Safety: if filter removed everything (technology had only excluded DOFs),
    % keep the original list rather than leaving an empty DOF set.
    if isempty(filtered)
      filtered = cases;
    end
    dof.propulsion_system.(sys).DOF = filtered;
  endfor
endfunction
