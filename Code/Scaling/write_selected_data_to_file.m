function [] = write_selected_data_to_file(x,y,filename, padbit)   %function to write

    [data] = sort_data_to_x(x,y,padbit);

    if size(data,2)==1                  %linear scaling when only single data point available
      data = [data(:,1), 2.*data(:,1)];
    end
    %disp(data)
    [data_fit] = data_fitting(data); % there was a 2 here earlier, but why?

    %write file

    dlmwrite(filename, data, ",");
    dlmwrite(filename, data_fit, ",",'-append');

    make_makeshift_graph(filename, data, data_fit); % bug here when insufficient data

    %TODO add here name string appending of file
    %append with name strings
    disp(strcat(filename, " updated"));

end


