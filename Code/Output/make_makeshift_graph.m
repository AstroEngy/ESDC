function [] = make_makeshift_graph(filename_old, data, data_fit)
    % Generate and save a scaling law visualization plot
    %
    % Inputs:
    %   filename_old - Original CSV filename (e.g., 'Database/Scaling/scaling_spacecraft_LEO_parameter_mass_to_power.csv')
    %   data         - Nx2 matrix of actual data points [x, y]
    %   data_fit     - Nx2 matrix of fitted curve points [x, y]
    %
    % Output:
    %   Saves PNG file to Output/ directory
    
    % Generate output filename
    filename = strrep(filename_old, '.csv', '.png');
    filename = strrep(filename, 'Database/Scaling/', 'Output/');
    
    % Ensure Output directory exists
    [output_dir, ~, ~] = fileparts(filename);
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
        fprintf('Created output directory: %s\n', output_dir);
    end
    
    % Extract title from filename (remove path and extension)
    title_text = filename_old(8:end-4);
    
    % Only create graphs for spacecraft data (components can be added later)
    if ~isempty(strfind(filename_old, 'spacecraft'))
        % Parse filename to extract metadata
        underscore_positions = strfind(filename_old, '_');
        param_position = strfind(filename_old, 'parameter');
        to_position = strfind(filename_old, '_to_');
        
        % Extract orbit type (between 2nd underscore and "parameter")
        orbit_type = filename_old(underscore_positions(2)+1 : param_position-2);
        
        % Extract x-axis parameter name
        param_x = filename_old(param_position+10 : to_position-1);
        unit_x = get_parameter_unit(param_x);
        
        % Capitalize first letter of x parameter if it's 'p'
        if strcmp(param_x(1), 'p')
            param_x(1) = 'P';
        end
        
        % Extract y-axis parameter name
        param_y = filename_old(to_position+4 : end-4);
        unit_y = get_parameter_unit(param_y);
        
        % Capitalize first letter of y parameter if it's 'p'
        if strcmp(param_y(1), 'p')
            param_y(1) = 'P';
        end
        
        % Format parameter names (replace underscores with spaces)
        param_x = strrep(param_x, '_', ' ');
        param_y = strrep(param_y, '_', ' ');
        
        % Create axis labels with units
        xlabel_text = strcat(param_x, unit_x);
        ylabel_text = strcat(param_y, unit_y);
        
        % Create annotation with orbit type
        annotation_text = strcat('Orbit type: ', orbit_type);
        
        % Clean title for display
        display_title = erase(filename, "Output/");
        
        % Create figure (invisible to avoid popup during batch processing)
        fig_handle = figure('Name', display_title, 'visible', 'off');
        set(0, 'CurrentFigure', fig_handle);
        hold on;
        
        % Add annotation box with orbit type
        annotation('textbox', [0.15, 0.9, 0.3, 0.08], ...
                   'String', annotation_text, ...
                   'FitBoxToText', 'on', ...
                   'EdgeColor', 'white', ...
                   'FontSize', 16);
        
        % Set axis labels
        xlabel(xlabel_text, 'FontSize', 16);
        ylabel(ylabel_text, 'FontSize', 16);
        
        % Plot actual data points (black asterisks)
        plot(data(:,1), data(:,2), '*k', 'MarkerSize', 12);
        
        % Plot fitted curve (black line)
        plot(data_fit(:,1), data_fit(:,2), '-k', 'LineWidth', 2);
        
        % Save figure to PNG file
        saveas(fig_handle, filename, 'png');
        
        hold off;
        close(fig_handle);
    end
end


function unit = get_parameter_unit(parameter_name)
    % Determine the unit for a parameter based on its first letter
    %
    % Input:
    %   parameter_name - String name of the parameter
    %
    % Output:
    %   unit - String representing the unit (e.g., ' / kg', ' / W')
    
    % Take only the first letter for unit determination
    first_letter = parameter_name(1);
    
    switch first_letter
        case 'm'
            unit = ' / kg';  % Mass
        case 'p'
            unit = ' / W';   % Power
        case 'f'
            unit = ' / -';   % Dimensionless (factor)
        case 's'
            unit = ' / m';   % Size/dimension
        otherwise
            unit = '';       % No unit assigned
    end
end