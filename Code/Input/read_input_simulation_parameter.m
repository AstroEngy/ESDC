% read_input_simulation_parameter — Load the solver configuration file
%
% PURPOSE:
%   Reads Input/ESDC_Simulation_parameters (YAML or XML) into a struct.
%   The resulting struct controls the evolver behaviour (seed count, max
%   generations, fitness criterion, random seed, verbosity, output flags).
%   Called first in input_processing() so that the prefer_xml flag it
%   contains is available for all subsequent file reads.
%
% INTENT:
%   Separates simulation configuration (how the solver runs) from mission
%   parameters (what the spacecraft must do).  Keeping them in different
%   files lets users share a single simulation config across many missions.
%
% Parameters:  none
% Returns:
%   simulation_parameters (struct): Parsed content of
%       Input/ESDC_Simulation_parameters.yaml/.xml.
%       Key sub-fields used elsewhere:
%         .Simulation_parameters.evolver.seed_points
%         .Simulation_parameters.evolver.max_generations
%         .Simulation_parameters.evolver.fitness_criterion
%         .Simulation_parameters.evolver.random_seed
%         .Simulation_parameters.io.prefer_xml
%         .Simulation_parameters.output.xml.full_history
%         .Simulation_parameters.output.xml.optimal_candidates
%         .Simulation_parameters.output.CLI.n_verbosity
%         .Simulation_parameters.defaults.sc_type_thresholds
%         .Simulation_parameters.defaults.mission_duration_years
%         .Simulation_parameters.defaults.propulsion_time_fraction
%
% Usage:
%   simulation_parameters = read_input_simulation_parameter()
%
% HOW TO TEST:
%   1. Call the function and verify the returned struct contains a
%      Simulation_parameters field with at least evolver and output sub-fields.
%   2. Rename or delete Input/ESDC_Simulation_parameters.yaml and confirm
%      the error message "ERROR: No Simulation Parameter Input File: ..."
%      is thrown — not a silent empty struct.
%   3. Swap YAML for XML (set prefer_xml manually in the YAML) and verify
%      the XML variant is loaded without error.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate mandatory fields after loading (e.g. assert that
%     evolver.seed_points is a positive integer) so mis-configured files
%     are detected here rather than mid-run.
function [simulation_parameters] = read_input_simulation_parameter()
    disp('Reading Simulation Parameter Input File');
    try
        % read_file_auto tries YAML first (or XML first if prefer_xml was set,
        % but here we have no flag yet so YAML is always attempted first).
        simulation_parameters = read_file_auto('Input/ESDC_Simulation_parameters');
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        % Hard-fail: without simulation parameters the solver cannot run.
        error('ERROR: No Simulation Parameter Input File: %s', err.message);
    end
end


