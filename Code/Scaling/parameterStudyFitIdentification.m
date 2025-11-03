function fit_quality_report = parameterStudyFitIdentification(numCases, thresholds, noiseRange)
% parameterStudyFitIdentification  Run parameter study over thresholds and
% report three performance metrics:
%  1) perfect fit (correct type AND correct poly degree for polynomials)
%  2) correct type (regardless of polynomial degree)
%  3) correct or lower complexity (predicted complexity index <= true)
%
% Usage:
%   fit_quality_report = parameterStudyFitIdentification();              % defaults
%   fit_quality_report = parameterStudyFitIdentification(500, 0:0.01:0.2);

    if nargin < 1 || isempty(numCases), numCases = 4000; end
    if nargin < 2 || isempty(thresholds), thresholds = 0.1:0.01:1.1; end
    if nargin < 3 || isempty(noiseRange), noiseRange = 0.01:0.1:1; end

    % Complexity ordering: list fits in increasing complexity so polynomial
    % degrees 1 & 2 appear before exponential functions, polynomial degree 3 & 4 most complex.
    fitTypeArray = {'polynomial', 'polynomial','squareroot', 'exponential', 'logarithmic', ...
                    'powerlaw', 'polynomial', 'polynomial'};
    polynomialFitDegreeArray = [1, 2, 1, 1, 1, 1, 3, 4];
    numberCoefficientsArray =  [2, 3, 2, 2, 2, 2 ,4, 5];

    % Generate validation data (no plotting)
    nNoise = numel(noiseRange);
    nT = numel(thresholds);
    
    % matrices: rows = noise levels, cols = thresholds
    M1Mat = zeros(nNoise, nT);   % Perfect
    M2Mat = zeros(nNoise, nT);   % Type only
    M3Mat = zeros(nNoise, nT);   % <= complexity

    for nIdx = 1:nNoise
        relNoise = noiseRange(nIdx);
        % generate validation data for this noise level
        [sorted_data_array, validationData_array] = validationDataGeneration(numCases, relNoise);
        
        perfectCount = zeros(1, nT);
        typeOnlyCount = zeros(1, nT);
        lowerOrEqualComplexityCount = zeros(1, nT);

        for tIdx = 1:nT
            thr = thresholds(tIdx);
            for idx = 1:numCases
                dataX = sorted_data_array{idx}.x;
                dataY = sorted_data_array{idx}.y;

                trueType = validationData_array{idx}.fitType;
                trueDegree = validationData_array{idx}.degree;

                [predType, predDegree, ~, ~] = determineFitTypeWithThreshold(dataX, dataY, thr);

                % Metric 1: perfect fit (type + for polynomials, degree)
                isPerfect = false;
                if strcmp(predType, trueType)
                    if strcmp(predType, 'polynomial')
                        isPerfect = (predDegree == trueDegree);
                    else
                        isPerfect = true;
                    end
                end
                perfectCount(tIdx) = perfectCount(tIdx) + double(isPerfect);

                % Metric 2: correct type irrespective of polynomial degree
                isTypeMatch = strcmp(predType, trueType);
                typeOnlyCount(tIdx) = typeOnlyCount(tIdx) + double(isTypeMatch);

                % Metric 3: correct or lower complexity
                predIdx = find(strcmp(fitTypeArray, predType) & (polynomialFitDegreeArray == predDegree), 1);
                trueIdx = find(strcmp(fitTypeArray, trueType) & (polynomialFitDegreeArray == trueDegree), 1);
                if isempty(predIdx), predIdx = find(strcmp(fitTypeArray, predType), 1); end
                if isempty(trueIdx), trueIdx = find(strcmp(fitTypeArray, trueType), 1); end
                if isempty(predIdx), predIdx = numel(fitTypeArray); end
                if isempty(trueIdx), trueIdx = numel(fitTypeArray); end

                if isTypeMatch
                    isLowerOrEqual = true;
                else
                    isLowerOrEqual = (predIdx <= trueIdx);
                end
                lowerOrEqualComplexityCount(tIdx) = lowerOrEqualComplexityCount(tIdx) + double(isLowerOrEqual);
            end
        end

        M1Mat(nIdx, :) = perfectCount / numCases;
        M2Mat(nIdx, :) = typeOnlyCount / numCases;
        M3Mat(nIdx, :) = lowerOrEqualComplexityCount / numCases;
    end

    % assemble report (fractions and percentages)
    fit_quality_report.thresholds = thresholds;
    fit_quality_report.numCases = numCases;
    fit_quality_report.noiseRange = noiseRange;
    fit_quality_report.M1 = M1Mat;
    fit_quality_report.M2 = M2Mat;
    fit_quality_report.M3 = M3Mat;
    % backward compatibility: use first noise level
    fit_quality_report.perfect = M1Mat(1, :);
    fit_quality_report.typeOnly = M2Mat(1, :);
    fit_quality_report.lowerOrEqualComplexity = M3Mat(1, :);

    % Print summary table
    fprintf('Threshold\tPerfect(%%)\tTypeOnly(%%)\t<=Complexity(%%)\n');
    for i = 1:nT
        fprintf('%.3f\t\t%.2f\t\t%.2f\t\t%.2f\n', thresholds(i), ...
            fit_quality_report.perfect(i)*100, ...
            fit_quality_report.typeOnly(i)*100, ...
            fit_quality_report.lowerOrEqualComplexity(i)*100);
    end

    % Generate plots and save results
    fit_quality_report = generatePlotsAndSaveResults(fit_quality_report, thresholds, numCases);

    % NEW: Add noise level study segment
    fit_quality_report = runNoiseStudy(fit_quality_report, numCases, thresholds, noiseRange);

    return;
