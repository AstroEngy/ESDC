% scaling_law_cache  Persistent in-memory cache for loaded scaling laws.
%
% [law, found] = scaling_law_cache('get', key)
%   Retrieve law by key. found=false when not cached.
%
% scaling_law_cache('set', key, law)
%   Store a law under key. Overwrites existing entry.
%
% scaling_law_cache('clear')
%   Evict all entries (call after explicitly reloading database files).
%
% scaling_law_cache('stats')
%   Print cache size to stdout.
%
% Key should be the canonical file stem (no extension) or ID string.
% The cache is process-scoped; it survives across function calls but not
% across Octave sessions or after 'clear all'.
function [law, found] = scaling_law_cache(op, key, val)
  persistent CACHE;
  if isempty(CACHE)
    CACHE.keys = {};
    CACHE.laws = {};
  end

  law   = [];
  found = false;

  switch op
    case 'get'
      if nargin < 2; return; end
      idx = find(strcmp(CACHE.keys, key));
      if ~isempty(idx)
        law   = CACHE.laws{idx(1)};
        found = true;
      end

    case 'set'
      if nargin < 3; return; end
      idx = find(strcmp(CACHE.keys, key));
      if isempty(idx)
        CACHE.keys{end+1} = key;
        CACHE.laws{end+1} = val;
      else
        CACHE.laws{idx(1)} = val;
      end
      law   = val;
      found = true;

    case 'clear'
      CACHE.keys = {};
      CACHE.laws = {};

    case 'stats'
      fprintf('scaling_law_cache: %d entries cached\n', numel(CACHE.keys));

    otherwise
      error('scaling_law_cache: unknown operation ''%s''', op);
  end
end
