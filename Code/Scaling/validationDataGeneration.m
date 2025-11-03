function [sorted_data_array, validationData_array] = validationDataGeneration(numCases = 10, relNoiseConstant = 0.1)
    % Generates numCases random validation/test data sets.
        % Complexity ordering: list fits in increasing complexity so polynomial
    % degrees 1 & 2 appear before exponential functions, polynomial degree 3 & 4 most complex.
    fitTypeArray = {'polynomial', 'polynomial','squareroot', 'exponential', 'logarithmic', ...
                    'powerlaw', 'polynomial', 'polynomial'};
    polynomialFitDegreeArray = [1, 2, 1, 1, 1, 1, 3, 4];
    numberCoefficientsArray =  [2, 3, 2, 2, 2, 2 ,4, 5];

    sorted_data_array = cell(1, numCases);
    validationData_array = cell(1, numCases);

    ValidationCase = 0;
    perCaseFraction = floor(numCases / 8);
    

    for idx = 1:numCases
        % Evenly distribute cases
        if mod(idx-1, perCaseFraction) == 0 && ValidationCase < 8
            ValidationCase = ValidationCase + 1;
        end 
       % ValidationCase = randi(8); % Randomly select one of the 8 cases

        % Generate random coefficients for the current model
        p   = (rand(1, numberCoefficientsArray(ValidationCase)) - 0.5) * 4; % Range: -2 to +2
        x = linspace(1, 1000, 20)'; % x values from 1 to 100

        switch ValidationCase
            case 1  % Linear
                a = p(2); b = p(1);
                yIdeal = a + b * x;
                fitTypeTex = 'a + b x';
                coefficientsText = sprintf('%.2f + %.2f x', a, b);
                fitType = 'polynomial'; degree = 1;
            case 2  % Quadratic
                a = p(3); b = p(2); c = p(1);
                yIdeal = a + b * x + c * x.^2;
                fitTypeTex = 'a + b x + c x^2';
                coefficientsText = sprintf('%.2f + %.2f x + %.2f x^2', a, b, c);
                fitType = 'polynomial'; degree = 2;
            case 3  % Square Root
                a = p(1); b = p(2);
                yIdeal = a * sqrt(x) + b;
                fitTypeTex = 'a sqrt(x) + b';
                coefficientsText = sprintf('%.2f sqrt(x) + %.2f', a, b);
                fitType = 'squareroot'; degree = 1;
            case 4  % Exponential
                a = p(2);
                b = (rand - 0.5) * 0.1; % b in [-0.05, 0.05]
                yIdeal = a * exp(b * x);
                fitTypeTex = 'a exp(b x)';
                coefficientsText = sprintf('%.2f exp(%.2f x)', a, b);
                fitType = 'exponential'; degree = 1;
            case 5  % Logarithmic
                a = p(1); b = p(2);
                yIdeal = a * log(x) + b;
                fitTypeTex = 'a ln(x) + b';
                coefficientsText = sprintf('%.2f ln(x) + %.2f', a, b);
                fitType = 'logarithmic'; degree = 1;
            case 6 % Power Law
                a = p(1);
                b = (rand - 0.5) * 24; % exponent in [-2, 2]
                yIdeal = a * (x .^ b);
                fitTypeTex = 'a x^b';
                coefficientsText = sprintf('%.2f x^{%.2f}', a, b);
                fitType = 'powerlaw'; degree = 1;
            case 7  % Cubic
                a = p(4); b = p(3); c = p(2); d = p(1);
                yIdeal = a + b * x + c * x.^2 + d * x.^3;
                fitTypeTex = 'a + b x + c x^2 + d x^3';
                coefficientsText = sprintf('%.2f + %.2f x + %.2f x^2 + %.2f x^3', a, b, c, d);
                fitType = 'polynomial'; degree = 3;
            case 8  % Quartic
                % Limit quartic coefficients to a smaller range
                a = p(5); b = p(4); c = p(3); 
                d = (rand - 0.5) * 0.5; % d in [-0.25, 0.25] 
                e = (rand - 0.5) * 0.1; % e in [-0.1, 0.1]
                yIdeal = a + b * x + c * x.^2 + d * x.^3 + e * x.^4;
                fitTypeTex = 'a + b x + c x^2 + d x^3 + e x^4';
                coefficientsText = sprintf('%.2f + %.2f x + %.2f x^2 + %.2f x^3 + %.2f x^4', a, b, c, d, e);
                fitType = 'polynomial'; degree = 4;
        end

        yIdealFinite = yIdeal(isfinite(yIdeal));
        rangeY = max(yIdealFinite) - min(yIdealFinite);
        relativeNoiseLevel = relNoiseConstant; % relative to range of yIdeal is determined here based on function argument
        absoluteNoiseFloor = 1; % Minimum noise

        noise = absoluteNoiseFloor + relativeNoiseLevel * rangeY;
        y = yIdeal + noise * randn(size(yIdeal));

        maxPlotValue = 1e6;
        yIdeal(abs(yIdeal) > maxPlotValue) = NaN;
        y(abs(y) > maxPlotValue) = NaN;

        sorted_data = struct();
        sorted_data.x = x;
        sorted_data.y = y;
        sorted_data.yIdeal = yIdeal;

        validationData = struct();
        validationData.fitType = fitType;
        validationData.degree = degree;
        validationData.fitTypeTex = fitTypeTex;
        validationData.coefficientsText = coefficientsText;
        validationData.coefficients = p;
        validationData.dataX = x;
        validationData.dataY = yIdeal;
        validationData.degree = polynomialFitDegreeArray(ValidationCase);

        sorted_data_array{idx} = sorted_data;
        validationData_array{idx} = validationData;

       
    end
     % Plot each case
    plotCases = false;

    if plotCases
        outputFolder = 'validation_plots';
        if ~exist(outputFolder, 'dir')
            mkdir(outputFolder);
        end
        for idx = 1:numCases
            x = sorted_data_array{idx}.x;
            y = sorted_data_array{idx}.y;
            yIdeal = sorted_data_array{idx}.yIdeal;
            coeffText = validationData_array{idx}.coefficientsText;  % True function text
            fitTypeTex = validationData_array{idx}.fitTypeTex;

            maxPlotValue = 1e6;
            yIdeal(abs(yIdeal) > maxPlotValue) = NaN;
            y(abs(y) > maxPlotValue) = NaN;

            if all(isnan(yIdeal)) || all(isnan(y))
                continue; % Skip this plot
            end

            figure('visible','off');
            scatter(x, y, 10, 'b', 'filled'); hold on;
            plot(x, yIdeal, 'r-', 'LineWidth', 2, ...
                'DisplayName', sprintf('True Function (%s)', coeffText));

            legend('Noisy Data', ...
                sprintf('True Function (%s)', coeffText), ...
                'Location', 'northeast');
                
            xlabel('x');
            ylabel('y');
            title(sprintf('Validation Case %d: %s', idx, fitTypeTex));
            grid on;

            print(fullfile(outputFolder, sprintf('validation_case_%03d.png', idx)), '-dpng');
            close(gcf);
        end
    end
end