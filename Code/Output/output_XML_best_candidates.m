function output_XML_best_candidates(config, evolution_data,runID)
  %XML file generation of the optimal candidates
  for j=1:size(evolution_data{1},1)
    solution_list = [];

    %disp(evolution_data{end}(1,1).subsystem_masses.m_margin)
    %disp(evolution_data{end}(1,1).subsystem_masses.m_margin.Text)
    %disp(str2num(evolution_data{end}(1,1).subsystem_masses.m_margin.Text))
    %disp(str2num(evolution_data{end}(1,1).subsystem_masses.m_margin.Text))
    for i=1:size(evolution_data{1},2)
    %TODO replace here?  % appended here mass.fractions.total - former EP system mass fraction total
    %      solution_list = [solution_list , evolution_data{end}(j,i).mass_fractions.total];
    % evolution_data{end} is already the best-per-lineage snapshot (set by evolver.m).
    ind_i = evolution_data{end}(j,i);
    score_i = str2num(ind_i.subsystem_masses.m_margin.Text);
    % Exclude individuals with NaN c_e or thrust (invalid propulsion solution).
    % sc_type==1 ('No Propulsion') is exempt — NaN propulsion fields are expected there.
    sc_type_i = 0;
    if isfield(ind_i, 'orbit') && isstruct(ind_i.orbit)
      sc_type_i = determine_sc_type(ind_i.orbit);
    end
    if sc_type_i ~= 1 && (isnan(ind_i.c_e) || isnan(ind_i.thrust))
      score_i = -Inf;  % push to end of ranking; never selected as optimal candidate
    end
    solution_list = [solution_list , score_i];
    end

    [solution_list, idx] = sort(solution_list, 'descend'); % sort index gives the good candidates

    %produce the reduced optimal index list

    %optimal_solution.best_solutions.dcep_info.dcep_show ="false";
    %optimal_solution.best_solutions.dcep_info.dcep_version=20200428;


   if j==1
   %optimal_solution.best_solutions.(strcat('case_',num2str(j))).dcep_info.dcep_show ="false";
   else
   %optimal_solution.best_solutions.(strcat('case_',num2str(j))).dcep_info.dcep_show ="false";
   end

    n_out = config.Simulation_parameters.output.xml.optimal_candidates;
    for k=1:n_out
      % evolution_data{end} is the best-per-lineage snapshot; read directly.
      ind = evolution_data{end}(j,idx(k));

      % Serialize component_matches (struct-array candidates) into a plain
      % nested struct so struct2xml can write it alongside the design fields.
      if isfield(ind, 'component_matches')
        % Add a compact selected_thruster summary from the top propulsion candidate
        if isfield(ind.component_matches, 'propulsion_system') && ...
           isfield(ind.component_matches.propulsion_system, 'thruster_candidates') && ...
           ~isempty(ind.component_matches.propulsion_system.thruster_candidates)
          top = ind.component_matches.propulsion_system.thruster_candidates(1);
          ind.selected_thruster.name         = top.name;
          ind.selected_thruster.company      = top.company;
          ind.selected_thruster.n_thrusters  = top.n_thrusters;
          ind.selected_thruster.source       = top.source;
        end
        % Add compact tank summary (best-fitting tank / cluster)
        if isfield(ind.component_matches, 'propulsion_system') && ...
           isfield(ind.component_matches.propulsion_system, 'tank_candidates') && ...
           ~isempty(ind.component_matches.propulsion_system.tank_candidates)
          top_tank = ind.component_matches.propulsion_system.tank_candidates(1);
          ind.selected_tank.name         = top_tank.name;
          ind.selected_tank.company      = top_tank.company;
          ind.selected_tank.n_tanks      = top_tank.n_tanks;
          ind.selected_tank.mass_cluster = top_tank.mass_cluster;
          ind.selected_tank.source       = top_tank.source;
        end
        % Add compact PPU summary (best-matching PPU, if any)
        if isfield(ind.component_matches, 'propulsion_system') && ...
           isfield(ind.component_matches.propulsion_system, 'ppu_candidates') && ...
           ~isempty(ind.component_matches.propulsion_system.ppu_candidates)
          top_ppu = ind.component_matches.propulsion_system.ppu_candidates(1);
          ind.selected_ppu.name    = top_ppu.name;
          ind.selected_ppu.company = top_ppu.company;
          ind.selected_ppu.mass    = top_ppu.mass;
          ind.selected_ppu.power   = top_ppu.power;
          ind.selected_ppu.source  = top_ppu.source;
        end
        ind.component_matches = serialize_component_matches(ind.component_matches, n_out);
      end

      optimal_solution.best_solutions.(strcat('case_',num2str(j))).(strcat('best_',num2str(k))) = ind;
    end

end

  folderPath = strcat('Output/',num2str(runID));
  xml_FileName = fullfile(folderPath, 'ESDC_best_candidates');
  struct2xml(optimal_solution,xml_FileName);
end


