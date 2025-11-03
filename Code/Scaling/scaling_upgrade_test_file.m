%TODO validate the fit functions in determining correct fit

function scaling_upgrade_test_file()
    % Test file for creating relevant scaling model here, update respective functions from here on out.
    UpdateSpacecraftScaling(1)
end

% Function for handling the spacecraft database file.
function UpdateSpacecraftScaling(forceUpdate)
    % Update spacecraft scaling models based on the XML database file.

    xmlFilePath = '../../Database/ESDC_Reference_Data_Spacecrafts.xml' % _short_test.xml'; % revert this to relative path in prod
    CheckAndUpdateModel(xmlFilePath, @ReadReferenceSpacecraftData, @UpdateGenericSpacecraftScalingModel, forceUpdate);
end



function spacecraftParameters = ReadReferenceSpacecraftData(xmlFilePath)
    % Read the reference spacecraft data from the specified XML file.
    if exist(xmlFilePath, 'file')
        disp('Reading Spacecraft Reference Database');
        spacecraftParameters = xml2struct(xmlFilePath); % Use the provided xmlFilePath
        spacecraftParameters = TypesetStruct(spacecraftParameters);

        %disp(spacecraftParameters); Debugging only
        % Ensure a singular entry parses as a cell array with one entry instead of a struct.
        if isstruct(spacecraftParameters.reference_data_spacecraft)
            structdata = spacecraftParameters.reference_data_spacecraft;
            spacecraftParameters = struct();
            spacecraftParameters.reference_data_spacecraft{1} = structdata;
        end

        disp('Success');
        disp(' ');
        fflush(stdout);
    else
        error('ERROR: No spacecraft reference data found');
    end
    spacecraftParameters=spacecraftParameters.reference_data_spacecraft{1}.spacecraft; %Lift data to the correct layer
end

function CheckAndUpdateModel(xmlFilePath, readDataFunc, updateModelFunc, forceUpdate)
    % Helper function handling the check for updates and respective updating of the underlying models.
    makeUpdate = false;
    if exist(xmlFilePath, 'file')
        persistent lastTimestamp;
        xmlInfo = dir(xmlFilePath);
        currentTimestamp = xmlInfo.datenum;

        if isempty(lastTimestamp) || currentTimestamp ~= lastTimestamp
            if isempty(lastTimestamp)
                disp(['First run, updating ', xmlFilePath]);
            else
                disp(['Updates to ', xmlFilePath, ' detected.']);
            end
            lastTimestamp = currentTimestamp;
            makeUpdate = true;
        else
            disp(['No updates to ', xmlFilePath, ' detected.']);
        end
    else
        error(['File not found: ', xmlFilePath]);
    end

    if forceUpdate || makeUpdate
        if forceUpdate
            disp(['Forcing update for ', xmlFilePath]);
        end
        data = feval(readDataFunc, xmlFilePath); 
        feval(updateModelFunc, data);
        disp(['Updates to ', xmlFilePath, ' complete.']);
    end
end

function UpdateGenericSpacecraftScalingModel(spacecraftData)
    % Update the scaling model using the spacecraft data.
    exclusionList   = {'name', 'launch_year', 'source', 'orbit_type', 'TRL', 'name_long', 'comment'}; % the fields where correlation is meaningless
    toCorrelate     = {'mass_total', 'mass_payload', 'power_total', 'power_payload'};                   % the main x fields to correlate

    disp('Updating spacecraft scaling models.');

    % Determine distinct orbit types and all fields
    distinctOrbitCases  = GetDistinctOrbitCases(spacecraftData);
    allFields           = GetAllFields(spacecraftData);

    % Perform correlations
    % add output here after correlations
    %disp('Starting Correlations')
    PerformCorrelations(spacecraftData, distinctOrbitCases, toCorrelate, allFields, exclusionList);

    % analysis of fitting model and renormalize it.

    % TODO: store model in structure --> Define structure (raw data, fit function direct, rescaling for unity fit, parameters, units, comment)
    % store model in scaling for back retrieval and avoiding recalc
    % store case specific model in output folder as documentation of run
    % ability to add year or TRL limits useful here
end

function allFields = GetAllFields(data)
    % Determine number of potentially correlatable fields
    allFields = {};
    for i = 1:numel(data)
        caseFields  = fieldnames(data{i});
        allFields   = [allFields; caseFields];
    end
    allFields = unique(allFields);
    %disp('All field check')
    %disp(allFields)
    %disp('This was all fields')
            %currently this results only in "spacecraft " --Y> wrong abstraction layer
end

function distinctOrbitCases = GetDistinctOrbitCases(data)
    % Determine distinct orbit types
    %disp('Starting Orbit distinction')
    orbitTypes = {};
    spacecraftArray = data;
    %disp(spacecraftArray)
    for j = 1:numel(spacecraftArray)
        spacecraftData = spacecraftArray(j); % Correct indexing for scalar structure
        if isfield(spacecraftData{1}, 'orbit_type')
            orbitTypes{end+1} = spacecraftData{1}.orbit_type;
        end
    end
    %disp(orbitTypes)
    distinctOrbitCases = unique(orbitTypes);
    %disp('orbits done')
end

function PerformCorrelations(data, orbitCases, toCorrelate, allFields, exclusionList)
    % Perform correlations between available fields of spacecraft database
    % Disp(allFields)

        % validationMode = false % default
    for i = 1:numel(orbitCases)
        for j = 1:numel(toCorrelate)
            if ismember(toCorrelate{j}, allFields)
                for k = 1:numel(allFields)
                        # disp(k)
                        # disp(exclusionList)
                        # disp(char(orbitCases{i}))
                        # disp(char(toCorrelate{j}))
                        % disp(char(allFields))
                        # disp(allFields{k})        
                        #disp(exclusionList)
                        # exit
                    if ~ismember(allFields{k}, exclusionList) % skip model derivation if field is part of exclusion list
                        %add backflow of data here as output
                        %disp('Specific correlation')
                        model = UpdateGenericSpacecraftScalingAtoB(data, char(orbitCases{i}), char(toCorrelate{j}), char(allFields{k}));
                    else
                        %disp('triggered jump')
                        %allFields{k}
                        %exit
                    end
                end
            else
                disp(['Correlation for ',toCorrelate{j},' not possible. No data in database.'])
            end
        end
    end

