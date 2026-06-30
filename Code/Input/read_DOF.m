% read_DOF — Load the Degrees-of-Freedom (mutation space) definition file
%
% PURPOSE:
%   Reads Database/model_DOF (YAML or XML) into a struct.
%   The DOF file defines, per propulsion system type, which parameters the
%   evolutionary algorithm is allowed to mutate (e.g. 'c_e', 'thrust',
%   'propellant') and any technology-specific constraints.
%
% INTENT:
%   Keeps the mutation logic configurable without changing code.  A new
%   propulsion variant (e.g. nuclear pulse) can be introduced by adding an
%   entry to model_DOF rather than modifying set_random_case_parameters or
%   mutate_individual.
%
% Parameters:
%   prefer_xml (logical, optional, default false): Read the XML file when
%              true, otherwise try YAML first.
%
% Returns:
%   DOF (struct): Parsed DOF definitions.
%       Key path: DOF.propulsion_system.<type>.DOF — cell array of mutable
%       parameter names for that technology.  Returns an empty struct on
%       read failure (soft failure to tolerate missing file in early runs).
%
% Usage:
%   DOF = read_DOF()           % YAML preferred
%   DOF = read_DOF(true)       % XML preferred
%
% HOW TO TEST:
%   1. Call and verify DOF.propulsion_system is a struct with at least one
%      technology field (e.g. arcjet, HET).
%   2. Verify each technology field contains a DOF cell array with at least
%      one entry ('c_e', 'thrust', or 'propellant').
%   3. Rename Database/model_DOF.yaml temporarily and confirm the function
%      returns an empty struct without throwing an error (soft-fail path).
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that every propulsion system listed in DOF also exists in the
%     reference database (cross-check against read_reference_data output).
%   - Warn when the file is missing rather than silently returning an empty
%     struct, since an empty DOF causes the evolver to produce no mutations.
function [DOF] = read_DOF(prefer_xml)
    if nargin < 1; prefer_xml = false; end
    disp('Reading Degrees of Freedom Input File');

    try
        % read_file_auto selects YAML or XML and normalises via typeset_struct.
        DOF = read_file_auto('Database/model_DOF', prefer_xml);
        disp('Success');
        disp(' ');
        fflush(stdout);
    catch err
        % Soft failure: an empty struct allows the caller to detect the
        % problem via isempty(DOF) without crashing during early development.
        disp('No Degrees of Freedom Input File');
        DOF = struct();
    end
end