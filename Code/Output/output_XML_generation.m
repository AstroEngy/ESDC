% output_XML_generation — Write evolution results to XML output files
%
% PURPOSE:
%   Post-processes the evolution_data cell array and writes it to one or
%   two XML output files depending on configuration:
%     1. Full history XML — all generations plus the best snapshot (when
%        output.xml.full_history = true).  Large; useful for convergence analysis.
%     2. Best-candidates XML — only the best individual per lineage, with
%        component match results (when output.xml.optimal_candidates = true).
%
% INTENT:
%   Separates output serialisation from the solver.  XML is chosen as the
%   interchange format for compatibility with DCEP and post-processing tools.
%   Attribute definitions (name, unit, description) are injected from
%   Database/ESDC_variable_attributes.xml to make the output self-documenting.
%
% Parameters:
%   input          (struct): Mission parameters (unused directly; passed for
%                  potential future context embedding in output).
%   db_data        (struct): Reference database (unused directly here;
%                  passed through to output_XML_best_candidates).
%   config         (struct): Simulation settings.  Controls output flags:
%       .Simulation_parameters.output.xml.full_history
%       .Simulation_parameters.output.xml.optimal_candidates
%   evolution_data (cell):   Best-per-lineage snapshot (from evolver).
%   runID          (integer): Determines Output/<runID>/ output path.
%
% Returns: none (side-effect: writes XML files to Output/<runID>/).
%
% HOW TO TEST:
%   1. Run with full_history=true and confirm Output/<runID>/
%      contains a full history XML with as many generation entries as
%      the evolver reported generations.
%   2. Run with optimal_candidates=true and confirm Output/<runID>/
%      contains a best-candidates XML with one entry per seed.
%   3. Run with both flags false and confirm no XML files are written
%      (no crash, just no output).
%   4. Validate the output XML against ESDC_Input.xsd if a schema exists.
%   5. Confirm that all numeric fields in the XML have unit attributes
%      from ESDC_variable_attributes.xml.
%
% SAFEGUARDS TO ADD (future work):
%   - Catch and log XML write errors (e.g. disk full) rather than crashing.
%   - Validate that evolution_data{end} is non-empty before processing.
function output_XML_generation(input, db_data, config, evolution_data,runID)
disp('XML production ')

output_struct=struct;

% ---- Step 1: Inject attribute metadata (unit, description) ---------------
% Wraps every numeric/string field in a sub-struct with .Text and .dcep_info
% so the serialised XML is self-documenting.
evolution_data = output_XML_attributes(evolution_data);

% ---- Step 2: Re-shape data for lineage-history XML -----------------------
output_struct.evolution_lineage_history = evolution_data_preprocessing(evolution_data);

% ---- Step 3: Write full history XML (optional) ---------------------------
if config.Simulation_parameters.output.xml.full_history
  output_XML_full_history(output_struct,runID);
end

% ---- Step 4: Write best-candidates XML (optional) ------------------------
if config.Simulation_parameters.output.xml.optimal_candidates
  output_XML_best_candidates(config, evolution_data,runID);
end

disp('XML Output complete')
disp(' ')

end


% output_XML_attributes — Inject metadata attributes into all fields of evolution_data
%
% PURPOSE:
%   Walks every field of every individual in the final generation and wraps
%   each value with its attribute metadata (name, unit, description) read
%   from Database/ESDC_variable_attributes.xml.  This makes the XML output
%   self-documenting without requiring the reader to consult a separate schema.
%
% Parameters:
%   unprocessed_data (cell): evolution_data as returned by evolver.
%
% Returns:
%   processed_data (cell): Same structure with fields wrapped in sub-structs
%       containing .Text (the value as string) and .dcep_info (attributes).
function processed_data = output_XML_attributes(unprocessed_data);

  % Load and parse the attribute definition file
  attr_definitions = xml2struct('Database/ESDC_variable_attributes.xml');
  attr_definitions = typeset_struct(attr_definitions);
  attr_definitions = attr_definitions.variable_attributes;

for i=1:size(unprocessed_data{end},1)
   for j=1:size(unprocessed_data{end},2)
      fields= fieldnames(unprocessed_data{end}(i,j));
      for k=1: size(fields,1)

        % skip component_matches — already exported separately by select_components
        if strcmp(fields{k,1}, 'component_matches'); continue; end
        unprocessed_data{end}(i,j).(fields{k,1}) = createAttributes(fields{k,1}, unprocessed_data{end}(i,j).(fields{k,1}),  attr_definitions);

      end
    end
end

processed_data =unprocessed_data;

end

% createAttributes — Recursively wrap a value with its DCEP attribute metadata
%
% PURPOSE:
%   For struct values, recurse into each field.
%   For scalar/string values, wrap in .Text + .dcep_info.
%   If no attribute is defined for a field name, dcep_info.none is set.
function out = createAttributes(name, val, attr_definitions)

  out = struct();
  if isstruct(val)

    [out.dcep_info] = getAttributes(name, attr_definitions); % here name of variable

      fields= fieldnames(val);
      for k=1: size(fields,1)
        out.(fields{k,1}) = createAttributes(fields{k,1}, val.(fields{k,1}), attr_definitions);
      end

  else
      % Convert numeric values to strings for XML text nodes
      if isnumeric(val)
      out.Text = num2str(val);
      else
      out.Text=val;
      end
      [out.dcep_info] = getAttributes(name, attr_definitions);

  end
end

% getAttributes — Look up attribute metadata for one variable name
%
% PURPOSE:
%   Searches the attribute definitions struct for a key matching var_name.
%   Returns all attribute sub-fields (name, unit, description) if found,
%   or a .none marker when the variable is not defined in the DB.
function [out_attributes] = getAttributes(var_name,attributes)

  fields = fieldnames(attributes);
  if any(strcmp(var_name,fields))
    % Variable found: copy all its attribute fields
    attr_fields= fieldnames(attributes.(var_name));
    for i=1:size(attr_fields,1)
      out_attributes.(attr_fields{i}) =attributes.(var_name).(attr_fields{i});
    end
  else
    % Variable not in attributes DB: mark as undefined
    out_attributes.none="no attributes defined";
  end
end
