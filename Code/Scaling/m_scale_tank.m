function m_tank = m_scale_tank(m_prop, propellant, db_data)
% TODO prop_density() support is required for the following propellants to enable
%      volume-based scaling (currently falling back to the 25 % mass margin below):
%   Solid sublimable:          Iodine
%   Liquid metals (FEEP/LMIS): Indium, Bismuth
%   Ionic liquids (electrospray): EMI-Im
%   Liquefied gases:           NH3, Dimethyl Ether (DME)
%   Compressed/cryogenic gas:  Hydrogen (H2), H2/N2 mixtures (simulated NH3/N2H4 decomposition products)

% m_scale_tank — Estimate propellant tank dry mass [kg] from propellant mass and type.
%
% Follows the same pattern as m_scale_thruster: a polynomial scaling law is
% derived from database entries (mass vs. storage volume) and cached as a CSV
% file in Database/Scaling/.  On subsequent calls the CSV is read directly.
%
% CSV filename convention:
%   Propellant-specific:
%     Database/Scaling/scaling_propulsion_system_tank_vessel_with_propellant_<P>_mass_to_volume.csv
%   Generic (null-propellant entries only):
%     Database/Scaling/scaling_propulsion_system_tank_vessel_mass_to_volume.csv
%
% Propellant-compatibility filtering rules (applied in order):
%   1. Tank entries whose propellant field is absent or empty are GENERIC vessels.
%   2. Propellant-specific entries are tried first (≥2 required for a fit).
%   3. If fewer than 2 specific entries exist, generic entries are used.
%   4. If still fewer than 2, all entries are combined with a warning.
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
%   m_tank — estimated dry tank dry mass [kg], same size as m_prop

  if nargin < 3 || isempty(db_data) || ~isstruct(db_data) || ~isfield(db_data, 'reference_data')
    db_data = read_reference_data();
  end

  % Fallback for propellants whose storage density is not yet modelled:
  % apply a 25 % tank-mass / propellant-mass ratio  as a worst case fall back
  % Source: Benfield & Belcher (2004), "Modeling of Spacecraft Advanced Chemical
  %         Propulsion Systems", NASA MSFC, NTRS 20050000113.
  if is_unsupported_propellant(propellant)
   % warning('m_scale_tank: prop_density not available for "%s"; using 25%% mass margin (Benfield & Belcher 2004).', propellant);
    m_tank = 0.25 .* m_prop;
    return;
  end

  % 1. Propellant storage density and required volume
  rho_p  = prop_density([], propellant);
  V_prop = m_prop ./ rho_p;   % [m³]

  % 2. Determine which CSV to use (propellant-specific preferred)
  aliases  = get_propellant_aliases(propellant);
  csv_spec = strcat('Database/Scaling/scaling_propulsion_system_tank_vessel_with_propellant_', ...
                    propellant, '_mass_to_volume.csv');
  csv_gen  = 'Database/Scaling/scaling_propulsion_system_tank_vessel_mass_to_volume.csv';

  % Check counts to decide which CSV level is appropriate
  vessels = db_data.reference_data.propulsion_system.tank.vessel;
  if isstruct(vessels); vessels = {vessels}; end
  [~, ms] = collect_tank_pairs(vessels, aliases, false);
  [~, mg] = collect_tank_pairs(vessels, aliases, true);
  n_spec = numel(ms);
  n_gen  = numel(mg);

  if n_spec >= 2
    filename = csv_spec;
  elseif n_gen >= 2
    filename = csv_gen;
    if n_spec > 0
      warning('m_scale_tank: only %d propellant-specific entries for "%s"; using generic CSV.', n_spec, propellant);
    end
  else
    filename = csv_gen;
    warning('m_scale_tank: fewer than 2 suitable entries for "%s"; using generic CSV with all entries.', propellant);
  end

  % 3. Generate CSV from DB if it does not yet exist
  if ~exist(filename, 'file')
    create_tank_scaling_csv(filename, vessels, aliases, n_spec);
  end

  % 4. Load the fitted scaling law and interpolate
  data = dlmread(filename, ',');
  % CSV layout (same as thruster CSVs):
  %   row 1: raw y (mass),  row 2: raw x (volume)
  %   row 3: fit y (mass),  row 4: fit x (volume)
  % scaling_linear expects data(3,:)=y, data(4,:)=x
  data(1:2, :) = [data(2,:); data(1,:)];
  data(3:4, :) = [data(4,:); data(3,:)];

  m_tank = scaling_linear(V_prop, data);

end


% ---------------------------------------------------------------------------
function create_tank_scaling_csv(filename, vessels, aliases, n_spec)
% Collect (volume, mass) pairs, fit a polynomial, and write the CSV.
  if n_spec >= 2
    % propellant-specific entries
    [vols, masses] = collect_tank_pairs(vessels, aliases, false);
  else
    % generic (null-propellant) entries, or all if still insufficient
    [vols, masses] = collect_tank_pairs(vessels, aliases, true);
    if numel(vols) < 2
      [vols, masses] = collect_tank_pairs(vessels, {}, false);
    end
  end

  if isempty(vols)
    warning('m_scale_tank: no valid tank entries found; using dummy scaling.');
    vols   = [0.001, 0.002];
    masses = [1.0,   2.0  ];
  elseif numel(vols) == 1
    vols   = [vols,   vols(1)*2  ];
    masses = [masses, masses(1)*2];
  end

  % Sort by volume
  [vols, si] = sort(vols);
  masses = masses(si);

  % Deduplicate: average masses at identical volumes
  [vols_u, ia] = unique(vols, 'stable');
  masses_u = zeros(size(vols_u));
  for k = 1:numel(vols_u)
    masses_u(k) = mean(masses(vols == vols_u(k)));
  end

  % write_selected_data_to_file fits a polynomial (via data_fitting) and
  % writes both the raw data and the fitted curve to the CSV.
  write_selected_data_to_file(masses_u, vols_u, filename, 0);
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
    aliases = {'Water', 'water', 'H2O', 'h2o', 'distilled water', 'de-ionized water', 'deionized water'};
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


% ---------------------------------------------------------------------------
function result = is_unsupported_propellant(propellant)
% True for propellants whose storage density is not yet modelled in prop_density().
% These receive the 25 % mass-margin fallback (Benfield & Belcher 2004, NTRS 20050000113).
%   Solid sublimable:             Iodine
%   Liquid metals (FEEP/LMIS):    Indium, Bismuth
%   Ionic liquids (electrospray): EMI-Im
%   Liquefied gases:              NH3, Dimethyl Ether (DME)
%   Compressed/cryogenic gas:     Hydrogen (H2), H2/N2 mixtures
  unsupported = { ...
    'iodine', ...
    'indium', ...
    'bi', 'bismuth', ...
    'emi-im', 'emi-tf', 'emi im', 'emi tf', ...
    'nh3', 'ammonia', ...
    'dme', 'dimethyl ether (dme)', 'dimethyl ether', ...
    'h2', 'hydrogen' ...
  };
  pl = lower(strtrim(propellant));
  % Exact match for most entries; prefix match for 'h2/n2' to catch long
  % variants like "H2/N2 mixtures (simulated NH3/N2H4 decomposition products)".
  result = any(strcmp(pl, unsupported)) || strncmp(pl, 'h2/n2', 5);
end
