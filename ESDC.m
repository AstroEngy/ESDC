% ESDC: Evolutionary Spacecraft Design Code
% 
% This function serves as the main entry point for the ESDC program. It facilitates
% the generic design of spacecraft using correlations and applies evolutionary optimization
%
% Parameters:
%   runID (optional): Identifier for the current run of the program. If not provided, defaults to 0.
%
% Functionality:
%   1. Initializes the environment and adds necessary paths for the relevant folders.
%   2. Starts the program and logs the initial status.
%   3. Updates the scaling database if needed.
%   4. Processes the input files for the current simulation.
%   5. Executes the evolutionary algorithm to solve the design problem.
%   6. Generates the output in XML format.
%   7. Logs the completion status and total execution time.
%   8. Handles any exceptions, logs error messages, and terminates the program if an error occurs.
%
% Usage:
%   ESDC(runID)
%
% Example:
%   ESDC(1)  % Runs the ESDC program with runID set to 1, a respective output folder will be created
%   ESDC()   % Runs the ESDC program with the default runID (0)


function ESDC(runID, force_db_update)
if nargin < 1
  runID = 0;
end
if nargin < 2
  force_db_update = 1;  % Default to NOT forcing update
end

clc

startTime = tic();                               % Reference timer for performance evaluation: Start

    try

    % Path adding for relevant folders containing code
        folders = {'Code/Analysis', 'Code/Evolver', 'Code/Input', 'Code/Output', 'Code/Scaling', 'Code/Support'};
        for i = 1:length(folders)
            if exist(folders{i}, 'dir')
                addpath(folders{i});
            else
                warning(['Folder not found: ', folders{i}]);
            end
        end
    add_paths_for_visualization();          % additional paths for the visualization codes like video and animation creation
    % Start
    startup();                              % Display startup messages, licenses etc.
    appendToLogFileDCEP('DCEP_STATUS: RUNNING_0%',1,runID)

    %Update Scaling Data Base
    update_scaling_model(force_db_update);                 % Checks for changes in the data bases and derives changed scaling laws unless forced by flag

    %Input
    [input db_data config] = input_processing();   %Reads input files for the specific simulaton at hand

    %Evolve
    evolutionStartTime = tic();                              % Reference timer for evolution process

    evolution_data = evolver(input, db_data, config,runID); % Main solver performance here

    evolutionElapsedTime = toc(evolutionStartTime);          % Calculate elapsed time for evolution
    fprintf('Evolution completed in %.2f seconds (%.2f minutes)\n', evolutionElapsedTime, evolutionElapsedTime/60);

    %Output
    output_XML_generation(input, db_data, config, evolution_data,runID);

    %Visual Output   - old code needs revision and adaption
    %disp('Visual production ')
    %visualization(evolution_data, config);
    %disp('Visual production complete')


    %End
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