end

function fit_quality_report = runNoiseStudy(fit_quality_report, numCases, thresholds, noiseRange)
    % Run study over noise levels with multiple thresholds and evaluate M1, M2, M3 metrics
    
    fprintf('\n=== Noise Level Study ===\n');
    
    % Use multiple thresholds for noise study
    nThresholds = length(thresholds);
    
    % Complexity ordering (keep consistent with main study)
    fitTypeArray = {'polynomial', 'polynomial','squareroot', 'exponential', 'logarithmic', ...
                    'powerlaw', 'polynomial', 'polynomial'};
    polynomialFitDegreeArray = [1, 2, 1, 1, 1, 1, 3, 4];
    
    nNoise = numel(noiseRange);
    
    % Metrics vs noise level (matrices: rows=noise, cols=thresholds)
    N1_perfect = zeros(nNoise, nThresholds);      % M1 vs noise vs threshold
    N2_typeOnly = zeros(nNoise, nThresholds);     % M2 vs noise vs threshold
    N3_complexity = zeros(nNoise, nThresholds);   % M3 vs noise vs threshold
    
    for nIdx = 1:nNoise
        relNoise = noiseRange(nIdx);
        
        % Generate validation data for this noise level
        [sorted_data_array, validationData_array] = validationDataGeneration(numCases, relNoise);
        
        % Loop over all thresholds for this noise level
        for tIdx = 1:nThresholds
            thr = thresholds(tIdx);
            
            % Counters for this noise-threshold combination
            perfectCount = 0;
            typeOnlyCount = 0;
            lowerOrEqualComplexityCount = 0;
            
            for idx = 1:numCases
                dataX = sorted_data_array{idx}.x;
                dataY = sorted_data_array{idx}.y;
                
                trueType = validationData_array{idx}.fitType;
                trueDegree = validationData_array{idx}.degree;
                
                % Determine predicted fit using current threshold
                [predType, predDegree, ~, ~] = determineFitTypeWithThreshold(dataX, dataY, thr);
                
                % Metric N1: perfect fit (same as M1)
                isPerfect = false;
                if strcmp(predType, trueType)
                    if strcmp(predType, 'polynomial')
                        isPerfect = (predDegree == trueDegree);
                    else
                        isPerfect = true;
                    end
                end
                perfectCount = perfectCount + double(isPerfect);
                
                % Metric N2: correct type (same as M2)
                isTypeMatch = strcmp(predType, trueType);
                typeOnlyCount = typeOnlyCount + double(isTypeMatch);
                
                % Metric N3: correct or lower complexity (same as M3)
                predIdx = find(strcmp(fitTypeArray, predType) & (polynomialFitDegreeArray == predDegree), 1);
                trueIdx = find(strcmp(fitTypeArray, trueType) & (polynomialFitDegreeArray == trueDegree), 1);
                if isempty(predIdx), predIdx = find(strcmp(fitTypeArray, predType), 1); end
                if isempty(trueIdx), trueIdx = find(strcmp(fitTypeArray, trueType), 1); end
                if isempty(predIdx), predIdx = numel(fitTypeArray); end
                if isempty(trueIdx), trueIdx = numel(fitTypeArray); end
                
                if isTypeMatch
                    isLowerOrEqual = true;
                else
                    isLowerOrEqual = (predIdx <= trueIdx);
                end
                lowerOrEqualComplexityCount = lowerOrEqualComplexityCount + double(isLowerOrEqual);
            end
            
            % Store percentages for this noise-threshold combination
            N1_perfect(nIdx, tIdx) = perfectCount / numCases * 100;
            N2_typeOnly(nIdx, tIdx) = typeOnlyCount / numCases * 100;
            N3_complexity(nIdx, tIdx) = lowerOrEqualComplexityCount / numCases * 100;
        end
    end
    
    % Store noise study results in fit_quality_report
    fit_quality_report.noiseStudy.thresholds = thresholds;
    fit_quality_report.noiseStudy.noiseRange = noiseRange;
    fit_quality_report.noiseStudy.N1_perfect = N1_perfect;
    fit_quality_report.noiseStudy.N2_typeOnly = N2_typeOnly;
    fit_quality_report.noiseStudy.N3_complexity = N3_complexity;
    
    % Print noise study summary (show average across thresholds)
    fprintf('Noise Level\tN1-Perfect(%%)\tN2-TypeOnly(%%)\tN3-≤Complexity(%%)\n');
    for i = 1:nNoise
        fprintf('%.3f\t\t%.2f\t\t%.2f\t\t%.2f\n', noiseRange(i), ...
            mean(N1_perfect(i,:)), mean(N2_typeOnly(i,:)), mean(N3_complexity(i,:)));
    end
    
    % Generate noise study plot
    fit_quality_report = generateNoiseStudyPlot(fit_quality_report);