end

function modelParameters = UpdateGenericSpacecraftScalingAtoB(data, orbitType, fieldX, fieldY)
    % Update scaling model from fieldX to fieldY for a specific orbit type.
    path = "Database/Scaling/";  % should also be written to output in the end.
    %disp('Inside UpdateGenericSpacecraftScalingAtoB')
    %disp(fieldX)
    %disp(fieldY)
    x = [];
    y = [];
    name = {};
    nameLong = {};

    %disp("Attempting to collect this data for correlation")
    for i = 1:numel(data)                                           % Loop over all spacecraft data in cell array of i length
            spacecraftStruct = data{i};                             % Access the data of spacecraft i
            if isfield(spacecraftStruct, 'orbit_type') && strcmp(spacecraftStruct.orbit_type, orbitType) && ... % Check if data is correct orbit type
                    isfield(spacecraftStruct, (fieldX)) && isfield(spacecraftStruct, (fieldY)) && ...           % Check if data contains field x and field y
                    ~isempty(spacecraftStruct.(fieldX)) && ~isempty(spacecraftStruct.(fieldY))                  % Check if data field is not empty
                x = [x, spacecraftStruct.(fieldX)];                                                              % Append x-array
                y = [y, spacecraftStruct.(fieldY)];                                                              % Append y_array
                if isfield(spacecraftStruct, 'name')                                                            % Check existance
                    name{numel(x)} = spacecraftStruct.name;                                                     % Appenx name cell array
                else
                    name{numel(x)} = {'No name given'};
                end
                if isfield(spacecraftStruct, 'name_long')                                                       % Check existance
                    nameLong{numel(x)} = spacecraftStruct.name_long;                                            % Appenx long name cell array
                else
                    nameLong{numel(x)} = {'No long name given'};
                end
            end
    end
    % Sort according to x the fields y, name, and nameLong

    if ~(isempty(x) || isempty(y))
        sorted_data = struct; % can be considered unnecessarsy
 
        [sorted_data.x, sorted_data.y, sorted_data.name, sorted_data.nameLong] = sortDataToX(x, y, name, nameLong);

    validationMode = true;

        if validationMode == true
            [sorted_data validationData] = getValidationData();

            [modelParameters] = deriveScalingModel(sorted_data.x, sorted_data.y);

            modelParameters.validationMode   = true;
            modelParameters.correlatedFieldX = 'Example data X';
            modelParameters.correlatedFieldY = 'Example data Y';
            modelParameters.orbitType        = 'example';
            modelParameters.unitX            = '-';
            modelParameters.unitY            = '-';
            modelParameters.validationData   = validationData;


        else                                            % normal mode for deriving system correlations
            % Derive correlation for this set
            [modelParameters] = deriveScalingModel(sorted_data.x, sorted_data.y);
            
            modelParameters.correlatedFieldX = fieldX;
            modelParameters.correlatedFieldY = fieldY;
            modelParameters.orbitType        = orbitType;
            modelParameters.unitX            = getUnitString(fieldX);
            modelParameters.unitY            = getUnitString(fieldY);

            % Singular data -> duplication case handling
            if numel(sorted_data.x) == 1 
                modelParameters.data.name        = {name, name};
                modelParameters.data.nameLong    = {nameLong, nameLong};
            else
                modelParameters.data.name        = sorted_data.name;
                modelParameters.data.nameLong    = sorted_data.nameLong;
            end

            modelParameters.data.minX = sorted_data.x(1);
            modelParameters.data.maxX = sorted_data.x(end);  

            modelParameters.data.minY = sorted_data.y(1);
            modelParameters.data.maxY = sorted_data.y(end);  
        end

            modelParameters.graph.baseModelGraph = makeModelGraph(modelParameters);
            filename = [modelParameters.graph.baseModelGraph.outputpath,'model_data',modelParameters.graph.baseModelGraph.graphname(1:end-4),'.mat'];
            save(filename,'modelParameters');

    else
        modelParameters.error = ['Error: No data for modelling ',fieldX , ' and ' , fieldY ,  '.'];
    end



    % Add further processing or saving logic here if needed
    % For example, saving the correlations to a file can be added here.
    % filename = strcat(path, "scaling_spacecraft_", orbitType, "_parameter_", fieldX, "_to_", fieldY, ".csv");
    % if numel(x) > 0 && numel(y) > 0
    %     write_selected_data_to_file(x, y, filename, 0); % TODO param names here
    % end

    %%Debug
    # disp("sorted")
    # disp(x)
    # disp(y)
    # disp(name)
    # disp(nameLong)
end

