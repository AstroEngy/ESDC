function rho_p = prop_density(p_max, propellant)
% TODO: Rework to config files
% prop_density — Nominal storage density for spacecraft propellants [kg/m³].
%
% Returns the bulk storage density at typical spacecraft tank operating conditions.
% For compressed gases, p_max [bar] scales the ideal-gas density estimate; for
% liquids and solids, p_max is ignored and may be passed as [].
%
% Inputs:
%   p_max      — max storage pressure [bar]; pass [] or omit to use per-propellant defaults
%   propellant — propellant name string (case-insensitive, common aliases accepted)
%
% Supported propellants:
%   N2H4 / Hydrazine / "Hydrazine (N2H4)"  — 1008 kg/m³  liquid monoprop, 20°C          NIST SRD 69, CAS 302-01-2
%   NH3                                     —  610 kg/m³  liquid, saturated 20°C          NIST SRD 69, CAS 7664-41-7
%   He                                      —   43 kg/m³  compressed gas, 300 bar, 20°C  NIST SRD 69, CAS 7440-59-7
%   Xe / Xenon                              — 2300 kg/m³  supercrit., 300 bar, 20°C      NIST SRD 69, CAS 7440-63-3
%   Kr / Krypton                            — 2700 kg/m³  supercrit., 300 bar, 20°C      NIST SRD 69, CAS 7439-90-9
%   Ar / Argon                              —  535 kg/m³  compressed gas, 300 bar, 20°C  NIST SRD 69, CAS 7440-37-1
%   Hydrogen / H2                           —   71 kg/m³  liquid cryo (LH2), NBP         NIST SRD 69, CAS 1333-74-0
%   Water / H2O                             —  998 kg/m³  liquid, 20°C                   NIST SRD 69, CAS 7732-18-5
%   DME / "Dimethyl Ether (DME)"            —  660 kg/m³  liquid, saturated 20°C         NIST SRD 69, CAS 115-10-6
%   Indium                                  — 7030 kg/m³  liquid metal, ~200°C           NIST SRD 69, CAS 7440-74-6
%   Bi / Bismuth                            — 10050 kg/m³ liquid metal, ~305°C           NIST SRD 69, CAS 7440-69-9
%   Iodine                                  — 4930 kg/m³  solid, 20°C                    NIST SRD 69, CAS 7553-56-6
%   EMI-Im / EMI-BF4 (ionic liquid)         — 1520 kg/m³  electrospray propellant, 20°C  Sigma-Aldrich, CAS 174899-83-3
%   H2/N2 mixtures (NH3/N2H4 decomp.)       — treated as NH3 (similar density at storage)
%
% Fallback: unknown propellants return 1000 kg/m³ with a warning.

  if nargin < 1; p_max = []; end

  prop_lc = lower(strtrim(propellant));

  % --- resolve common aliases to canonical names ---
  if any(strcmp(prop_lc, {'n2h4', 'hydrazine', 'hydrazine (n2h4)'}))
    prop_lc = 'n2h4';
  elseif any(strcmp(prop_lc, {'xe', 'xenon'}))
    prop_lc = 'xe';
  elseif any(strcmp(prop_lc, {'kr', 'krypton'}))
    prop_lc = 'kr';
  elseif any(strcmp(prop_lc, {'ar', 'argon'}))
    prop_lc = 'ar';
  elseif any(strcmp(prop_lc, {'hydrogen', 'h2'}))
    prop_lc = 'h2';
  elseif any(strcmp(prop_lc, {'water', 'h2o'}))
    prop_lc = 'water';
  elseif any(strcmp(prop_lc, {'dme', 'dimethyl ether (dme)', 'dimethyl ether'}))
    prop_lc = 'dme';
  elseif any(strcmp(prop_lc, {'bi', 'bismuth'}))
    prop_lc = 'bi';
  elseif any(strcmp(prop_lc, {'emi-im', 'emi-tf', 'emi im', 'emi tf'}))
    prop_lc = 'emi-im';
  elseif strncmp(prop_lc, 'h2/n2', 5) || ~isempty(strfind(prop_lc, 'nh3/n2h4 decomposition'))
    % "H2/N2 mixtures (simulated NH3/N2H4 decomposition products)" — treat as NH3
    prop_lc = 'nh3';
  end

  switch prop_lc
    case 'n2h4'
      rho_p = 1008;   % liquid hydrazine, 20°C, 1 atm.
                      % NIST Chemistry WebBook, SRD 69, Hydrazine (CAS 302-01-2)
    case 'nh3'
      rho_p = 610;    % liquid ammonia, saturated at 20°C (~8.6 bar).
                      % NIST Chemistry WebBook, SRD 69, Ammonia (CAS 7664-41-7)
    case 'he'
      % Compressed helium — ideal-gas scaling: rho ∝ pressure.
      % Reference density: 43.14 kg/m³ at 300 bar, 20°C.
      % NIST Chemistry WebBook, SRD 69, Helium (CAS 7440-59-7)
      if ~isempty(p_max) && p_max > 0
        if p_max > 1e4; p_bar = p_max / 1e5; else; p_bar = p_max; end  % accept Pa or bar
      else
        p_bar = 300;  % default storage pressure [bar]
      end
      rho_p = 43.14 * (p_bar / 300);
    case 'xe'
      rho_p = 2300;   % supercritical xenon, 300 bar, 20°C (Tc = 289.77 K, Pc = 5.84 MPa).
                      % NIST Chemistry WebBook, SRD 69, Xenon (CAS 7440-63-3)
    case 'kr'
      rho_p = 2700;   % supercritical krypton, 300 bar, 20°C (Tc = 209.48 K, Pc = 5.53 MPa).
                      % NIST Chemistry WebBook, SRD 69, Krypton (CAS 7439-90-9)
    case 'ar'
      rho_p = 535;    % compressed argon, 300 bar, 20°C (Tc = 150.86 K, Pc = 4.90 MPa).
                      % NIST Chemistry WebBook, SRD 69, Argon (CAS 7440-37-1)
    case 'h2'
      rho_p = 70.8;   % liquid hydrogen (LH2), normal boiling point -252.87°C, 1 atm.
                      % NIST Chemistry WebBook, SRD 69, Hydrogen (CAS 1333-74-0)
    case 'water'
      rho_p = 998;    % liquid water, 20°C, 1 atm.
                      % NIST Chemistry WebBook, SRD 69, Water (CAS 7732-18-5)
    case 'dme'
      rho_p = 660;    % liquid DME, saturated at 20°C (~5.1 bar).
                      % NIST Chemistry WebBook, SRD 69, Dimethyl ether (CAS 115-10-6)
    case 'indium'
      rho_p = 7030;   % liquid indium, ~200°C (FEEP propellant; mp = 156.6°C).
                      % NIST Chemistry WebBook, SRD 69, Indium (CAS 7440-74-6)
    case 'bi'
      rho_p = 10050;  % liquid bismuth, ~305°C (FEEP propellant; mp = 271.5°C).
                      % NIST Chemistry WebBook, SRD 69, Bismuth (CAS 7440-69-9)
    case 'iodine'
      rho_p = 4930;   % solid iodine, 20°C, 1 atm.
                      % NIST Chemistry WebBook, SRD 69, Iodine (CAS 7553-56-6)
    case 'emi-im'
      rho_p = 1520;   % 1-ethyl-3-methylimidazolium bis(trifluoromethylsulfonyl)imide
                      % (ionic liquid, electrospray propellant), 20°C.
                      % Sigma-Aldrich Product No. 711691, CAS 174899-83-3
    otherwise
      warning('prop_density: unknown propellant "%s" — assuming 1000 kg/m³.', propellant);
      rho_p = 1000;
  end

end
