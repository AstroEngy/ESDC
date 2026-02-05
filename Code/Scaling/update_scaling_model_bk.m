function [scaling_model_struct] = update_scaling_model(force_update_flag)
  disp('Database check:');
  %System scaling
  update_system_scaling(force_update_flag); %generates .csv look-up tables for component data from database
  %[data] = read_reference_data();    
  %update_generic_component_scaling_model(data);  

  %SC data scaling
  update_SC_scaling(force_update_flag); %generates .csv look-up tables for spacecraft data
  % [data] = read_reference_spacecraft_data();     %for debugging
  % update_generic_spacecraft_scaling_model(data);

end

function[] = update_SC_scaling(force_update)

    make_update = 0;
    if exist("Database/ESDC_Reference_Data_Spacecrafts_hash");
    hash_file = fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "r");
    hash_val = fgetl(hash_file);
    fclose(hash_file);
    current_hash = hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml'));
      if (hash_val == current_hash)
      disp('No updates to spacecraft database detected.');
        %return;
      else
      disp('Updates to spacecraft database detected.');
        [data] = read_reference_spacecraft_data();                    % add output here
        hash_file= fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "w");
        fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml')));
        fclose(hash_file);
        update_generic_spacecraft_scaling_model(data);
        disp('Updates to S/C db complete.');
      end
    else
      disp('No spacecraft database hash file found');
      disp('Creating hash file');
      hash_file= fopen('Database/ESDC_Reference_Data_Spacecrafts_hash', "a");
      disp('Write hash');
      fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Spacecrafts.xml')));
      fclose(hash_file);
      make_update = 1;
    end
    
    if (force_update)
      disp('Forcing Spacecraft Database Update');
    end
    if (make_update | force_update)
      [data] = read_reference_spacecraft_data();
      update_generic_spacecraft_scaling_model(data);
    end
end

function [] =  update_generic_spacecraft_scaling_model(data)
  
    exclusion_list =    {'name', 'launch_year', 'source', 'orbit_type','TRL','name_long', 'comment'};  % list of xml field names that are not to be correlated 
    disp('Updating spacecraft scaling models');
    % Correct field name and provide fallback if reader used alternate key
    if isfield(data, 'reference_data_spacecraft')
      scdata = data.reference_data_spacecraft{1,1}.spacecraft;
    elseif isfield(data, 'reference_data_spracecraft')  % fallback for legacy typo
      scdata = data.reference_data_spracecraft{1,1}.spacecraft;
    else
      error('update_generic_spacecraft_scaling_model: missing field ''reference_data_spacecraft'' in input data');
    end

    % Normalize input to a cell array of structs for uniform processing
    if iscell(scdata)
      rawEntries = scdata(:);
    elseif isstruct(scdata)
      % convert struct array to cell array of single-element structs
      rawEntries = num2cell(scdata(:));
    else
      error('update_generic_spacecraft_scaling_model: unexpected spacecraft data type');
    end

    % Collect union of all field names across entries
    allFieldNames = {};
    for i = 1:numel(rawEntries)
      if isempty(rawEntries{i})
        continue;
      end
      fn = fieldnames(rawEntries{i});
      allFieldNames = [allFieldNames; fn];
    end
    allFieldNames = unique(allFieldNames);

   

    % determine different cases of orbit types
    distinct_orbit_cases  = {};
    for i=1:numel(data)
      if isfield(data(i), 'orbit_type')
        distinct_orbit_cases{i}=data(i).orbit_type;
      else
        distinct_orbit_cases{i} = '';
      end
    end
    distinct_orbit_cases = unique(distinct_orbit_cases);

    % determine number of potentially correlatable fields  
    all_fields = {};
    for i=1:numel(data)
      case_fields = fieldnames(data(i));
      all_fields = [all_fields; case_fields];
    end
    all_fields = unique(all_fields);

    to_correlate = {'m_total','m_payload','p_total','p_payload'}; 
    for i=1: numel(distinct_orbit_cases);
      for j=1:numel(to_correlate)                                                                               
       for k=1:numel(all_fields)
         %strcmp(all_fields{1,k},exclusion_list)
         if sum(strcmp(all_fields{1,k},exclusion_list))  % exclusion from numerical correlation
           %just skip
         else
          update_generic_spacecraft_system_scaling_a_to_b(data,char(distinct_orbit_cases{i}),char(to_correlate{1,j}),char(all_fields{1,k}));
         end
       end
      end
    end
  
   disp('Updating Spacecraft system scalings complete');