% -------------------------------------------------------------------------
% Serialize component_matches into a plain nested struct for struct2xml.
% The propulsion_system subsystem now has three struct-array sub-fields
% (thruster_candidates, tank_candidates, ppu_candidates) instead of a single
% 'candidates' array.  All other subsystems still use 'candidates'.
function out = serialize_component_matches(cm_raw, n_candidates_out)
  out = struct();
  if ~isstruct(cm_raw) || isempty(cm_raw); return; end

  % Names of struct-array fields that must be serialized element-by-element
  ARRAY_FIELDS = {'candidates', 'thruster_candidates', 'tank_candidates', 'ppu_candidates'};

  subsystems = fieldnames(cm_raw);
  for s = 1:numel(subsystems)
    sys  = subsystems{s};
    cm_s = cm_raw.(sys);

    % Copy all scalar/string design-point fields (skip struct-array lists)
    all_fields = fieldnames(cm_s);
    for f = 1:numel(all_fields)
      fname = all_fields{f};
      if any(strcmp(fname, ARRAY_FIELDS)); continue; end
      out.(sys).(fname) = cm_s.(fname);
    end

    % Serialize each struct-array candidate list
    any_found = false;
    for af = 1:numel(ARRAY_FIELDS)
      aname = ARRAY_FIELDS{af};
      if ~isfield(cm_s, aname) || isempty(cm_s.(aname)); continue; end
      any_found = true;
      arr = cm_s.(aname);
      n = min(n_candidates_out, numel(arr));
      for k = 1:n
        cname   = strcat(aname, '_', num2str(k));
        c       = arr(k);
        cfields = fieldnames(c);
        for ff = 1:numel(cfields)
          out.(sys).(cname).(cfields{ff}) = c.(cfields{ff});
        end
      end
    end

    if ~any_found
      out.(sys).note = 'No compatible components found';
    end
  end
end

##
##  %here attempt to fit new DCEP interface requirements
##
##
##  for all case_
##    for all best_
##      for all sub_
##
##      endfor
##    endfor
##  endfor
##
##  "if attribute" then
##
##  if
##
##
##endif
##
##  function attribute_processing (in_struct)
##
##  %name case
##    if isfield(param_Attributes,'dcep_name')
##      dcep_name = in_struct.Attributes.dcep_name;
##      out_struct.dcep_info.dcep_name = dcep_name;
##    endif
##
##  %description case
##    if isfield(param_Attributes,'dcep_description')
##      dcep_description = in_struct.Attributes.dcep_description;
##      out_struct.dcep_info.dcep_description = dcep_description;
##    endif
##
##  %unit case
##    if isfield(param_Attributes,'dcep_unit')
##      dcep_unit = in_struct.Attributes.dcep_unit;
##      out_struct.dcep_info.dcep_unit = dcep_unit;
##    end
##
##  endfunction
##
##  optimal_solution_DCEP_IO=struct;
##  optimal_solution_DCEP_IO.best_solution=struct;
##
##  % Extract the necessary data
##  dcep_name = xml_data.mass.Attributes.dcep_name;
##  dcep_description = xml_data.mass.Attributes.dcep_description;
##  dcep_unit = xml_data.mass.Attributes.dcep_unit;
##  mass_value = xml_data.mass.Text;
##
##  % Create a new XML struct with the desired structure
##  new_xml_data = struct('mass', struct('dcep_info', struct()));
##  new_xml_data.mass.dcep_info.dcep_name = dcep_name;
##  new_xml_data.mass.dcep_info.dcep_description = dcep_description;
##  new_xml_data.mass.dcep_info.dcep_unit = dcep_unit;
##  new_xml_data.mass.Text = mass_value;
##
##  struct2xml(optimal_solution_DCEP_IO,'Output/ESDC_best_candidates');
##
##
##end
##
##<best_solutions>
##    <case_1>
##        <best_1>
##            <mass>
##                <dcep_info>
##                       <dcep_name>total system mass</dcep_name>
##                       <dcep_description> Input: Total system mass wet including margins</dcep_description>
##                       <dcep_unit>kg</dcep_unit>
##                </dcep_info>
##            <dv>

##
##function output_XML_best_candidates(config, evolution_data)
##  %XML file generation of the optimal candidates
##  for j=1:size(evolution_data{1},1)
##    solution_list = [];
##
##    %disp(evolution_data{end}(1,1).subsystem_masses.m_margin)
##    %disp(evolution_data{end}(1,1).subsystem_masses.m_margin.Text)
##    %disp(str2num(evolution_data{end}(1,1).subsystem_masses.m_margin.Text))
##    %disp(str2num(evolution_data{end}(1,1).subsystem_masses.m_margin.Text))
##    for i=1:size(evolution_data{1},2)
##    %TODO replace here?  % appended here mass.fractions.total - former EP system mass fraction total
##    %      solution_list = [solution_list , evolution_data{end}(j,i).mass_fractions.total];
##    solution_list = [solution_list , str2num(evolution_data{end}(j,i).subsystem_masses.m_margin.Text)];
##    end
##
##    [solution_list, idx] = sort(solution_list, 'descend'); % sort index gives the good candidates
##
##    %produce the reduced optimal index list
##
##    optimal_solution.best_solutions.Attributes.dcep_show ="false";
##    optimal_solution.best_solutions.Attributes.dcep_version=20200428;
##
##
##   if j==1
##   optimal_solution.best_solutions.(strcat('case_',num2str(j))).Attributes.dcep_show ="false";
##   else
##   optimal_solution.best_solutions.(strcat('case_',num2str(j))).Attributes.dcep_show ="false";
##   end
##
##    for k=1:config.Simulation_parameters.output.xml.optimal_candidates
##      optimal_solution.best_solutions.(strcat('case_',num2str(j))).(strcat('best_',num2str(k))) =  evolution_data{end}(j,idx(k));
##
##        if k==1 && j==1
##          optimal_solution.best_solutions.(strcat('case_',num2str(j))).(strcat('best_',num2str(k))).Attributes.dcep_show ="false";
##        else
##          optimal_solution.best_solutions.(strcat('case_',num2str(j))).(strcat('best_',num2str(k))).Attributes.dcep_show ="false";
##        end
##
##    end
##
##  end
##
##  struct2xml(optimal_solution, 'Output/ESDC_best_candidates');
##end