function [sorted_data_array, validationData_array] = getValidationData(numCases)
    % Generates numCases random validation/test data sets.
    fitTypeArray = {'polynomial', 'squareroot', 'exponential', 'logarithmic', ...
                    'polynomial', 'polynomial', 'polynomial'};
    polynomialFitDegreeArray = [1, 1, 1, 1, 2, 3, 4];
    numberCoefficientsArray = [2, 2, 2, 2, 3, 4, 5];

    sorted_data_array = cell(1, numCases);
    validationData_array = cell(1, numCases);

    for idx = 1:numCases
        ValidationCase = randi(7); % Randomly select one of the 7 cases

        % Generate random coefficients for the current model
        p   = (rand(1, numberCoefficientsArray(ValidationCase)) - 0.5) * 20; % Range: -10 to +10
        x = linspace(0, 100, 100);

        switch ValidationCase
            case 1  % Linear
                a = p(2); b = p(1);
                yIdeal = a + b * x;
                fitTypeTex = 'a + b x';
                coefficientsText = sprintf('a = %.2e, b = %.2e', a, b);
            case 2  % Square Root
                a = p(1); b = p(2);
                yIdeal = a * sqrt(x) + b;
                fitTypeTex = 'a \\surd{x} + b';
                coefficientsText = sprintf('a = %.2e, b = %.2e', a, b);
            case 3  % Exponential
                a = p(2); b = p(1);
                yIdeal = a * exp(b * x);
                fitTypeTex = 'a e^{b x}';
                coefficientsText = sprintf('a = %.2e, b = %.2e', a, b);
            case 4  % Logarithmic
                a = p(1); b = p(2);
                yIdeal = a * log(x) + b;
                fitTypeTex = 'a ln(x) + b';
                coefficientsText = sprintf('a = %.2e, b = %.2e', a, b);
            case 5  % Quadratic
                a = p(3); b = p(2); c = p(1);
                yIdeal = a + b * x + c * x.^2;
                fitTypeTex = 'a + b x + c x^2';
                coefficientsText = sprintf('a = %.2e, b = %.2e, c = %.2e', a, b, c);
            case 6  % Cubic
                a = p(4); b = p(3); c = p(2); d = p(1);
                yIdeal = a + b * x + c * x.^2 + d * x.^3;
                fitTypeTex = 'a + b x + c x^2 + d x^3';
                coefficientsText = sprintf('a = %.2e, b = %.2e, c = %.2e, d = %.2e', a, b, c, d);
            case 7  % Quartic
                a = p(5); b = p(4); c = p(3); d = p(2); e = p(1);
                yIdeal = a + b * x + c * x.^2 + d * x.^3 + e * x.^4;
                fitTypeTex = 'a + b x + c x^2 + d x^3 + e x^4';
                coefficientsText = sprintf('a = %.2e, b = %.2e, c = %.2e, d = %.2e, e = %.2e', a, b, c, d, e);
        end

        noiseLevel = 100;
        y = yIdeal + noiseLevel * randn(size(yIdeal));

        sorted_data = struct();
        sorted_data.x = x;
        sorted_data.y = y;
        sorted_data.yIdeal = yIdeal;

        validationData = struct();
        validationData.fitType = fitTypeArray{ValidationCase};
        validationData.fitTypeTex = fitTypeTex;
        validationData.coefficientsText = coefficientsText;
        validationData.coefficients = p;
        validationData.dataX = x;
        validationData.dataY = yIdeal;
        validationData.degree = polynomialFitDegreeArray(ValidationCase);

        sorted_data_array{idx} = sorted_data;
        validationData_array{idx} = validationData;
    end
end
%model graph

function [graphdata] = makeModelGraph(modelParameters)

%TODO: Validation mode improvements
% put correct legend entry for the original function into legend , function + coefficients
% create an additional filename, increment the filename property
% collect output to see where validation function was correctly fitted

    h = figure('Visible', 'off');
    hold on;
    plot(modelParameters.data.x,modelParameters.data.y,'bx','MarkerSize', 3);


    xNameTex = ReplaceTerms(TransformVariableName(modelParameters.correlatedFieldX));          %Transform the field name to be LaTeX parseable
    yNameTex = ReplaceTerms(TransformVariableName(modelParameters.correlatedFieldY));

    xlabel([xNameTex,' / ', modelParameters.unitX]);
    ylabel([yNameTex,' / ', modelParameters.unitY]);
    title(['Correlation of ',xNameTex,' to ',yNameTex, ' for ',modelParameters.orbitType,' orbit type']);
    %modelParameters.data

    xFit = modelParameters.data.xFit;
    yFit = modelParameters.data.yFit; 
    % Plot the polynomial fit
    plot(xFit, yFit, 'r--', 'LineWidth', 1);

    if isfield(modelParameters,'validationData')
        plot(modelParameters.validationData.dataX, modelParameters.validationData.dataY, 'k..', 'DisplayName', 'cos(x)')
        legend('show');
    end

    if ~isempty(strfind(modelParameters.correlatedFieldY,'fraction')) % in case of relation to fraction, always show [0,1]
        ylim([0,1]);
    else
        upperY = modelParameters.data.y(end)*1.1;
        if upperY > 0
            ylim([0, upperY]);
        else
            ylim('auto'); % fallback to automatic limits
        end
    end 

    xlim([0,modelParameters.data.x(end)*1.1]);


    
    fittypeText = [modelParameters.fitType,' ', modelParameters.fittypeText];   

  %  hLegend = legend('data',['fit ',fittypeText,sprintf('\n'),modelParameters.fitCoefficientsText;]);            % add bla bla to fit 

    % Get the position of the legend
    %legendPosition = get(hLegend, 'Position');

% TODO: add addtiional plotting for validation cases here

    % Label each data point with smaller font size
    labelFontSize = 6;  % Adjust this value to make labels smaller or larger

    % Label each data point with a smaller font size using a for loop
    if isfield(modelParameters.data,'name')
        for i = 1:length(modelParameters.data.x)
            text(modelParameters.data.x(i), modelParameters.data.y(i), ...
                ReplaceTerms(modelParameters.data.name{i}), ...
                'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right', ...
                'FontSize', labelFontSize);
        end
    end

    graphpath = 0;
    %disp(pwd)      %displays the current working directory
    outputpath = ['/home/op/Documents/IRS_Owncloud/Projekte/IRAS/DCEP/git_ESDC/Output/ESDCmodel/Systemmodel_validation/',modelParameters.orbitType,'/']; % TODO: adapt here correctly in late version
    % Create the directory if it does not exist
    if ~exist(outputpath, 'dir')
        mkdir(outputpath);
    end

    % adapt here for file incrementing 

    filename = ['Correlation_',modelParameters.correlatedFieldX,'-and_',modelParameters.correlatedFieldY,' for orbit ',modelParameters.orbitType,'.png'];
    outputHere = [outputpath, filename];
    saveas(h, outputHere);  % Save the figure with the constructed file path
    %title orbitType, x,y 
    % legend including fit function

    graphdata.handle = h;
    graphdata.outputpath = outputpath;
    graphdata.graphname = filename;