end



function [] = update_system_scaling(force_update)
  make_update = 0;
  %%DEBUG block:  Always do system scaling
  %data= read_reference_data(); 
  %update_generic_component_scaling_model(data); 
  
  if exist("Database/ESDC_Reference_Data_Systems_hash")
    hash_file = fopen('Database/ESDC_Reference_Data_Systems_hash', "r");
    hash_val = fgetl(hash_file);
    fclose(hash_file);
    current_hash = hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml'));
    if (hash_val == current_hash)
      disp('No updates to database detected.');
      else
      disp('Updates to database detected.');
        [data] = read_reference_data();                    % add output here
        hash_file= fopen('Database/ESDC_Reference_Data_Systems_hash', "w");
        fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml')));
        fclose(hash_file);
        update_generic_component_scaling_model(data);
        disp('Updates complete.');
      end
  else
    disp('No database hash file found');
    disp('Creating hash file');
    hash_file= fopen('Database/ESDC_Reference_Data_Systems_hash', "a");
    disp('Write hash');
    fprintf(hash_file, hash('md5', fileread('Database/ESDC_Reference_Data_Systems.xml')));
    fclose(hash_file);
    make_update= 1;
  end
  if force_update
    disp('Forcing Component Database Update');
  end
  if (make_update | force_update)
    [data] = read_reference_data();
    update_generic_component_scaling_model(data);
  end
end

function [] =  update_generic_component_scaling_model(data)
disp('Starting updating of scaling data');
disp('');
system_type_names=fieldnames(data.reference_data); % System loop - e.g. propulsion, power etc.
%disp(system_type_names)
for k=1:numel(system_type_names)
  
  technology_type_names=fieldnames(data.reference_data.(char(system_type_names(k))));
  for i=1:numel(technology_type_names)                    % Technology loop - e.g. arcjet, GIT etc.

    %for debugging
    %disp(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))))
    %disp(system_type_names(k))
    %disp(technology_type_names(i))
    %disp(data.reference_data.(char(system_type_names(k))))
    component_type_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i)))); %bug here , when updating DB, probably because tech types dont exist?
    for j=1:numel(component_type_names)                   % Component loop - e.g. thruster, ppu, solar cell, etc.
      if not(isstruct(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j))))) % HERE single field will not be considered
        parameter_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j))){1,i});
      else
        parameter_names=fieldnames(data.reference_data.(char(system_type_names(k))).(char(technology_type_names(i))).(char(component_type_names(j))));
      end
      
      if strcmp(parameter_names,"system") 
        break;
      end
        for l=1:numel(parameter_names)                      % Parameter loop - e.g. mass, power, etc 
          if strcmp(char(component_type_names(j)),'thruster')     % Case distinction of scaling parameters of thrusters being propellant dependent
          update_generic_component_scaling_a_to_b(data,char(system_type_names(k)),char(technology_type_names(i)),char(component_type_names(j)),'mass',char(parameter_names(l)), 'propellant');
          else                                                    % Generic correlation of two parameters
          update_generic_component_scaling_a_to_b(data,char(system_type_names(k)),char(technology_type_names(i)),char(component_type_names(j)),'mass',char(parameter_names(l)));
          end
        
        end

    end
  end
  
%update_generic_component_scaling_a_to_b(data,'propulsion_system','arcjet','ppu','mass','power')
end
disp('');
disp('Updating scaling data complete');
disp('');

end