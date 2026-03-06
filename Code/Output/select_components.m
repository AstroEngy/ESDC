% select_components  — Component matching for optimal design solutions
%
% Orchestrates per-subsystem component selection across all best-solution
% individuals in evolution_data.  Each subsystem selector scans the reference
% database for real hardware components compatible with the design point and
% appends its results to individual.component_matches.<subsystem>.
%
% Subsystems handled:
%   propulsion_system  — thrusters (technology type, propellant, thrust, c_e, power)
%   power_generation   — solar panels & batteries (power, energy capacity)
%   attitude_control   — actuators / magnetorquers / reaction wheels (mass, power)
%   thermal            — heaters / passive elements (mass, power)
%   structure          — bus structures (mass)
%   communication      — transceivers / laser links (mass, power)
%   onboard_computer   — OBC boards (mass, power)
%
% Parameters:
%   evolution_data : cell array returned by evolver (best-per-lineage snapshot)
%   db_data        : database struct as loaded by input_processing
%   config         : configuration struct (simulation parameters)
%   runID          : run identifier (used for output path)
%
% Returns:
%   evolution_data : same cell array with component_matches field added/extended
%                   on every individual in evolution_data{end}.
%     individual.component_matches.<subsystem>  — struct with fields:
%       .system_type     technology variant selected / matched
%       .design_*        design-point parameters used for scoring
%       .candidates      struct array sorted by proximity score (best first)
%         .name          component name from DB
%         .score         proximity score  (1 = perfect, 0 = worst)
%         .mass          component mass [kg]   (NaN if not in DB)
%         .source        DB source string
%         + subsystem-specific performance fields

function evolution_data = select_components(evolution_data, db_data, config, runID)

  disp('Component Selection ...');
  fflush(stdout);

  evolution_data = select_propulsion_components(evolution_data, db_data);
  evolution_data = select_power_generation_components(evolution_data, db_data);
  evolution_data = select_attitude_control_components(evolution_data, db_data);
  evolution_data = select_thermal_components(evolution_data, db_data);
  evolution_data = select_structure_components(evolution_data, db_data);
  evolution_data = select_communication_components(evolution_data, db_data);
  evolution_data = select_obc_components(evolution_data, db_data);

  % Write XML output using the now-annotated evolution_data
  write_component_matches_xml(evolution_data, config, runID);

  disp('Component Selection complete');
  disp(' ');
  fflush(stdout);

end


% -------------------------------------------------------------------------
% Write component matches to XML in Output/<runID>/
% Iterates dynamically over all subsystem fields in component_matches.
function write_component_matches_xml(evolution_data, config, runID)

  n_candidates_out = 5;   % number of top candidates to export per design point
  if isfield(config, 'Simulation_parameters') && ...
     isfield(config.Simulation_parameters, 'output') && ...
     isfield(config.Simulation_parameters.output, 'xml') && ...
     isfield(config.Simulation_parameters.output.xml, 'optimal_candidates')
    n_candidates_out = config.Simulation_parameters.output.xml.optimal_candidates;
  end

  out = struct();

  for i = 1:size(evolution_data{end}, 1)
    case_name = strcat('case_', num2str(i));
    for j = 1:size(evolution_data{end}, 2)
      seed_name = strcat('seed_', num2str(j));

      if ~isfield(evolution_data{end}(i,j), 'component_matches')
        out.(case_name).(seed_name).note = 'No component matches computed';
        continue;
      end

      cm = evolution_data{end}(i,j).component_matches;
      subsystems = fieldnames(cm);

      for s = 1:numel(subsystems)
        sys_name = subsystems{s};
        cm_sys   = cm.(sys_name);

        % Copy all scalar / string design-point fields
        design_fields = fieldnames(cm_sys);
        for f = 1:numel(design_fields)
          fname = design_fields{f};
          if strcmp(fname, 'candidates'); continue; end
          out.(case_name).(seed_name).(sys_name).(fname) = cm_sys.(fname);
        end

        if ~isfield(cm_sys, 'candidates') || isempty(cm_sys.candidates)
          out.(case_name).(seed_name).(sys_name).note = 'No compatible components found';
          continue;
        end

        n_out = min(n_candidates_out, numel(cm_sys.candidates));
        for k = 1:n_out
          cand_name = strcat('candidate_', num2str(k));
          c = cm_sys.candidates(k);
          cand_fields = fieldnames(c);
          for f = 1:numel(cand_fields)
            out.(case_name).(seed_name).(sys_name).(cand_name).(cand_fields{f}) = c.(cand_fields{f});
          end
        end

      end  % subsystem loop
    end  % seed loop
  end  % case loop

  folderPath   = strcat('Output/', num2str(runID));
  xml_FileName = fullfile(folderPath, 'ESDC_component_matches');
  struct2xml(out, xml_FileName);

end