end

function fit_quality_report = generateNoiseStudyPlot(fit_quality_report)
    % Generate plot showing metrics vs noise level (averaged across thresholds)
    
    resultsFolder = 'parameterStudy_results';
    if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end
    
    noiseRange = fit_quality_report.noiseStudy.noiseRange;
    % Average across thresholds for plotting
    N1 = mean(fit_quality_report.noiseStudy.N1_perfect, 2)';  % average each row (noise level)
    N2 = mean(fit_quality_report.noiseStudy.N2_typeOnly, 2)';
    N3 = mean(fit_quality_report.noiseStudy.N3_complexity, 2)';
    thresholds = fit_quality_report.noiseStudy.thresholds;
    
    % Create noise study plot
    hNoise = figure('visible','off');
    hold on;
    
    % Use same colors as main study for consistency
    colN1 = [0 0.4470 0.7410];     % Blue for N1 (same as M1)
    colN2 = [0.8500 0.3250 0.0980]; % Orange for N2 (same as M2)
    colN3 = [0.4660 0.6740 0.1880]; % Green for N3 (same as M3)
    
    % Plot lines
    plot(noiseRange, N1, '-', 'Color', colN1, 'LineWidth', 1.5, 'Marker', 'o', 'MarkerSize', 6);
    plot(noiseRange, N2, '-', 'Color', colN2, 'LineWidth', 1.5, 'Marker', 's', 'MarkerSize', 6);
    plot(noiseRange, N3, '-', 'Color', colN3, 'LineWidth', 1.5, 'Marker', '^', 'MarkerSize', 6);
    
    % Styling
    xlabel('Noise Level (relative)');
    ylabel('Accuracy (%)');
    title(sprintf('Fit identification vs Noise Level (thresholds=[%.2f:%.2f], N=%d)', min(thresholds), max(thresholds), fit_quality_report.numCases));
    legend({'N1 - Perfect Identification', 'N2 - Type Identification', 'N3 - Simpler Fit'}, 'Location', 'northwest');
    grid on;
    box on;
    set(gca, 'FontSize', 10);
    axis tight;
    hold off;
    
    % Save noise study plot
    noisePlotFile = fullfile(resultsFolder, sprintf('accuracy_vs_noise_thrRange_N%d_%s.png', ...
        fit_quality_report.numCases, datestr(now,'yyyymmdd_HHMMSS')));
    try
        print(hNoise, noisePlotFile, '-dpng');
        fit_quality_report.noiseStudy.plotFile = noisePlotFile;
        fprintf('Noise study plot saved: %s\n', noisePlotFile);
    catch
        warning('Could not save noise study plot to %s', noisePlotFile);
        fit_quality_report.noiseStudy.plotFile = '';
    end
    close(hNoise);
