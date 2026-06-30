% appendToLogFileDCEP — Write a status or error message to the run log file
%
% PURPOSE:
%   Appends (or creates) a plain-text log file at
%   Output/<runID>/ESDC_tool.log.  Used by ESDC() to record the lifecycle
%   status tokens (RUNNING / FINISHED / ERROR) and any exception messages
%   so that external orchestration tools (e.g. DCEP) can poll the file for
%   progress without needing a live console connection.
%
% INTENT:
%   Keeps logging decoupled from the console so that batch runs are
%   auditable after the fact.  The `restart` flag allows the first call
%   of a run to clear stale log content from a previous run with the same
%   runID.
%
% Parameters:
%   data    (string) : The text line to write to the log.
%                      Convention: status tokens are prefixed "DCEP_STATUS:".
%   restart (logical): 1 = overwrite the log file (new run start).
%                      0 = append to the existing file.
%   runID   (integer): Run identifier — determines the Output/<runID>/ path.
%
% Returns:  none (side-effect: writes/appends to log file)
%
% Usage:
%   appendToLogFileDCEP('DCEP_STATUS: RUNNING_0%', 1, runID)  % start of run
%   appendToLogFileDCEP('DCEP_STATUS: FINISHED',   0, runID)  % normal end
%   appendToLogFileDCEP('DCEP_STATUS: ERROR',       0, runID)  % on exception
%   appendToLogFileDCEP(exception.message,          0, runID)  % error detail
%
% HOW TO TEST:
%   1. Call with restart=1: verify Output/0/ESDC_tool.log is (re)created
%      containing exactly the supplied string.
%   2. Call again with restart=0: verify the second string is appended on a
%      new line without overwriting the first.
%   3. Supply a non-existent runID folder: confirm the directory is created
%      automatically and the log file appears inside it.
%   4. Simulate a read-only Output/ folder and verify a meaningful OS error
%      (fopen failure) surfaces rather than a silent data loss.
%
% SAFEGUARDS TO ADD (future work):
%   - Check that fopen succeeded (fileID == -1 on failure) and throw an
%     error rather than silently writing nothing.
%   - Sanitize `data` to strip non-printable characters that could break
%     log parsers.
function appendToLogFileDCEP(data, restart,runID)

    % Construct output folder path for this run
    folderPath = strcat('Output/',num2str(runID));

    % Create the run-output folder if it does not yet exist.
    % exist() returns 7 for directories; any other value means missing.
    if ~(exist(folderPath, 'dir') == 7)
      mkdir(folderPath)
    end

    logFileName = fullfile(folderPath, 'ESDC_tool.log');

    % Open in write mode ('w') at the start of a run to clear old content,
    % or append mode ('a') for all subsequent calls within the same run.
    if restart || ~exist(logFileName, 'file')
        fileID = fopen(logFileName, 'w');
    else
        fileID = fopen(logFileName, 'a');
    end

    fprintf(fileID, '%s\n', data);
    fclose(fileID);
end