end



function transformedName = TransformVariableName(variableName)
    % TransformVariableNameNested: Convert a variable name from the format
    % name_subindex_subindex2 to name_{subindex_{subindex2}} for nested subscripts.
    %
    % transformedName = TransformVariableNameNested(variableName) returns the
    % transformed variable name string suitable for LaTeX parsing with nested subscripts.

    % Split the name at underscores
    parts = strsplit(variableName, '_');
    
    % Start with the base name
    baseName = parts{1};

    % Recursively create nested subscripts
    if length(parts) > 1
        nestedSubscripts = parts{2};
        for i = 3:length(parts)
            nestedSubscripts = [nestedSubscripts, '_{', parts{i}, '}'];
        end
        transformedName = [baseName, '_{', nestedSubscripts, '}'];
    else
        transformedName = variableName; % No underscores, no transformation needed
    end
end

function outputString = ReplaceTerms(inputString)
    % ReplaceTerms: Replace specific terms in a string with desired substitutions.
    %
    % outputString = ReplaceTerms(inputString) returns the inputString with
    % specified terms replaced by their corresponding symbols.
    
    % Define the replacements as cell arrays add here additonal replacements
    terms = {'mass', 'power', 'fraction'};
    replacements = {'m', 'P', '\lambda'};
    
    % Perform the replacements
    outputString = inputString;
    for i = 1:length(terms)
        outputString = strrep(outputString, terms{i}, replacements{i});
    end
end

function unit = getUnitString(inputField)
    % input should be a field
    % Define lists of variable names associated with each unit

    %Masses 
    massArray = {
        'mass_total';
        'mass_total_dry';
        'mass_margin';
        'mass_dry_margin';
        'mass_dry';
        'mass_ADC';
        'mass_OBC';
        'mass_TTC';
        'mass_other';
        'mass_payload';
        'mass_power';
        'mass_propulsion';
        'mass_structmech';
        'mass_thermal';
    };

    %Electrical power - later also thermal/RF power
    powerArray = {        
        'power_total';
        'power_ADC';
        'power_OBC';
        'power_TTC';
        'power_payload';
        'power_power';
        'power_structmech';
        'power_thermal';
        'propulsion_power'};

    % Anything without unit
    dimensionlessArray = {
        'TRL';
        'fraction_mass_ADC';
        'fraction_mass_OBC';
        'fraction_mass_TTC';
        'fraction_mass_other';
        'fraction_mass_payload';
        'fraction_mass_power';
        'fraction_mass_propulsion';
        'fraction_mass_structmech';
        'fraction_mass_thermal';
        'fraction_power_ADC';
        'fraction_power_OBC';
        'fraction_power_TTC';
        'fraction_power_payload';
        'fraction_power_power';
        'fraction_power_structmech';
        'fraction_power_thermal';
        'fraction_propulsion_power'
    };

    % Anything with unit of length
    lengthArray = {
        'size_h';
        'size_x';
        'size_y'
    };

    % Check which list the input field belongs to and assign the unit
    if any(strcmp(inputField, massArray))
        unit = 'kg';  % Mass is typically measured in kilograms
    elseif any(strcmp(inputField, powerArray))
        unit = 'W';   % Power is typically measured in watts
    elseif any(strcmp(inputField, dimensionlessArray))
        unit = '-';    % Dimensionless quantities have no units marked with a -
    elseif any(strcmp(inputField, lengthArray))
        unit = 'm';   % Length is typically measured in meters
    else
        warning(['Unit for ', inputField ,' unknown. Add definition to function  getUnitString(inputField)'])
        unit = 'undef';
    end
end


function [x, y, name, nameLong] = sortDataToX(x, y, name, nameLong)
    %disp('Sorting start')
    % Sort the data according to x
    [x, sortIdx] = sort(x);
    y = y(sortIdx);

    % Sort name if provided
    if nargin > 2 && ~isempty(name)
        name = name(sortIdx);
    end

    % Sort nameLong if provided
    if nargin > 3 && ~isempty(nameLong)
        nameLong = nameLong(sortIdx);
    end
end

