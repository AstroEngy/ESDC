% get_input_file_path — Resolve input file path with environment variable override
%
% PURPOSE:
%   Determines which mission parameter input file to use by checking:
%   1. ESDC_INPUT_PATH environment variable (highest priority)
%   2. input_file_path from simulation_parameters.Simulation_parameters.io
%   3. Default fallback value
%
% INTENT:
%   Allows flexible input file specification without editing code:
%   - Users can change inputs by editing ESDC_Simulation_parameters.yaml
%   - CI/CD pipelines can override via ESDC_INPUT_PATH environment variable
%   - Maintains backward compatibility with hardcoded default
%
% Parameters:
%   simulation_parameters (struct): Output from read_input_simulation_parameter()
%                                   May be empty/partial on first call.
%
% Returns:
%   input_file_path (string): Resolved path to mission parameter input file
%                             (relative to ESDC root)
%
% Usage:
%   input_path = get_input_file_path(simulation_parameters)
%
% Examples:
%   % Use value from ESDC_Simulation_parameters.yaml
%   input_path = get_input_file_path(sim_params)
%
%   % Override via environment variable (highest priority)
%   setenv('ESDC_INPUT_PATH', 'Input/ESDC_Input_LEO_300kg_Arcjet')
%   input_path = get_input_file_path(sim_params)
%
% HOW TO TEST:
%   1. Call without environment variable; verify it returns value from config.
%   2. Set ESDC_INPUT_PATH and verify it takes precedence.
%   3. Clear both config and env var; verify default fallback is used.
%   4. Use with example input files and verify paths are resolved correctly.
%
function input_file_path = get_input_file_path(simulation_parameters)
  
  % Default fallback (used if nothing else is available)
  default_path = 'Input/ESDC_Input_LEO_650ms_1500W';
  
  % Step 1: Check environment variable (highest priority)
  env_path = getenv('ESDC_INPUT_PATH');
  if ~isempty(env_path)
    input_file_path = env_path;
    fprintf('[get_input_file_path] Using ESDC_INPUT_PATH from environment: %s\n', input_file_path);
    return
  end
  
  % Step 2: Check simulation_parameters config file
  if nargin >= 1 && ~isempty(simulation_parameters) && isstruct(simulation_parameters)
    if isfield(simulation_parameters, 'Simulation_parameters') && ...
       isfield(simulation_parameters.Simulation_parameters, 'io') && ...
       isfield(simulation_parameters.Simulation_parameters.io, 'input_file_path')
      
      config_path = simulation_parameters.Simulation_parameters.io.input_file_path;
      if ~isempty(config_path)
        input_file_path = config_path;
        fprintf('[get_input_file_path] Using input_file_path from ESDC_Simulation_parameters.yaml: %s\n', input_file_path);
        return
      end
    end
  end
  
  % Step 3: Use default fallback
  input_file_path = default_path;
  fprintf('[get_input_file_path] Using default fallback path: %s\n', input_file_path);
  
end
