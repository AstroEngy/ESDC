function eff = literature_fallback_efficiency(propulsion_type, propellant)
  % Returns literature-based typical thruster jet efficiency (P_jet/P_in) by technology.
  % Used only when no DB entry or calculable efficiency is available.
  %
  % Sources:
  %   Arcjet (N2H4, ~1-2 kW): NASA TM-105340, Sankovic et al. (1991), p.8:
  %     2 kW H2 arcjet (hydrazine products surrogate), eta=0.307 at 935 s Isp over 150 h.
  %     Flight-qualified MR-509/MR-512 development: Riehle et al., IEPC-97-008 (1997), p.65.
  %     Typical range 30-40%; recommended fallback: 0.35.
  %
  %   HET (Xe, 1-5 kW): Goebel & Katz, Fundamentals of Electric Propulsion (2008), Table 1-1.
  %     SPT-100: 0.50, PPS-1350-G: 0.55; SPT series 0.35-0.55, advanced up to 0.60.
  %     Recommended fallback: 0.55.
  %
  %   Gridded ion (Xe): Goebel & Katz (2008), Tables 1-1, 9-2 to 9-7.
  %     NSTAR: 0.42-0.631, XIPS: 0.67-0.688; typical range 40-80%.
  %     Recommended fallback: 0.60.
  %
  %   FEEP / Electrospray (In, EMI-Im): IEPC-2009-242.
  %     BET-300-P: 0.28-0.45; overall 40-60% with ~45-50% propellant utilisation.
  %     Recommended fallback: 0.50.

  switch lower(propulsion_type)
    case 'arcjet'
      eff = 0.35;
    case 'het'
      eff = 0.55;
    case 'gridionthruster'
      eff = 0.60;
    case {'feep', 'electrospray'}
      eff = 0.50;
    case {'chemical', 'resistojet'}
      % Chemical / resistojet: efficiency here is combustion+nozzle efficiency (c* efficiency),
      % NOT P_jet/P_electrical. Electrical input is negligible compared to propellant enthalpy.
      % Typical bipropellant c* efficiency: 0.94-0.99 (Sutton & Biblarz, Rocket Propulsion Elements, 8th ed.)
      % Monopropellant hydrazine: 0.85-0.95 (Brown, Spacecraft Propulsion, AIAA, 1996)
      % Resistojet adds ~10-30% Isp augmentation via electrical heating; combustion eff ~0.90.
      % Recommended fallback: 0.90
      eff = 0.90;
    otherwise
      eff = 0.30;  % generic fallback, recommended here as 30% to consider a worst case
  endswitch
endfunction