function [fitModel] = deriveScalingModel(dataX, dataY, fitType) % what if fitType is poly but no degree is given...determine degree
warning('off', 'Octave:singular-matrix');
      if nargin < 3
           [fitType polynomialFitDegree] =  determineFitType(dataX,dataY);                 % is computational expensive as fittings are already done in here to make a decision
      end
      %fitType
            %disp('inside derive scaling')
            %polynomialFitDegree
            if strcmp(fitType,'polynomial')             % f(x) = sum(p_i*x^i)
                if ~exist('polynomialFitDegree', 'var')                                    % only needed if explicit polynomial fitting is desired without previously knowing the degree
                    polynomialFitDegree = determinePolynomialDegreeToFit(dataX,dataY);
                end
                if numel(dataX)==1                                                          % in case of single data point, duplicate the data point to achieve horizontal linear fit
                    dataX = [dataX dataX];
                    dataY = [dataY dataY];
                end
                [p s] = polyfit(dataX,dataY,polynomialFitDegree);
                xFit = linspace(min(dataX),max(dataX), 100);
                yFit = polyval(p, xFit); %todo add here cases for exp, ln, sqrt functions
                if polynomialFitDegree==1
                    a = p(2);
                    b = p(1); 
                    fitTypeTex = ['a + b x '];
                    coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b)]; 
                elseif polynomialFitDegree==2
                    a = p(3);
                    b = p(2);
                    c = p(1); 
                    fitTypeTex = ['a + b x  + c x^2'];
                    coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b),', c = ',sprintf('%.2e', c)]; 
                elseif polynomialFitDegree==3
                    a = p(4);
                    b = p(3);
                    c = p(2);
                    d = p(1);
                    fitTypeTex = ['a + b x  + c x^2 + d x^3'];
                    coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b),', c = ',sprintf('%.2e', c),sprintf(',\n'),' d = ',sprintf('%.2e', d)]; 
                elseif polynomialFitDegree==4
                    a = p(5);
                    b = p(4);
                    c = p(3);
                    d = p(2);
                    e = p(1);
                    fitTypeTex = ['a + b x  + c x^2 + d x^3+ e x^4'];
                    coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b),', c = ',sprintf('%.2e', c),sprintf(',\n'),' d = ',sprintf('%.2e', d),', e = ',sprintf('%.2e', e)]; 
                end
            end

            if strcmp(fitType,'exponential')            % f(x) = a*e^(b*x)
                yTransformed = log(dataY);              % Transform y-values: ln(y) = ln(a) + b*x
                [p, s] = polyfit(dataX, yTransformed, 1); % Fit line to transformed data
                a = exp(p(2));                         % Intercept transformed back to a
                b = p(1);                               % Slope is b
                xFit = linspace(min(dataX), max(dataX), 100); % Generate x-values for the fit
                yFit = a * exp(b * xFit);               % Compute corresponding y-values
                fitTypeTex = ['a e^{b x}'];
                if any(isnan(p))                        %should never trigger due to previous handling in determineFitType
                    warning(['Exponential fit attempt contains NaN.']);
                end
                %input('Press Enter to continue: ', 's');
                % does this need a case for isNaN?
                coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b)]; 
            end

            if strcmp(fitType,'logarithmic')               % f(x) = a*ln(x) + b
                xTransformed = log(dataX);                 % Transform x-values: ln(x)
                [p, s] = polyfit(xTransformed, dataY, 1);  % Fit line to transformed data
                a = p(1);                                  % Slope (a)
                b = p(2);                                  % Intercept (b)
                xFit = linspace(min(dataX), max(dataX), 100); % Generate x-values for the fit
                yFit = a * log(xFit) + b;                  % Compute corresponding y-values
                fitTypeTex = ['a ln(x) + b'];
                coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b)]; 
            end

            if strcmp(fitType,'squareroot')             % f(x) = a \sqrt(x)+b
                xTransformed=sqrt(dataX);                       % transform x to sqrt x to apply polyfit
                [p s] = polyfit(xTransformed, dataY,1);        % p(1) = b, p(2)= a
                a = p(1);                                  % Slope (a)
                b = p(2);                                  % Intercept (b)
                xFit = linspace(min(dataX),max(dataX), 100);
                yFit = a*sqrt(xFit)+b;
                fitTypeTex = ['a \surd{x} + b'];
                % Format the coefficients in scientific notation and create the explanation text
                coefficientsText = ['a = ',sprintf('%.2e', a),', b = ',sprintf('%.2e', b)]; 
            end
      %end

    fitModel.fitType            = fitType;              % Polynomial, Squareoot, Exponential, Logarithmic
    fitModel.fittypeText        = fitTypeTex;           % the abstract text to be displayed on the graph , e.g. f(x)= A e^(b x)
    fitModel.fitDegree          = polynomialFitDegree; % 1,2,3,4
    fitModel.data.x             = dataX;                % Original x data
    fitModel.data.y             = dataY;                % Original y data
    fitModel.fitCoefficients    = p;                    % Coefficients a b c in reverse order
    fitModel.fitCoefficientsText= coefficientsText;     % The corresponding text explaining the factors a to e in scientific notation
    fitModel.fitAdditonalInfo   = s;                    % additional polyfit output like residuals norms, vandenmode matrix etc. https://octave.sourceforge.io/octave/function/polyfit.html
    fitModel.data.xFit          = xFit;                 % explicit x-values of the resulting fitfunction
    fitModel.data.yFit          = yFit;                 % explicit y-values of the resulting fitfunction
    %fitModel

    %add fitting data here , make this fully external
    %xFit = linspace(modelParameters.data.minX,modelParameters.data.maxX, 100);
    %yFit = polyval(modelParameters.fitCoefficients, xFit) %todo add here cases for exp, ln, sqrt functions
    warning('on', 'Octave:singular-matrix');
end

