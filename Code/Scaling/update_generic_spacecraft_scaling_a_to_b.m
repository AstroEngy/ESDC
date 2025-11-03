function [] = update_generic_spacecraft_scaling_a_to_b (data, orbit_type, field_x, field_y)

  path = "Database/Scaling/";             %new path set to output /Scaling/Model/System
  
  x = [];
  y = [];
  name = {};

  %Data vector creation here
  for i = 1:numel(data)
        if strcmp(data(i).orbit_type, orbit_type) && isfield(data(i), field_x) && isfield(data(i), field_y) && ~isempty(data(i).(field_x)) && ~isempty(data(i).(field_y))
              x = [x data(i).(field_x)];
              y = [y data(i).(field_y)];
              if isfield(data(i), "name")
                name{1, numel(x)} = data(i).name;
              else
                name{1, numel(x)} = {};
              end
        end
  end
  
   filename = strcat(path, "scaling_spacecraft_", orbit_type, "_parameter_", field_x, "_to_", field_y, ".csv");
   if numel(x) > 0 && numel(y) > 0
    write_selected_data_to_file(x, y, filename, 0); % TODO param names here
   end
end

