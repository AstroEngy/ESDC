function m_tank = m_scale_tank(m_prop, propellant, db_data)
% m_scale_tank — Estimate propellant tank dry mass [kg] from propellant mass and type.
%
% Derives a scaling law on-the-fly from tank entries in the reference database
% (db_data.reference_data.propulsion_system.tank.vessel) that are compatible
% with the specified propellant.  The propellant storage volume is computed from
% m_prop and the storage density returned by prop_density().
%
% Propellant-compatibility filtering rules (applied in order):
%   1. Tank entries whose propellant field is absent or empty are GENERIC vessels
%      and are only used when no propellant-specific entries exist.
%   2. Tank entries with a propellant string are compatible when the string
%      matches any alias of the requested propellant (case-insensitive).
%   3. Tank entries with a propellant list (cell array) are compatible when any
%      element of the list matches an alias of the requested propellant.
%   4. Selection priority:
%        a. If ≥2 propellant-specific entries found → use those only.
%        b. Else if ≥2 generic (null-propellant) entries found → use those.
%        c. Else fall back to all entries combined (with a warning).
%
% Tank `volume` values in the database are in m³.
% rho_p is obtained from prop_density(); see that function for supported
% propellant names, aliases, and source references.
%
% Inputs:
%   m_prop     — propellant mass [kg], scalar or array
%   propellant — propellant name string (see prop_density for full list)
%   db_data    — (optional) pre-loaded reference database struct; read from
%                disk if omitted or empty
%
% Output:
%   m_tank — estimated dry tank mass [kg], same size as m_prop

  if nargin < 3 || isempty(db_data) || ~isstruct(db_data) || ~isfield(db_data, 'reference_data')
    db_data = read_reference_data();
  end

  % 1. Propellant storage density and volume
  rho_p  = prop_density([], propellant);
  V_prop = m_prop ./ rho_p;   % [m³]

  % 2. Load tank vessel list from database
  vessels = db_data.reference_data.propulsion_system.tank.vessel;
  if isstruct(vessels)
    vessels = {vessels};
  end

  % 3. Resolve propellant aliases for matching
  aliases = get_propellant_aliases(propellant);

  % 4. Collect specific and generic entries separately
  [vol_spec,  mass_spec]  = collect_tank_pairs(vessels, aliases, false);
  [vol_gen,   mass_gen]   = collect_tank_pairs(vessels, aliases, true);

  if numel(vol_spec) >= 2
    vol_data  = vol_spec;
    mass_data = mass_spec;
  elseif numel(vol_gen) >= 2
    vol_data  = vol_gen;
    mass_data = mass_gen;
    if numel(vol_spec) > 0
      warning('m_scale_tank: only %d propellant-specific tank entries for "%s"; using %d generic entries.', ...
              numel(vol_spec), propellant, numel(vol_gen));
    end
  else
    % Fallback: use all entries combined
    [vol_data, mass_data] = collect_tank_pairs(vessels, {}, false);
    warning('m_scale_tank: fewer than 2 suitable tank entries for propellant "%s"; using all %d database entries.', ...
            propellant, numel(vol_data));
  end

  % 5. Build data matrix for scaling_linear:  %TODO: adapt here for proper scaling law derivation and handling
  %      data(3,:) = mass values (output), data(4,:) = volume values (input)
  [vol_s, si] = sort(vol_data);
  mass_s      = mass_data(si);
  data        = [mass_s; vol_s; mass_s; vol_s];   % rows: raw-y, raw-x, fit-y, fit-x

  % 6. Interpolate / extrapolate
  m_tank = scaling_linear(V_prop, data);

end