function [fitType, polynomialFitDegree] = determineFitType(dataX, dataY)
    warning('off', 'Octave:singular-matrix');
    % function formerly named data_fitting
    % based on method from own paper: https://link.springer.com/article/10.1007/s12567-021-00383-3
    % new and improved to avoid overfitting 

    # % Initialize output variables
    # fitType = 'polynomial';  % Default fit type
    # polynomialFitDegree = 1;  % Default polynomial degree

    threshold = 0.90;  % max 1-> perfect fit %TODO extract to Simulation parameter , used for avoiding overfitting by considering reduced polynomial degree to most simplest and not necessarily "best fitting"
                    % THINK why lower threshold allows for exponentional prefererd

        % Pearson correlation shortcut
    if numel(dataX) > 1 && numel(dataY) > 1
        r = corr(dataX(:), dataY(:)); % Pearson correlation     % https://www.statisticshowto.com/probability-and-statistics/correlation-coefficient-formula/
        if abs(r) > 0.97                % Pearson correlation threshold
            fitType = 'polynomial';
            polynomialFitDegree = 1;
            warning('on', 'Octave:singular-matrix');
            return;
        end
    end

    % Ranking of fit tests from preferred to unpreferred
        % poly 1 - linear
        % poly 2 - quadratic
        % sqrt   - square root, inverse to quadratic
        % exponential - an extrem poly 2
        % logarithmic - an extreme sqrt
        % poly 3 - cubic
        % poly 4 - quartic 
            % if all bad use linear 
            
        % Define the array of fit types
        fitTypeArray = {'polynomial', 'squareroot', 'exponential', 'logarithmic', ...
                        'polynomial', 'polynomial', 'polynomial'};

        % Define the corresponding polynomial fit degrees
        polynomialFitDegreeArray = [1, 1, 1, 1, 2, 3, 4];

        maxPolynomialDegree = numel(dataX)-1;
        if maxPolynomialDegree > 4
            maxPolynomialDegree = 4;
        end 

        if maxPolynomialDegree == 0               % in case of single data point, duplicate the data point to achieve horizontal linear fit
            dataX = [dataX dataX];
            dataY = [dataY dataY];
            [p s] =   polyfit(dataX,dataY,1); 
            fitType = 'polynomial';
            polynomialFitDegree = 1; 
            return
        end

        %get normed residuals for all approaches

        % poly 1 - linear
        [p s] =   polyfit(dataX,dataY,1); 
        normR(1) = s.normr;

        % sqrt   - square root, inverse to quadratic    
        xTransformedSqrt=sqrt(dataX);                        % transform x to sqrt x to apply polyfit
        [p s] = polyfit(xTransformedSqrt, dataY,1);          % p(1) = b, p(2)= a
        normR(2) = s.normr;

        % exponential - an extrem poly 2
        yTransformedExp=log(dataY);                          % transform function to ln(y) = ln(a)+b x to apply polyfit
        [p s] = polyfit(dataX,yTransformedExp,1);            % p(1) = b, p(2)= ln(a)
        normR(3) = s.normr;

        % logarithmic - an extreme sqrt
        xTransformedLog=log(dataX);                        % transform x to log(x) to apply polyfit
        [p s ] = polyfit(xTransformedLog, dataY,1);        % p(1) = b, p(2)= ln(a)
        normR(4) = s.normr;

        % poly 2 - quadratic
        % poly 3 - cubic
        % poly 4 - quartic 
        for i=2:maxPolynomialDegree
            [p s] =   polyfit(dataX,dataY,i); 
            normR(i+3) = s.normr;
        end


        %normR
        %Normed residual comparison logic here
        normR = normR+1e-16; % add small number to total normR, is a  hack to avoid division by zero in case of perfect fit

        % fit current mathematical best fit
        [normRFitCandidate indexFitCandidate] = min(normR);

        % move the index to the lowest possible position that is still a fit of similar quality according to threshold
        i = indexFitCandidate;
        while 1
            if i==1                         % if all else fails go linear
                fitTypeIndex = 1;
                break;
            end

            if isnan(normR(i))              % if the fit of the current interpolation is NaN skip it.
                i = i-1;
                continue;
            end

            currentTestNormR = normR(i)./normR;                                             % get individual relative normed residuals 
            withinThreshold = find(currentTestNormR > threshold & currentTestNormR < 1);    % test if lower approximation within threshold, currentTestNormR < 1 excludes the self reference to the tested element.
                                                                                            % function docu: https://octave.sourceforge.io/octave/function/find.html
            signOkay = true;
            if (strcmp(fitTypeArray{i},'polynomial') && i >= 2)                             % Additional check whether coefficients have changing signs, indicating possible overfitting
                [p, s] = polyfit(dataX, dataY, polynomialFitDegreeArray(i));                % The current fit in question
                p = p(p ~= 0);                                                              % Exclude zero coefficients from consideration
                signsFound = unique(sign(p));                                               % Find unique signs contained in the coefficients p
                
                if length(signsFound) > 1                                                   % Check if more than one unique sign is found
                    signOkay = false;                                                       % Indicates potential overfitting due to sign changes
                else
                    signOkay = true;                                                        % No sign changes, fit is considered okay
                end
            end
            
            if  withinThreshold && signOkay                                                  % when withinThreshold can not be defined there is not a better fit, and if sign change of polynomial is not triggered
                fitTypeIndex = i;
                break;                                                                      % Exit the loop once a suitable fit is found
            end
            
            i = i-1;                        % decrement i , ascents the list of fit tests
        end

        fitType = fitTypeArray{fitTypeIndex};
        polynomialFitDegree = polynomialFitDegreeArray(fitTypeIndex);
        warning('on', 'Octave:singular-matrix');
end

function [polynomialFitDegree] = determinePolynomialDegreeToFit(dataX,dataY)
    %similar to determineFitTypeFunction
        %disp('determine poly fit deg')
        maxPolynomialDegree = numel(dataX)-1;
        if maxPolynomialDegree > 4
            maxPolynomialDegree = 4;
        end 

        if maxPolynomialDegree == 0               % in case of single data point, duplicate the data point to achieve horizontal linear fit
            dataX = [dataX dataX];
            dataY = [dataY dataY];
            [p s] =   polyfit(dataX,dataY,1); 
            fitType = 'polynomial'
            polynomialFitDegree = 1; 
            return
        end

       for i=1:maxPolynomialDegree
            [p s] =   polyfit(dataX,dataY,i); 
            normR(i) = s.normr;
        end

        %Normed residual comparison logic here
        normR = normR+1e-18; % add small number to total normR, is a  hack to avoid division by zero in case of perfect fit

        % fit current mathematical best fit
        [normRFitCandidate indexFitCandidate] = min(normR); 

                % move the index to the lowest possible position that is still a fit of similar quality according to threshold
                threshold %undefined here
        i = indexFitCandidate;
        while 1
            currentTestNormR = normR(i)./normR;                                             % get individual relative normed residuals 
            withinThreshold = find(currentTestNormR > threshold & currentTestNormR < 1);    % test if lower approximation within threshold, currentTestNormR < 1 excludes the self reference to the tested element.
                                                                                            % function docu: https://octave.sourceforge.io/octave/function/find.html
           signOkay = true;
            if (strcmp(fitTypeArray{i},'polynomial') && i >= 2)                             % Additional check whether coefficients have changing signs, indicating possible overfitting
                [p, s] = polyfit(dataX, dataY, polynomialFitDegreeArray(i));                % The current fit in question
                p = p(p ~= 0);                                                              % Exclude zero coefficients from consideration
                signsFound = unique(sign(p));                                               % Find unique signs contained in the coefficients p
                
                if length(signsFound) > 1                                                   % Check if more than one unique sign is found
                    signOkay = false;                                                       % Indicates potential overfitting due to sign changes
                else
                    signOkay = true;                                                        % No sign changes, fit is considered okay
                end
            end
            
            if  withinThreshold && signOkay                                                  % when withinThreshold can not be defined there is not a better fit, and if sign change of polynomial is not triggered
                fitTypeIndex = i;
                break;                                                                      % Exit the loop once a suitable fit is found
            end

            i = i-1;                        % decrement i , ascents the list of fit tests

            if i==1                         % if all else fails go linear
                fitTypeIndex = i;
                break;
            end

        end
        polynomialFitDegree = fitTypeIndex;
