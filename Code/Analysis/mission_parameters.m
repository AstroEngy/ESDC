%this function derives time for conumsing the given propellant mass by a propulsion system  

function [mission_parameters] =  mission_parameters(data)            % use data, return refined mission parameters
  mission_parameters = struct;                                       % prepare a data structure
  mission_parameters.maneuver_duration = maneuver_duration(data);    % add calculated maneuvre time to structure
end  

function [time] = maneuver_duration(data)                            % Calculate maneuvre duration time
  %disp(data)
    t  = data.thrust;
    ce = data.c_e;
    % Guard against empty or non-positive thrust/c_e (e.g. no propulsion power supplied).
    if isempty(t) || isempty(ce) || ~isscalar(t) || ~isscalar(ce) || ce <= 0 || t <= 0
        time = Inf;
        return;
    end
    massflow = t / ce;                                               % mass flow is thrust divided by effective exhaust velocity
    m_prop = data.subsystem_masses.mass_propellant;
    if m_prop <= 0 || massflow <= 0
        time = 0;
        return;
    end
    time = m_prop / massflow;                                        % time is propellant mass divided by mass flow
end