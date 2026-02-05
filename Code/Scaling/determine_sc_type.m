% Spacecraft Type Determination
%
% Determines the spacecraft type based on delta-v requirements using
% mission profile thresholds. If spacecraft type is already defined in
% input data, uses that value instead.
%
% Spacecraft Types:
%   1 - No propulsion
%   2 - Low Earth Orbit (LEO) mission
%   3 - High Earth Orbit (GEO) mission
%   4 - Planetary probe mission
%
% Inputs:
%   data - Structure containing mission parameters
%          Can have 'sc_type' (numeric or string) or 'dv' field
%
% Outputs:
%   sc_type - Integer representing spacecraft type (1-4)

function [sc_type] = determine_sc_type(data)
    
    % ===== Check for Predefined Spacecraft Type =====
    
    if isfield(data, 'sc_type')
        % Spacecraft type already defined
        
        if isnumeric(data.sc_type)
            sc_type = data.sc_type;
            
        elseif ischar(data.sc_type) || isstring(data.sc_type)
            % Convert string to numeric type
            sc_type = parse_sc_type_string(data.sc_type);
            
        else
            error('Invalid sc_type format. Must be numeric or string.');
        end
        
        return;
    end
    
    % ===== Determine Type from Delta-v =====
    
    % Delta-v thresholds [m/s]
    DV_GEO_THRESHOLD = 2000;      % Minimum dv for GEO transfer
    DV_ESCAPE_THRESHOLD = 4300;   % Approximate dv for Earth escape
    
    % Check for delta-v field (support both 'dv' and 'deltav')
    if isfield(data, 'dv')
      dv_value = data.dv;
    elseif isfield(data, 'deltav')
      dv_value = data.deltav;
    else
      dv_value = 0;
    end
    
    if dv_value > 0 
      % Propelled spacecraft - determine type by delta-v
      
      if dv_value <= DV_GEO_THRESHOLD
        sc_type = 2;  % LEO mission (default for propelled spacecraft)
        
      elseif dv_value <= DV_ESCAPE_THRESHOLD
        sc_type = 3;  % High Earth Orbit (e.g., GEO transfer)
        
      else
        sc_type = 4;  % Planetary probe (escape velocity exceeded)
      end
      
    else
      % No propulsion or zero delta-v
      sc_type = 1;
    end
    
end


% =========================================================================
% PARSE SPACECRAFT TYPE STRING
% =========================================================================
% Converts string representation of spacecraft type to numeric value

function [sc_type_num] = parse_sc_type_string(sc_type_str)
    
    % Convert to lowercase for case-insensitive comparison
    sc_type_lower = lower(char(sc_type_str));
    
    switch sc_type_lower
        case {'1', 'no propulsion', 'no_propulsion', 'nopropulsion'}
            sc_type_num = 1;
            
        case {'2', 'leo', 'low earth', 'low_earth', 'lowearth'}
            sc_type_num = 2;
            
        case {'3', 'geo', 'high earth', 'high_earth', 'highearth', 'geostationary'}
            sc_type_num = 3;
            
        case {'4', 'planetary', 'probe', 'planetary probe', 'planetary_probe'}
            sc_type_num = 4;
            
        otherwise
            error('Unknown spacecraft type string: %s', sc_type_str);
    end
    
end

% function [sc_type] = determine_sc_type(data)
%     if isfield(data,'dv') && (data.dv >0) % only type 1,2,3 when propelled
%       sc_type = 2; % LEO type mission is default
%       if (data.dv >2000) && (data.dv <=4300)
%         sc_type = 3; % High Earth type mission like GEO
%       elseif (data.dv >4300) % dv to escape earth from orbital velocity, makes planetary probe type mission (3)
%         sc_type = 4;
%       endif
%     else 
%       sc_type = 1; % no propulsion case
%     endif
% endf