end

%draft for data
%scalingModel.Spacecraft.(OrbitType).(field_x).(field_y). 
%                                                          orbit_type = type , e.g."LEO"
%                                                          field_name_x = value x , e.g. "totalmass"
%                                                          unit_x = unit x, e.g. "kg" 
%                                                          field__name_y = value y , e.g. 
%                                                          unit_x = unit x, e.g. "W" 
%                                                          raw_x =  [1,2,3] , i.e. db values x
%                                                          raw_y = [7,12,26], i.e. db values y
%                                                          interpolation data
%                                                            p = Return the coefficients of a polynomial p(x) of degree n that minimizes the least-squares-error of the fit to the points [x, y]. 
%                                                            mu.x =   The Vandermonde matrix used to compute the polynomial coefficients.
%                                                            mu.yf =  The values of the polynomial for each value of x. 
%                                                            mu.normr =     The norm of the residuals.
%
%                                                          renormalized interpolation data 

                                                          % beachte fit muss immer positiv>=0 sein % minimal prozent?
                                                          % beachte  gesamtleistung und gesamtmasse ist forderung , renormalisiere entsprechend


%helpers will be removed later
function [ s ] = xml2struct( file )

    %Convert xml file into a MATLAB structure
    % [ s ] = xml2struct( file )
    %
    % A file containing:
    % <XMLname attrib1="Some value">
    %   <Element>Some text</Element>
    %   <DifferentElement attrib2="2">Some more text</Element>
    %   <DifferentElement attrib3="2" attrib4="1">Even more text</DifferentElement>
    % </XMLname>
    %
    % Will produce:
    % s.XMLname.Attributes.attrib1 = "Some value";
    % s.XMLname.Element.Text = "Some text";
    % s.XMLname.DifferentElement{1}.Attributes.attrib2 = "2";
    % s.XMLname.DifferentElement{1}.Text = "Some more text";
    % s.XMLname.DifferentElement{2}.Attributes.attrib3 = "2";
    % s.XMLname.DifferentElement{2}.Attributes.attrib4 = "1";
    % s.XMLname.DifferentElement{2}.Text = "Even more text";
    %
    % Please note that the following characters are substituted
    % '-' by '_dash_', ':' by '_colon_' and '.' by '_dot_'
    %
    % Written by W. Falkena, ASTI, TUDelft, 21-08-2010
    % Attribute parsing speed increased by 40% by A. Wanner, 14-6-2011
    % Added CDATA support by I. Smirnov, 20-3-2012
    %
    % Modified by X. Mo, University of Wisconsin, 12-5-2012

    % Modified by M. Ehresmann, University of Stuttgart, 18-03-2019, to work on Octave with Java xerces 2.12.0.

    if (nargin < 1)
        clc;
        help xml2struct
        return
    end
    
    if isa(file, 'org.apache.xerces.dom.DeferredDocumentImpl') || isa(file, 'org.apache.xerces.dom.DeferredElementImpl')
        % input is a java xml object
        xDoc = file;
    else
        %check for existance
        if (exist(file,'file') == 0)
            %Perhaps the xml extension was omitted from the file name. Add the
            %extension and try again.
            if (isempty(strfind(file,'.xml')))
                file = [file '.xml'];
            end
            
            if (exist(file,'file') == 0)
                error(['The file ' file ' could not be found']);
            end
        end
        %read the xml file
        xDoc = xmlread(file);
    end
    
    %parse xDoc into a MATLAB structure
    s = parseChildNodes(xDoc);
    
end



% ----- Subfunction parseChildNodes -----
function [children,ptext,textflag] = parseChildNodes(theNode)
    % Recurse over node children.
    children = struct;
    ptext = struct; textflag = 'Text';
    if theNode.hasChildNodes()
        childNodes = theNode.getChildNodes();
        numChildNodes = theNode.getLength();

        for count = 1:numChildNodes
            theChild = childNodes.item(count-1);
            [text,name,attr,childs,textflag] = getNodeData(theChild);
            
            if (~strcmp(name,'#text') && ~strcmp(name,'#comment') && ~strcmp(name,'#cdata_dash_section'))
                %XML allows the same elements to be defined multiple times,
                %put each in a different cell
                if (isfield(children,name))
                    if (~iscell(children.(name)))
                        %put existsing element into cell format
                        children.(name) = {children.(name)};
                    end
                    index = length(children.(name))+1;
                    %add new element
                    children.(name){index} = childs;
                    if(~isempty(fieldnames(text)))
                        children.(name){index} = text; 
                    end
                    if(~isempty(attr)) 
                        children.(name){index}.('Attributes') = attr; 
                    end
                else
                    %add previously unknown (new) element to the structure
                    children.(name) = childs;
                    if(~isempty(text) && ~isempty(fieldnames(text)))
                        children.(name) = text; 
                    end
                    if(~isempty(attr)) 
                        children.(name).('Attributes') = attr; 
                    end
                end
            else
                ptextflag = 'Text';
                if (strcmp(name, '#cdata_dash_section'))
                    ptextflag = 'CDATA';
                elseif (strcmp(name, '#comment'))
                    ptextflag = 'Comment';
                end
                
                %this is the text in an element (i.e., the parentNode) 
                if (~isempty(regexprep(text.(textflag),'[\s]*','')))
                    if (~isfield(ptext,ptextflag) || isempty(ptext.(ptextflag)))
                        ptext.(ptextflag) = text.(textflag);
                    else
                        %what to do when element data is as follows:
                        %<element>Text <!--Comment--> More text</element>
                        
                        %put the text in different cells:
                        % if (~iscell(ptext)) ptext = {ptext}; end
                        % ptext{length(ptext)+1} = text;
                        
                        %just append the text
                        ptext.(ptextflag) = [ptext.(ptextflag) text.(textflag)];
                    end
                end
            end
            
        end
    end