% ---------------------------------------------------------------------------
function aliases = get_propellant_aliases(propellant)
% Return canonical name variants used in the database for a given propellant.
  pl = lower(strtrim(propellant));
  if any(strcmp(pl, {'xe', 'xenon'}))
    aliases = {'Xe', 'Xenon', 'xenon', 'xe'};
  elseif any(strcmp(pl, {'kr', 'krypton'}))
    aliases = {'Kr', 'Krypton', 'krypton', 'kr'};
  elseif any(strcmp(pl, {'ar', 'argon'}))
    aliases = {'Ar', 'Argon', 'argon', 'ar'};
  elseif any(strcmp(pl, {'he', 'helium'}))
    aliases = {'He', 'Helium', 'helium', 'he'};
  elseif any(strcmp(pl, {'n2h4', 'hydrazine', 'hydrazine (n2h4)'}))
    aliases = {'N2H4', 'Hydrazine', 'hydrazine', 'Hydrazine (N2H4)'};
  elseif any(strcmp(pl, {'nh3', 'ammonia'}))
    aliases = {'NH3', 'nh3', 'Ammonia', 'ammonia'};
  elseif any(strcmp(pl, {'h2', 'hydrogen'}))
    aliases = {'H2', 'Hydrogen', 'hydrogen'};
  elseif any(strcmp(pl, {'water', 'h2o'}))
    aliases = {'Water', 'water', 'H2O', 'h2o'};
  elseif any(strcmp(pl, {'dme', 'dimethyl ether (dme)', 'dimethyl ether'}))
    aliases = {'DME', 'dme', 'Dimethyl Ether (DME)', 'Dimethyl ether'};
  elseif any(strcmp(pl, {'iodine'}))
    aliases = {'Iodine', 'iodine'};
  elseif any(strcmp(pl, {'indium'}))
    aliases = {'Indium', 'indium'};
  elseif any(strcmp(pl, {'bi', 'bismuth'}))
    aliases = {'Bi', 'Bismuth', 'bismuth'};
  elseif any(strcmp(pl, {'emi-im', 'emi-tf', 'emi im', 'emi tf'}))
    aliases = {'EMI-Im', 'EMI-BF4', 'emi-im', 'EMI-Im'};
  else
    aliases = {propellant};
  end
end


% ---------------------------------------------------------------------------
function [vols, masses] = collect_tank_pairs(vessels, aliases, generic_only)
% Extract (volume [m³], dry mass [kg]) pairs from compatible tank entries.
%   generic_only=true  → only entries with absent/empty propellant field
%   generic_only=false → only entries whose propellant matches aliases
%   aliases={}         → collect from ALL entries (no filter)
  vols   = [];
  masses = [];
  no_filter = isempty(aliases) && ~generic_only;

  for i = 1:numel(vessels)
    entry = vessels{i};
    if ~isfield(entry, 'mass') || ~isfield(entry, 'volume')
      continue;
    end
    mass_val   = tank_scalar(entry.mass);
    volume_val = tank_scalar(entry.volume);
    if isnan(mass_val) || isnan(volume_val) || volume_val <= 0
      continue;
    end

    if no_filter
      % Collect everything
    elseif generic_only
      if ~is_generic(entry)
        continue;
      end
    else
      if ~is_specific_match(entry, aliases)
        continue;
      end
    end

    vols(end+1)   = volume_val;   %#ok<AGROW>
    masses(end+1) = mass_val;     %#ok<AGROW>
  end
end


% ---------------------------------------------------------------------------
function result = is_generic(entry)
% True if the entry carries no propellant specification (generic vessel).
  if ~isfield(entry, 'propellant')
    result = true;
  elseif isempty(entry.propellant)
    result = true;
  else
    result = false;
  end
end


% ---------------------------------------------------------------------------
function result = is_specific_match(entry, aliases)
% True if the entry's propellant field matches any of the given aliases.
  if ~isfield(entry, 'propellant') || isempty(entry.propellant)
    result = false;
    return;
  end
  p = entry.propellant;
  if ischar(p)
    result = any(strcmpi(p, aliases));
  elseif iscell(p)
    result = false;
    for k = 1:numel(p)
      if ischar(p{k}) && any(strcmpi(p{k}, aliases))
        result = true;
        return;
      end
    end
  else
    result = false;
  end
end


% ---------------------------------------------------------------------------
function val = tank_scalar(x)
% Return scalar numeric value, or mean of min/max struct, or NaN.
  if isnumeric(x) && isscalar(x) && isfinite(x)
    val = x;
  elseif isstruct(x) && isfield(x, 'min') && isfield(x, 'max')
    val = (x.min + x.max) / 2;
  else
    val = NaN;
  end
end
