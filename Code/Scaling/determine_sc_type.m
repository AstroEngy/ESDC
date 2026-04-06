% Spacecraft Type Determination
%
% Determines the spacecraft type using a three-priority inference chain:
%   Priority 1 — explicit sc_type field in data        (highest)
%   Priority 2 — orbit_height [km] field in data       (classifies to sc_type 2 or 3 only;
%                                                        sc_type 4 requires explicit or dv)
%   Priority 3 — dv / deltav [m/s] field in data       (lowest)
%   Default    — sc_type 1 (no propulsion)
%
% Spacecraft Types:
%   1 - No propulsion
%   2 - Low Earth Orbit (LEO)
%   3 - High Earth / GEO / HEO
%   4 - Planetary probe mission
%
% Inputs:
%   data       - Structure with any of: sc_type, orbit_height, dv, deltav
%   thresholds - (optional) Struct from Simulation_parameters.defaults.sc_type_thresholds
%                  orbit_height_leo_max [km]  — LEO/GEO-HEO altitude boundary
%                  dv_geo_min           [m/s] — LEO/GEO-HEO delta-v boundary
%                  dv_escape_min        [m/s] — GEO-HEO/Planetary delta-v boundary
%                Omit to use hardcoded fallbacks matching the simulation parameter defaults.
%
% Outputs:
%   sc_type - Integer representing spacecraft type (1-4)

function [sc_type] = determine_sc_type(data, thresholds)

    % ===== Load Classification Thresholds =====
    % Fallbacks match ESDC_Simulation_parameters.defaults.sc_type_thresholds.
    if nargin < 2 || ~isstruct(thresholds)
        thresholds = struct();
    end
    orbit_height_leo_max = sc_threshold(thresholds, 'orbit_height_leo_max', 2000);  % km
    DV_GEO_THRESHOLD     = sc_threshold(thresholds, 'dv_geo_min',           2000);  % m/s
    DV_ESCAPE_THRESHOLD  = sc_threshold(thresholds, 'dv_escape_min',        4300);  % m/s

    % ===== Priority 1: Explicit sc_type =====
    if isfield(data, 'sc_type')
        if isnumeric(data.sc_type)
            sc_type = data.sc_type;
        elseif ischar(data.sc_type) || isstring(data.sc_type)
            sc_type = parse_sc_type_string(data.sc_type);
        else
            error('Invalid sc_type format. Must be numeric or string.');
        end
        return;
    end

    % ===== Priority 2: Orbit Height =====
    % Only classifies as sc_type 2 (LEO) or 3 (GEO/HEO).
    % sc_type 4 (Planetary) cannot be inferred from Earth-relative altitude alone
    % and requires an explicit sc_type or a delta-v exceeding the escape threshold.
    if isfield(data, 'orbit_height') && ~isempty(data.orbit_height) && data.orbit_height > 0
        if data.orbit_height <= orbit_height_leo_max
            sc_type = 2;
        else
            sc_type = 3;
        end
        % Cross-check: warn when delta-v implies a different classification.
        dv_check = 0;
        if isfield(data, 'dv');     dv_check = data.dv;     end
        if isfield(data, 'deltav'); dv_check = data.deltav; end
        if dv_check > 0
            if     dv_check > DV_ESCAPE_THRESHOLD; sc_type_dv = 4;
            elseif dv_check > DV_GEO_THRESHOLD;   sc_type_dv = 3;
            else;                                  sc_type_dv = 2;
            end
            if sc_type_dv ~= sc_type
                fprintf(['Warning [determine_sc_type]: orbit_height (%.0f km) implies sc_type %d ' ...
                         'but delta-v (%.0f m/s) implies sc_type %d. ' ...
                         'Orbit height takes priority.\n'], ...
                         data.orbit_height, sc_type, dv_check, sc_type_dv);
            end
        end
        return;
    end

    % ===== Priority 3: Delta-v =====
    if isfield(data, 'dv')
        dv_value = data.dv;
    elseif isfield(data, 'deltav')
        dv_value = data.deltav;
    else
        dv_value = 0;
    end
    if dv_value > 0
        if dv_value <= DV_GEO_THRESHOLD
            sc_type = 2;
        elseif dv_value <= DV_ESCAPE_THRESHOLD
            sc_type = 3;
        else
            sc_type = 4;
        end
    else
        sc_type = 1;  % no propulsion or zero delta-v
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

% =========================================================================
% CLASSIFICATION THRESHOLD HELPER
% =========================================================================
% Reads a numeric threshold from the thresholds struct.
% Handles XML-parsed string values; falls back to default_val when absent or invalid.

function val = sc_threshold(thresholds, field, default_val)
    if isfield(thresholds, field)
        v = thresholds.(field);
        if ischar(v) || isstring(v); v = str2double(v); end
        if ~isnan(v) && v > 0
            val = v;
            return;
        end
    end
    val = default_val;
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