end

% ----- Subfunction getNodeData -----
function [text,name,attr,childs,textflag] = getNodeData(theNode)
    % Create structure of node info.
    
    %make sure name is allowed as structure name
    name = char(theNode.getNodeName());
    name = strrep(name, '-', '_dash_');
    name = strrep(name, ':', '_colon_');
    name = strrep(name, '.', '_dot_');

    attr = parseAttributes(theNode);
    if (isempty(fieldnames(attr))) 
        attr = []; 
    end
    
    %parse child nodes
    [childs,text,textflag] = parseChildNodes(theNode);
    
    if (isempty(fieldnames(childs)) && isempty(fieldnames(text)))
        %get the data of any childless nodes
        % faster than if any(strcmp(methods(theNode), 'getData'))
        % no need to try-catch (?)
        % faster than text = char(getData(theNode));
        text.(textflag) = char(theNode.getTextContent());
    end
    
end

% ----- Subfunction parseAttributes -----
function attributes = parseAttributes(theNode)
    % Create attributes structure.

    attributes = struct;
    if theNode.hasAttributes()
       theAttributes = theNode.getAttributes();
       numAttributes = theAttributes.getLength();

       for count = 1:numAttributes
            %attrib = item(theAttributes,count-1);
            %attr_name = regexprep(char(getName(attrib)),'[-:.]','_');
            %attributes.(attr_name) = char(getValue(attrib));
            %Suggestion of Adrian Wanner
            str = char(theAttributes.item(count-1)); %Modified here by M. Ehresmann
            k = strfind(str,'='); 
            attr_name = str(1:(k(1)-1));
            attr_name = strrep(attr_name, '-', '_dash_');
            attr_name = strrep(attr_name, ':', '_colon_');
            attr_name = strrep(attr_name, '.', '_dot_');
            attributes.(attr_name) = str((k(1)+2):(end-1));
       end
    end
end

    %Copyright (c) 2010, Wouter Falkena
    %All rights reserved.

    %Redistribution and use in source and binary forms, with or without
    %modification, are permitted provided that the following conditions are
    %met:
    %
    %    * Redistributions of source code must retain the above copyright
    %      notice, this list of conditions and the following disclaimer.
    %    * Redistributions in binary form must reproduce the above copyright
    %      notice, this list of conditions and the following disclaimer in
    %      the documentation and/or other materials provided with the distribution

    %THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    %AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    %IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
    %ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
    %LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    %CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
    %SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
    %INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
    %CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    %ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    %POSSIBILITY OF SUCH DAMAGE.

function [in_struct] = TypesetStruct(in_struct)
 % Author: M. Ehresmann 2019
 % Check XML2Struct product and convert all "Text" fields to appropriate numbers and strings.
 % Look ahead two field layers. If second layer is text convert and append previous struct.
  if isstruct(in_struct)                  %check if directly struct
    %disp("struct case");
    fields_1 =fieldnames(in_struct);
    
    for i=1: size(fields_1,1)
      if isstruct(in_struct.(fields_1{i}))    %struct upon strFuct allows text
         %disp("struct *2 case");
        fields_2 =fieldnames(in_struct.(fields_1{i}));
        if strcmp(fields_2{1},"Text")
          [num, state] = str2num(in_struct.(fields_1{i}).Text);
          if state == 0
            %disp('string');
            field_value = char(in_struct.(fields_1{i}).Text);
          else
            %disp('scalar');
            field_value = num;
          end
          in_struct.(fields_1{i})  = field_value;     %redefine previous substructure with field "text" to field with generated value
          
         elseif strcmp(fields_2{1},"Attributes") || strcmp(fields_1{i},"Attributes") 
         % disp("here stuff for Attributes")
        else                                 % if struct upon struct is not text decend deeper
          in_struct.(fields_1{i}) = TypesetStruct(in_struct.(fields_1{i})); 
        end
        
      else                                  %if type is cell descent deeper in cell array
        %disp("cell case")
        for j=1:size(in_struct.(fields_1{i}),2)
        fields_2 =fieldnames(in_struct.(fields_1{i}){1,j});
        if (strcmp(fields_2{1},"Text"))
           [num, state] = str2num(in_struct.(fields_1{i}){1,j}.Text);
          if state ==0
            %disp('string');
            field_value = char(in_struct.(fields_1{i}){1,j}.Text);
          else
            %disp('scalar');
            field_value = num;
          end
          in_struct.(fields_1{i}){1,j}  = field_value;     %redefine previous substructure with field "text" to field with generated value
        else
         % if isstruct(in_struct.(fields_1{i}))
          in_struct.(fields_1{i}){1,j}=TypesetStruct(in_struct.(fields_1{i}){1,j});
        end

        end
          
      end
    end  
  end
  

end

% MIT License
% Copyright (c) 2019 Manfred Ehresmann
% 
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
% 
% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
% 
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
