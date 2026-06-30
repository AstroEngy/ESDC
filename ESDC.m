% ESDC: Evolutionary Spacecraft Design Code
%
% PURPOSE:
%   Top-level entry point for the ESDC tool.  Given mission parameters
%   (mass, delta-v, power, orbit, mission duration) it uses an evolutionary
%   algorithm to converge on one or more candidate spacecraft designs,
%   selecting propulsion technology, sizing all subsystems via SMAD scaling
%   laws, and matching real hardware from a reference database.
%
% INTENT:
%   Acts as the orchestrator; every major processing stage (input, evolution,
%   component selection, output) is delegated to a dedicated module.  This
%   function itself does NOT contain physics — it stitches modules together
%   and provides error handling and logging.
%
% Parameters:
%   runID          (optional, default 0): Integer identifier for this run.
%                  Determines the Output/<runID>/ folder where logs and XML
%                  results are written.  Use distinct values to keep parallel
%                  runs from overwriting each other.
%   force_db_update (optional, default 0): Set to 1 to force regeneration of
%                  all scaling-law CSV files from the XML databases even when
%                  no change is detected.  Useful after manual DB edits.
%
% Outputs:
%   None (results written to Output/<runID>/ as XML + log files).
%
% Usage:
%   ESDC(runID)
%   ESDC(runID, force_db_update)
%
% Example:
%   ESDC(1)     % Run with output written to Output/1/
%   ESDC()      % Default run, output to Output/0/
%   ESDC(2, 1)  % Force DB rebuild then run, output to Output/2/
%
% HOW TO TEST:
%   1. Smoke test:  ESDC()  -- should complete without error and print
%      "ESDC complete" with timing, and create Output/0/ESDC_tool.log.
%   2. Reproducibility: set Simulation_parameters.evolver.random_seed to a
%      fixed integer; two runs with the same seed must produce identical XML.
%   3. Edge-case inputs: run with the example files in
%      Documentation/Example Files/Input/ — one for each sc_type (1–4).
%   4. Force-update test: ESDC(0, 1) — verify Database/Scaling/ CSV files
%      are regenerated (check file timestamps change).
%   5. Error path: supply an invalid Input/ESDC_Input.yaml; confirm an error
%      message is logged to ESDC_tool.log and the exception is re-thrown.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that Output/<runID>/ is writable before starting the run.
%   - Check that required input files exist before calling input_processing().
%   - Warn (not crash) when runID already has existing output so results are
%     not silently overwritten in batch runs.


function ESDC(runID, force_db_update)
if nargin < 1
  runID = 0;
end
if nargin < 2
  force_db_update = 0;  % Default to NOT forcing update
end

clc

startTime = tic();                               % Reference timer for performance evaluation: Start

    try

    % ---- 1. Environment setup -----------------------------------------------
    % Add all code subdirectories to Octave/MATLAB search path so that
    % functions in subdirectories can be called without qualification.
        folders = {'Code/Analysis', 'Code/Evolver', 'Code/Input', 'Code/Output', 'Code/Scaling', 'Code/Support'};
        for i = 1:length(folders)
            if exist(folders{i}, 'dir')
                addpath(folders{i});
            else
                warning(['Folder not found: ', folders{i}]);
            end
        end
    add_paths_for_visualization();          % additional paths for the visualization codes like video and animation creation

    % ---- 2. Startup / logging -----------------------------------------------
    startup();                              % Display startup messages, licenses etc.
    appendToLogFileDCEP('DCEP_STATUS: RUNNING_0%',1,runID)

    % ---- 3. Read all input files --------------------------------------------
    % Returns: mission_parameters (design constraints), db_data (reference
    % hardware DB + SMAD tables), config (simulation settings).
    [input db_data config] = input_processing();   %Reads input files for the specific simulaton at hand

    % ---- 4. Update scaling database (CSV lookup tables) --------------------
    % Must happen AFTER input_processing so prefer_xml is known.
    % Only regenerates when the underlying XML has changed (hash-based).
    prefer_xml = false;
    if isfield(config, 'Simulation_parameters') && isfield(config.Simulation_parameters, 'io') && ...
       isfield(config.Simulation_parameters.io, 'prefer_xml')
      prefer_xml = logical(config.Simulation_parameters.io.prefer_xml);
    end
    update_scaling_model(force_db_update, prefer_xml);     % Checks for changes in the data bases and derives changed scaling laws unless forced by flag

    % ---- 5. Evolutionary optimisation ----------------------------------------
    evolutionStartTime = tic();                              % Reference timer for evolution process

    % Apply deterministic random seed if configured (for reproducible/debug runs).
    % Set Simulation_parameters.evolver.random_seed to a positive integer to enable.
    % Leave unset or set to 0 to use the default non-deterministic seeding.
    if isfield(config.Simulation_parameters.evolver, 'random_seed') && config.Simulation_parameters.evolver.random_seed > 0
      rng(config.Simulation_parameters.evolver.random_seed);
      fprintf('RNG seeded with %d for deterministic run\n', config.Simulation_parameters.evolver.random_seed);
    end

    evolution_data = evolver(input, db_data, config,runID); % Main solver performance here

    evolutionElapsedTime = toc(evolutionStartTime);          % Calculate elapsed time for evolution
    fprintf('Evolution completed in %.2f seconds (%.2f minutes)\n', evolutionElapsedTime, evolutionElapsedTime/60);

    % ---- 6. Component matching ----------------------------------------------
    % Match real hardware from the reference DB to each design candidate.
    % Results are appended as individual.component_matches.<subsystem>.
    evolution_data = select_components(evolution_data, db_data);

    % ---- 7. XML output generation -------------------------------------------
    output_XML_generation(input, db_data, config, evolution_data,runID);

    %Visual Output   - old code needs revision and adaption
    %disp('Visual production ')
    %visualization(evolution_data, config);
    %disp('Visual production complete')

    % ---- 8. Completion ------------------------------------------------------
    disp('ESDC complete')
    totalElapsedTime = toc(startTime);
    fprintf('Total execution time: %.2f seconds (%.2f minutes)\n', totalElapsedTime, totalElapsedTime/60);

    appendToLogFileDCEP('DCEP_STATUS: FINISHED',0,runID)

    catch exception
        % Handle the exception
        disp(['Error occurred: ' exception.message]);
        appendToLogFileDCEP('DCEP_STATUS: ERROR ', 0,runID);
        % Write the error message to the log file
        appendToLogFileDCEP(exception.message, 0,runID);

        % Re-throw the exception to terminate the program
        rethrow(exception);
    end

end

