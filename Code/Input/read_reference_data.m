% read_reference_data — Load the hardware component reference database
%
% PURPOSE:
%   Reads Database/ESDC_Reference_Data_Systems (YAML or XML) into a struct.
%   This file contains the catalogue of real space hardware components
%   (thrusters, tanks, PPUs, solar panels, batteries, etc.) organised by
%   subsystem and technology type.  Used by the evolver for propulsion
%   performance data and by select_components() for hardware matching.
%
% INTENT:
%   Decouples data from code.  All component characteristics (c_e ranges,
%   thrust ranges, mass, power) live in the XML/YAML database rather than
%   in hard-coded arrays.  Adding a new thruster type only requires editing
%   the database, not the solver code.
%
% Parameters:
%   prefer_xml (logical, optional, default false): When true, reads the XML
%              file; when false (default) the YAML file is read first.
%
% Returns:
%   database (struct): Parsed hardware catalogue.
%       Key sub-path: database.reference_data.propulsion_system.<type>
%       where <type> is e.g. 'arcjet', 'HET', 'gridionthruster', etc.
%
% Usage:
%   database = read_reference_data()           % YAML preferred
%   database = read_reference_data(true)       % XML preferred
%
% HOW TO TEST:
%   1. Call and confirm the returned struct contains
%      database.reference_data.propulsion_system with at least one entry.
%   2. Temporarily corrupt Database/ESDC_Reference_Data_Systems.yaml and
%      confirm a clear parse error is reported (not a silent empty struct).
%   3. Toggle prefer_xml and confirm identical struct shapes are returned
%      from both file variants.
%
% SAFEGUARDS TO ADD (future work):
%   - Assert that at least one propulsion system entry is present after
%     loading; an empty catalogue will cause silent convergence failures.
%   - Log the number of component entries loaded for traceability.
function [database] = read_reference_data(prefer_xml)
    if nargin < 1; prefer_xml = false; end
    disp('Reading Reference Data Input File');
    % read_file_auto selects YAML or XML based on the prefer_xml flag and
    % file availability, then returns a normalised struct via typeset_struct.
    database = read_file_auto('Database/ESDC_Reference_Data_Systems', prefer_xml);
    disp('Success');
    disp(' ');
    fflush(stdout);
end