end


function fit_quality_report = generatePlotsAndSaveResults(fit_quality_report, thresholds, numCases)
    % ensure results folder is defined and exists
    resultsFolder = 'parameterStudy_results';
    if ~exist(resultsFolder, 'dir')
        mkdir(resultsFolder);
    end

    % prepare data for plotting (convert to percent)
    M1Mat = fit_quality_report.M1 * 100;  % rows=noise, cols=thresholds
    M2Mat = fit_quality_report.M2 * 100;
    M3Mat = fit_quality_report.M3 * 100;
    nNoise = size(M1Mat, 1);

    % compute M2 maximum and corresponding threshold (use first noise level for markers)
    [M2_max, M2_max_idx] = max(M2Mat(1,:));
    M2_max_thresh = thresholds(M2_max_idx);

    M3_full_idx = find(any(M3Mat >= 100, 1), 1); % first threshold where any noise level reaches 100%
    if ~isempty(M3_full_idx)
        M3_full_thresh = thresholds(M3_full_idx);
    else
        M3_full_thresh = NaN;
    end

    % store in report
    fit_quality_report.M2_max = M2_max;
    fit_quality_report.M2_max_thresh = M2_max_thresh;
    fit_quality_report.M3_full_idx = M3_full_idx;
    fit_quality_report.M3_full_thresh = M3_full_thresh;

    % create styled plot (no popup)
    hAcc = figure('visible','off');
    hold on;
    % metric colors (keep consistent)
    colM1 = [0 0.4470 0.7410];
    colM2 = [0.8500 0.3250 0.0980];
    colM3 = [0.4660 0.6740 0.1880];

    % opacity levels for different noise levels (higher noise = less visible)
    alphas = linspace(1.0, 0.3, max(1, nNoise));  % fade from opaque to transparent (higher noise = less visible)

    % plot family of curves for each metric
    for nIdx = 1:nNoise
        alpha = alphas(nIdx);
        
        % Create color with manual alpha blending (works in Octave)
        % Blend with white background: newColor = alpha*originalColor + (1-alpha)*white
        colM1_alpha = alpha * colM1 + (1-alpha) * [1 1 1];
        colM2_alpha = alpha * colM2 + (1-alpha) * [1 1 1];
        colM3_alpha = alpha * colM3 + (1-alpha) * [1 1 1];
        
        % M1 family
        h1 = plot(thresholds, M1Mat(nIdx,:), '-', 'Color', colM1_alpha, 'LineWidth', 1.5);
        
        % M2 family  
        h2 = plot(thresholds, M2Mat(nIdx,:), '-', 'Color', colM2_alpha, 'LineWidth', 1.5);
        
        % M3 family
        h3 = plot(thresholds, M3Mat(nIdx,:), '-', 'Color', colM3_alpha, 'LineWidth', 1.5);
    end

    % Add noise level documentation to the plot
    noiseRange = fit_quality_report.noiseRange;
    % Create text annotation showing noise level mapping
    noiseText = sprintf('Noise levels: %.2f (opaque) → %.2f (transparent)', min(noiseRange), max(noiseRange));
    text(0.02, 0.98, noiseText, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
         'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'k');

    % draw vertical line at M2 max threshold
    ax = gca;
    yl = ylim(ax);
    vline = line([M2_max_thresh, M2_max_thresh], yl, 'Color', [0.5 0 0.5], 'LineStyle', '--', 'LineWidth', 1.2);

    % mark M2 max with a filled pentagram marker
    plot(M2_max_thresh, M2_max, 'p', 'MarkerSize', 10, 'MarkerFaceColor', colM2, 'MarkerEdgeColor', 'k');

    % mark intersection with M3 at the same x (use first noise level)
    M3_at = M3Mat(1, M2_max_idx);
    plot(M2_max_thresh, M3_at, 'o', 'MarkerSize', 8, 'MarkerFaceColor', colM3, 'MarkerEdgeColor', 'k');

    % Also mark M1 maximum (use first noise level)
    [M1_max, M1_max_idx] = max(M1Mat(1,:));
    M1_max_thresh = thresholds(M1_max_idx);
    % place a distinct marker for M1 max (diamond, filled blue)
    plot(M1_max_thresh, M1_max, 'd', 'MarkerSize', 9, 'MarkerFaceColor', colM1, 'MarkerEdgeColor', 'k');

    % Add annotations
    fit_quality_report = addAnnotations(fit_quality_report, ax, M1Mat(1, M1_max_idx), M1_max_thresh, M2Mat(1, M2_max_idx), M2_max_thresh, M3_at);

    % legend in southeast
    legend({'M1 - Perfect Identification','M2 - Type Identification','M3 - Underfit'}, 'Location', 'southeast');

    xlabel('Threshold');
    ylabel('Accuracy (%)');
    title(sprintf('Fit identification performance (N=%d, %d noise levels)', numCases, nNoise));
    grid on;
    box on;
    set(gca, 'FontSize', 10);
    axis tight;
    hold off;

    % save plot and .mat (Octave compatible)
    accPlotFile = fullfile(resultsFolder, sprintf('accuracy_vs_threshold_N%d_%s.png', numCases, datestr(now,'yyyymmdd_HHMMSS')));
    try
        print(hAcc, accPlotFile, '-dpng');
        fit_quality_report.accuracyPlotFile = accPlotFile;
    catch
        warning('Could not save accuracy plot to %s', accPlotFile);
        fit_quality_report.accuracyPlotFile = '';
    end
    close(hAcc);

    % save numeric summary (.mat)
    matfn = fullfile(resultsFolder, sprintf('fit_quality_report_N%d_%s.mat', numCases, datestr(now,'yyyymmdd_HHMMSS')));
    try
        save(matfn, 'fit_quality_report', 'thresholds', 'numCases', 'M1Mat','M2Mat','M3Mat', '-v7');
        fit_quality_report.summaryMAT = matfn;
    catch
        warning('Could not save %s', matfn);
        fit_quality_report.summaryMAT = '';
    end

    % Optional: collect any per-case plot files produced earlier (if you saved them)
    perCaseFolder = 'parameterStudy_plots';
    if exist(perCaseFolder, 'dir')
        files = dir(fullfile(perCaseFolder, 'case_*.png'));
        fit_quality_report.perCasePlotFiles = fullfile({files.folder}, {files.name});
    else
        fit_quality_report.perCasePlotFiles = {};
    end
end


function fit_quality_report = addAnnotations(fit_quality_report, ax, M1_max, M1_max_thresh, M2_max, M2_max_thresh, M3_at)
    % annotate markers using annotation (axes->figure transform)
    xl = xlim(ax); yl = ylim(ax);
    axpos = get(ax, 'Position');   % axes position in normalized figure units
    wbox = 0.18 * axpos(3);
    hbox = 0.05 * axpos(4);

    % annotation for M1 (place slightly above or to the right of marker)
    xdata_label_M1 = M1_max_thresh;
    ydata_label_M1 = M1_max;
    xnorm_M1 = axpos(1) + (xdata_label_M1 - xl(1)) / (xl(2) - xl(1)) * axpos(3);
    ynorm_M1 = axpos(2) + (ydata_label_M1 - yl(1)) / (yl(2) - yl(1)) * axpos(4);
    try
        annotation('textbox', [xnorm_M1, ynorm_M1, wbox, hbox], 'String', sprintf('M1 = %.2f%% @ %.3f', M1_max, M1_max_thresh), ...
                   'EdgeColor', 'none', 'BackgroundColor', 'w', 'FontSize', 9, 'HorizontalAlignment', 'left');
    catch
        text(xdata_label_M1, ydata_label_M1 + 0.01*(yl(2)-yl(1)), sprintf('M1=%.2f%% @ %.3f', M1_max, M1_max_thresh), 'Color','k', 'BackgroundColor','w', 'HorizontalAlignment','left');
    end

    % annotation for M2 (place slightly above marker)
    xdata_label = M2_max_thresh;
    ydata_label = M2_max;
    xnorm = axpos(1) + (xdata_label - xl(1)) / (xl(2) - xl(1)) * axpos(3);
    ynorm = axpos(2) + (ydata_label - yl(1)) / (yl(2) - yl(1)) * axpos(4);
    try
        annotation('textbox', [xnorm, ynorm, wbox, hbox], 'String', sprintf('M2 = %.2f%% @ %.3f', M2_max, M2_max_thresh), ...
                   'EdgeColor', 'none', 'BackgroundColor', 'w', 'FontSize', 9, 'HorizontalAlignment', 'left');
    catch
        text(xdata_label, ydata_label + 0.01*(yl(2)-yl(1)), sprintf('M2=%.2f%% @ %.3f', M2_max, M2_max_thresh), 'Color','k', 'BackgroundColor','w', 'HorizontalAlignment','left');
    end

    % annotation for M3 intersection (place slightly below the marker)
    xdata_label2 = M2_max_thresh;
    ydata_label2 = M3_at;
    xnorm2 = axpos(1) + (xdata_label2 - xl(1)) / (xl(2) - xl(1)) * axpos(3);
    ynorm2 = axpos(2) + (ydata_label2 - yl(1)) / (yl(2) - yl(1)) * axpos(4);
    try
        annotation('textbox', [xnorm2 - wbox/2, ynorm2 - 1.2*hbox, wbox, hbox], 'String', sprintf('M3 = %.2f%%', M3_at), ...
                   'EdgeColor', 'none', 'BackgroundColor', 'w', 'FontSize', 9, 'HorizontalAlignment', 'center');
    catch
        text(xdata_label2, ydata_label2 - 0.01*(yl(2)-yl(1)), sprintf('M3=%.2f%%', M3_at), 'Color','k', 'BackgroundColor','w', 'HorizontalAlignment','center', 'VerticalAlignment','top');
    end
end


function [fitType, polynomialFitDegree, coefficients, residual] = determineFitTypeWithThreshold(x, y, threshold)
    fitTypeArray = {'polynomial', 'polynomial','squareroot', 'exponential', 'logarithmic', ...
                    'powerlaw', 'polynomial', 'polynomial'};
    polynomialFitDegreeArray = [1, 2, 1, 1, 1, 1, 3, 4];
    numberCoefficientsArray =  [2, 3, 2, 2, 2, 2 ,4, 5];

    numFits = numel(fitTypeArray);
    residuals = nan(1, numFits);
    coefficientsCell = cell(1, numFits);
    yFits = cell(1, numFits);

    for i = 1:numFits
        try
            switch fitTypeArray{i}
                case 'polynomial'
                    p = polyfit(x, y, polynomialFitDegreeArray(i));
                    yFit = polyval(p, x);
                    coefficientsCell{i} = p;
                case 'squareroot'
                    p = polyfit(sqrt(x), y, 1);
                    yFit = polyval(p, sqrt(x));
                    coefficientsCell{i} = p;
                case 'exponential'
                    p = polyfit(x, log(y), 1);
                    a = exp(p(2));
                    b = p(1);
                    yFit = a * exp(b * x);
                    coefficientsCell{i} = [a b];
                case 'logarithmic'
                    p = polyfit(log(x), y, 1);
                    yFit = polyval(p, log(x));
                    coefficientsCell{i} = p;
                case 'powerlaw'
                    % Fit log(y) = log(a) + b*log(x) safely
                    validIdx = isfinite(x) & isfinite(y) & (x > 0) & (y > 0);
                    if nnz(validIdx) < 2 || numel(unique(x(validIdx))) < 2
                        % not enough positive/unique points for a reliable power-law fit
                        residuals(i) = Inf;
                        yFits{i} = nan(size(x));
                        coefficientsCell{i} = [];
                    else
                        lx = log(x(validIdx));
                        ly = log(y(validIdx));
                        % ensure there are at least two distinct log-points
                        if numel(unique(lx)) < 2
                            residuals(i) = Inf;
                            yFits{i} = nan(size(x));
                            coefficientsCell{i} = [];
                        else
                            p = polyfit(lx, ly, 1);
                            b = p(1);
                            a = exp(p(2));
                            % evaluate on full x for plotting/consistency
                            yFit = a .* (x .^ b);
                            coefficientsCell{i} = [a b];
                            yFits{i} = yFit;
                            % compute residual on the data points used for fitting
                            residuals(i) = sum((y(validIdx) - a .* (x(validIdx) .^ b)).^2);
                        end
                    end
            end
            residuals(i) = sum((y - yFit).^2);
            yFits{i} = yFit;
        catch
            residuals(i) = Inf;
            yFits{i} = nan(size(x));
        end
    end

    % Robust selection: use caller-provided threshold (no clamping)
    [minRes, ~] = min(residuals);

    % mask finite non-negative residuals
    finiteMask = isfinite(residuals) & (residuals >= 0);

    if ~any(finiteMask)
        bestIdx = 1;
    else
        % compute closeness: 1 means best (res == minRes), smaller is worse
        closeness = zeros(size(residuals));
        if minRes == 0
            % exact-zero fits considered perfect; others get 0 closeness
            closeness(finiteMask & residuals == 0) = 1;
        else
            closeness(finiteMask) = minRes ./ (residuals(finiteMask) + eps);
        end

        % select fits meeting threshold (first = lowest complexity)
        validIdx = find(closeness >= threshold);

        if isempty(validIdx)
            % fallback to absolute best residual (lowest-index tie)
            bestIdx = find(residuals == minRes & finiteMask, 1);
            if isempty(bestIdx)
                bestIdx = find(finiteMask, 1); % any finite fit
                if isempty(bestIdx), bestIdx = 1; end
            end
        else
            bestIdx = validIdx(1);
        end
    end

    fitType = fitTypeArray{bestIdx};
    polynomialFitDegree = polynomialFitDegreeArray(bestIdx);
    coefficients = coefficientsCell{bestIdx};
    residual = residuals(bestIdx);

    % Plot all fits and their residuals (styled like validationDataGeneration)
    plotCases = false; % Set to true to enable plotting
    if plotCases
        h = figure('visible','on');
        % scatter noisy data like validationDataGeneration
        scatter(x, y, 36, 'b', 'filled'); hold on;

        % plot candidate fits with distinct colors, moderate line width
        colors = lines(numFits);
        for i = 1:numFits
            if ~isempty(yFits{i}) && all(~isnan(yFits{i}))
                plot(x, yFits{i}, '-', 'Color', colors(i,:), 'LineWidth', 1.5, ...
                    'DisplayName', sprintf('%s (deg %d), res=%.2e', fitTypeArray{i}, polynomialFitDegreeArray(i), residuals(i)));
            end
        end

        % emphasize the selected fit (thicker black line)
        if ~isempty(yFits{bestIdx}) && all(~isnan(yFits{bestIdx}))
            plot(x, yFits{bestIdx}, 'k-', 'LineWidth', 3, ...
                'DisplayName', sprintf('Selected: %s (deg %d), res=%.2e', fitType, polynomialFitDegree, residual));
        end

        % styling consistent with validationDataGeneration
        legend('Location','northeast');
        xlabel('x');
        ylabel('y');
        title(sprintf('Candidate fits — selected: %s (deg %d)', fitType, polynomialFitDegree));
        grid on;
        box on;
        set(gca, 'FontSize', 10);    % similar text sizing to validation plots
        axis tight;

        % optional: save plot like validationDataGeneration (uncomment to enable)
        % outdir = 'parameterStudy_plots';
        % if ~exist(outdir, 'dir'), mkdir(outdir); end
        % outfn = fullfile(outdir, sprintf('case_plot_selected_%s.png', datestr(now,'yyyymmdd_HHMMSS')));
        % saveas(h, outfn);

        % keep figure open for inspection (remove close) or close explicitly
        % close(h);
    end
end
