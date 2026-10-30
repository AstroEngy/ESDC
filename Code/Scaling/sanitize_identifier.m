% sanitize_identifier  Convert a display name to a filesystem-safe identifier.
%
% safe_id = sanitize_identifier(display_name)
%   Replaces characters that are illegal or semantically significant in
%   filesystem paths (/, \, :, *, ?, ", <, >, |, spaces, parentheses) with
%   underscores, then collapses repeated underscores and trims the result.
%
% The original display name is preserved separately as metadata in the YAML
% (e.g. classification.propellant).  Do NOT pass sanitized identifiers back
% to scientific computations that expect the original chemical name.
%
% Examples
%   sanitize_identifier('H2/N2 mixtures (simulated NH3/N2H4 dec. products)')
%     -> 'H2_N2_mixtures_simulated_NH3_N2H4_dec._products'
%   sanitize_identifier('Hydrazine (N2H4)')
%     -> 'Hydrazine_N2H4'
%   sanitize_identifier('EMI-Im')
%     -> 'EMI-Im'   % hyphens are safe and kept
function safe_id = sanitize_identifier(display_name)
  safe_id = char(display_name);
  for ch = {'/', '\', ':', '*', '?', '"', '<', '>', '|'}
    safe_id = strrep(safe_id, ch{1}, '_');
  end
  safe_id = strrep(safe_id, ' ', '_');
  safe_id = strrep(safe_id, '(', '');
  safe_id = strrep(safe_id, ')', '');
  while ~isempty(strfind(safe_id, '__'))
    safe_id = strrep(safe_id, '__', '_');
  end
  while ~isempty(safe_id) && safe_id(1) == '_';   safe_id = safe_id(2:end);   end
  while ~isempty(safe_id) && safe_id(end) == '_'; safe_id = safe_id(1:end-1); end
end
