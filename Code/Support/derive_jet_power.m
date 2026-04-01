% derive_jet_power — Compute jet (kinetic exhaust) power from available knowns.
%
% Jet power is the kinetic-energy flux of the exhaust in vacuum:
%
%   Pjet = 0.5 * m_dot * ve^2
%
% Three equivalent forms are tried in order of preference; the first for
% which all required inputs are finite and positive is used:
%
%   Method 1: Pjet = 0.5 * T * ve          (T and ve known)
%   Method 2: Pjet = T^2 / (2 * m_dot)     (T and m_dot known)
%   Method 3: Pjet = 0.5 * m_dot * ve^2    (m_dot and ve known)
%
% Inputs (any unknown quantity should be passed as NaN):
%   T     — thrust [N]
%   ve    — effective exhaust velocity / c_e [m/s]
%   mdot  — propellant mass-flow rate [kg/s]
%
% Outputs:
%   power  — jet power [W], or NaN if no method can be applied
%   method — string naming the formula used (e.g. '0.5*T*ve'), or '' if NaN
%
% All three formulae are mathematically equivalent under the ideal-rocket
% relation T = m_dot * ve; numerical differences arise only from rounding in
% the DB values.

function [power, method] = derive_jet_power(T, ve, mdot)
  if nargin < 1; T    = NaN; end
  if nargin < 2; ve   = NaN; end
  if nargin < 3; mdot = NaN; end

  power  = NaN;
  method = '';

  % Method 1: Pjet = 0.5 * T * ve
  if is_pos(T) && is_pos(ve)
    power  = 0.5 * T * ve;
    method = '0.5*T*ve';
    return;
  end

  % Method 2: Pjet = T^2 / (2 * mdot)
  if is_pos(T) && is_pos(mdot)
    power  = T^2 / (2 * mdot);
    method = 'T^2/(2*mdot)';
    return;
  end

  % Method 3: Pjet = 0.5 * mdot * ve^2
  if is_pos(mdot) && is_pos(ve)
    power  = 0.5 * mdot * ve^2;
    method = '0.5*mdot*ve^2';
    return;
  end
end

function ok = is_pos(x)
  ok = ~isnan(x) && x > 0;
end
