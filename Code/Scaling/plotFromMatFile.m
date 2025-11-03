function plotFromMatFile(matFilePath)
% plotFromMatFile - Create plots from saved parameter study results
%
% Usage:
%   plotFromMatFile('parameterStudy_results/fit_quality_report_N100_20251020_225107.mat')
%   plotFromMatFile()  % opens file dialog

    if nargin < 1 || isempty(matFilePath)
        % Set default directory (use results folder if it exists, otherwise current dir)
        defaultDir = 'parameterStudy_results';
        if ~exist(defaultDir, 'dir')
            defaultDir = '.';
        end
        
        % Open file dialog starting in default directory
        [filename, pathname] = uigetfile('*.mat', 'Select parameter study MAT file', defaultDir);
        if isequal(filename, 0)
            fprintf('No file selected.\n');
            return;
        end
        matFilePath = fullfile(pathname, filename);
    end
    
    % Check if file exists
    if ~exist(matFilePath, 'file')
        error('File not found: %s', matFilePath);
    end
    
    fprintf('Loading data from: %s\n', matFilePath);
    
    % Load the data
    data = load(matFilePath);
    
    % Extract main variables
    if isfield(data, 'fit_quality_report')
        report = data.fit_quality_report;
        thresholds = report.thresholds;
        numCases = report.numCases;
        
        % Check if we have matrix data (multi-noise) or single-noise data
        if isfield(report, 'M1') && size(report.M1, 1) > 1
            % Multi-noise data available
            plotMultiNoiseResults(report, thresholds, numCases);
        else
            % Single-noise data only
            plotSingleNoiseResults(report, thresholds, numCases);
        end
        
        % Also create noise study plot if available
        if isfield(report, 'noiseStudy')
            plotNoiseStudy(report.noiseStudy, numCases);
        end
        
    else
        error('Invalid MAT file: missing fit_quality_report structure');
    end
    
    fprintf('Plotting completed.\n');
end

function plotMultiNoiseResults(report, thresholds, numCases)
    % Plot results with multiple noise levels (family of curves)
    
    M1Mat = report.M1 * 100;  % convert to percent
    M2Mat = report.M2 * 100;
    M3Mat = report.M3 * 100;
    noiseRange = report.noiseRange;
    nNoise = length(noiseRange);
    
    % Create figure with dissertation-appropriate styling
    hFig = figure('Name', 'Parameter Study Results (Multi-Noise)', 'Position', [100, 100, 800, 600]);
    hold on;
    
    % Elegant distinct colors for dissertation
    colM1 = [0.2 0.2 0.8];         % Deep blue for M1
    colM2 = [0.8 0.2 0.2];         % Deep red for M2
    colM3 = [0.2 0.6 0.2];         % Deep green for M3
    
    % All lines solid
    lineStyle = '-';       % Solid for all metrics
    
    % Transparency levels for noise (higher noise = more transparent)
    alphas = linspace(1.0, 0.3, max(1, nNoise));
    lineWidth = 1.2;  % Consistent line width
    
    % Plot family of curves
    for nIdx = 1:nNoise
       alpha = alphas(nIdx);
       
       % Create transparent colors by blending with white background
       colM1_alpha = alpha * colM1 + (1-alpha) * [1 1 1];
       colM2_alpha = alpha * colM2 + (1-alpha) * [1 1 1];
       colM3_alpha = alpha * colM3 + (1-alpha) * [1 1 1];
        
        % Plot curves
       plot(thresholds, M1Mat(nIdx,:), lineStyle, 'Color', colM1_alpha, 'LineWidth', lineWidth);
       plot(thresholds, M2Mat(nIdx,:), lineStyle, 'Color', colM2_alpha, 'LineWidth', lineWidth);
       plot(thresholds, M3Mat(nIdx,:), lineStyle, 'Color', colM3_alpha, 'LineWidth', lineWidth);
    end
    
    % Add markers for first noise level (lowest noise)
    [M2_max, M2_max_idx] = max(M2Mat(1,:));
    M2_max_thresh = thresholds(M2_max_idx);
    [M1_max, M1_max_idx] = max(M1Mat(1,:));
    M1_max_thresh = thresholds(M1_max_idx);
    M3_at = M3Mat(1, M2_max_idx);
    M1_at_M2_max = M1Mat(1, M2_max_idx);
    
    % Vertical line at M2 max
    yl = ylim();
    line([M2_max_thresh, M2_max_thresh], yl, 'Color', [0.3 0.3 0.3], 'LineStyle', ':', 'LineWidth', 0.8);
    
    % Elegant markers - fixed M1 markers
    plot(M2_max_thresh, M2_max, 's', 'MarkerSize', 6, 'MarkerFaceColor', colM2, 'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    plot(M2_max_thresh, M3_at, 'o', 'MarkerSize', 6, 'MarkerFaceColor', colM3, 'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    plot(M1_max_thresh, M1_max, 'd', 'MarkerSize', 6, 'MarkerFaceColor', colM1, 'MarkerEdgeColor', 'k', 'LineWidth', 0.8);     % M1 max marker
    plot(M2_max_thresh, M1_at_M2_max, '^', 'MarkerSize', 6, 'MarkerFaceColor', colM1, 'MarkerEdgeColor', 'k', 'LineWidth', 0.8); % M1 at M2 max marker
    
    % Add value annotations (dissertation style)
    addValueAnnotations(M1_max, M1_max_thresh, M2_max, M2_max_thresh, M1_at_M2_max, M3_at);
    
    % Noise level documentation (bottom left)
    noiseText = sprintf('Noise: %.2f–%.2f (opaque→transparent)', min(noiseRange), max(noiseRange));
    text(0.02, 0.02, noiseText, 'Units', 'normalized', 'VerticalAlignment', 'bottom', ...
         'HorizontalAlignment', 'left', 'FontSize', 9, 'BackgroundColor', 'w', 'EdgeColor', 'none');
    
    % Dissertation-appropriate styling
    xlabel('Threshold / - ');
    ylabel('Accuracy / % ');
    title(sprintf('Fit Type Identification Accuracy vs. Threshold (%d test cases)', numCases));
    legend({'M_1 - Perfect','M_2 - Type','M_3 - ≤Complexity'}, 'Location', 'northwest', 'Box', 'off');
    grid on;
    box on;
    set(gca, 'FontSize', 11, 'GridAlpha', 0.3);
    axis tight;
    hold off;
    
    % Save plot
    savePlot(hFig, sprintf('replot_multiNoise_N%d', numCases));
end

function addValueAnnotations(M1_max, M1_max_thresh, M2_max, M2_max_thresh, M1_at_M2_max, M3_at)
    % Add clean value annotations for dissertation
    
    % Get current axes limits for positioning
    xl = xlim();
    yl = ylim();
    
    % Annotation style
    annotStyle = {'FontSize', 9, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
                  'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 2};
    
    % M1 maximum annotation (to the left of its marker)
    annotStyleRight = {'FontSize', 9, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
                      'BackgroundColor', 'w', 'EdgeColor', 'none', 'Margin', 2};
    text(M1_max_thresh - 0.02*(xl(2)-xl(1)), M1_max + 0.01*(yl(2)-yl(1)), ...
         sprintf('M_{1,max} = %.1f%%\n@ %.3f', M1_max, M1_max_thresh), annotStyleRight{:});
    
    % M2 maximum annotation  
    text(M2_max_thresh + 0.02*(xl(2)-xl(1)), M2_max + 0.01*(yl(2)-yl(1)), ...
         sprintf('M_{2,max} = %.1f%%\n@ %.3f', M2_max, M2_max_thresh), annotStyle{:});
    
    % M1 and M3 values at M2 optimum (aligned at M2 max x position)
    text(M2_max_thresh + 0.02*(xl(2)-xl(1)), M1_at_M2_max + 0.01*(yl(2)-yl(1)), ...
         sprintf('M_1 = %.1f%%', M1_at_M2_max), annotStyle{:});
    
    text(M2_max_thresh + 0.02*(xl(2)-xl(1)), M3_at - 0.03*(yl(2)-yl(1)), ...
         sprintf('M_3 = %.1f%%', M3_at), annotStyle{:});
end

function plotSingleNoiseResults(report, thresholds, numCases)
    % Plot results for single noise level (traditional view)
    
    M1 = report.perfect * 100;
    M2 = report.typeOnly * 100;
    M3 = report.lowerOrEqualComplexity * 100;
    
    % Create figure
    hFig = figure('Name', 'Parameter Study Results (Single-Noise)', 'Position', [200, 200, 800, 600]);
    hold on;
    
    % Colors
    colM1 = [0 0.4470 0.7410];
    colM2 = [0.8500 0.3250 0.0980];
    colM3 = [0.4660 0.6740 0.1880];
    
    % Plot main curves
    plot(thresholds, M1, '-', 'Color', colM1, 'LineWidth', 1.5);
    plot(thresholds, M2, '-', 'Color', colM2, 'LineWidth', 1.5);
    plot(thresholds, M3, '-', 'Color', colM3, 'LineWidth', 1.5);
    
    % Find and mark maxima
    [M2_max, M2_max_idx] = max(M2);
    M2_max_thresh = thresholds(M2_max_idx);
    [M1_max, M1_max_idx] = max(M1);
    M1_max_thresh = thresholds(M1_max_idx);
    M3_at = M3(M2_max_idx);
    
    % Vertical line and markers
    yl = ylim();
    line([M2_max_thresh, M2_max_thresh], yl, 'Color', [0.5 0 0.5], 'LineStyle', '--', 'LineWidth', 1.2);
    plot(M2_max_thresh, M2_max, 'p', 'MarkerSize', 10, 'MarkerFaceColor', colM2, 'MarkerEdgeColor', 'k');
    plot(M2_max_thresh, M3_at, 'o', 'MarkerSize', 8, 'MarkerFaceColor', colM3, 'MarkerEdgeColor', 'k');
    plot(M1_max_thresh, M1_max, 'd', 'MarkerSize', 9, 'MarkerFaceColor', colM1, 'MarkerEdgeColor', 'k');
    
    % Styling
    xlabel('Threshold');
    ylabel('Accuracy (%)');
    title(sprintf('Fit Type Identification Accuracy vs. Threshold (%d test cases)', numCases));
    legend({'M_1 - Perfect Identification','M_2 - Type Identification','M_3 - ≤Complexity'}, 'Location', 'southeast');
    grid on;
    box on;
    set(gca, 'FontSize', 10);
    axis tight;
    hold off;
    
    % Save plot
    savePlot(hFig, sprintf('replot_singleNoise_N%d', numCases));
end

function plotNoiseStudy(noiseStudy, numCases)
    % Plot noise study results if available
    
    if ~isfield(noiseStudy, 'N1_perfect')
        fprintf('No noise study data available.\n');
        return;
    end
    
    noiseRange = noiseStudy.noiseRange;
    
    % Average across thresholds if matrix data
    if size(noiseStudy.N1_perfect, 2) > 1
        N1 = mean(noiseStudy.N1_perfect, 2)';
        N2 = mean(noiseStudy.N2_typeOnly, 2)';
        N3 = mean(noiseStudy.N3_complexity, 2)';
        titleSuffix = sprintf('(avg over %d thresholds)', size(noiseStudy.N1_perfect, 2));
    else
        N1 = noiseStudy.N1_perfect;
        N2 = noiseStudy.N2_typeOnly;
        N3 = noiseStudy.N3_complexity;
        titleSuffix = sprintf('(threshold=%.2f)', noiseStudy.fixedThreshold);
    end
    
    % Create figure
    hFig = figure('Name', 'Noise Study Results', 'Position', [300, 300, 800, 600]);
    hold on;
    
    % Colors (same as main metrics)
    colN1 = [0 0.4470 0.7410];
    colN2 = [0.8500 0.3250 0.0980];
    colN3 = [0.4660 0.6740 0.1880];
    
    % Plot with markers
    plot(noiseRange, N1, '-', 'Color', colN1, 'LineWidth', 1.5, 'Marker', 'o', 'MarkerSize', 6);
    plot(noiseRange, N2, '-', 'Color', colN2, 'LineWidth', 1.5, 'Marker', 's', 'MarkerSize', 6);
    plot(noiseRange, N3, '-', 'Color', colN3, 'LineWidth', 1.5, 'Marker', '^', 'MarkerSize', 6);
    
    % Styling
    xlabel('Noise Level (relative)');
    ylabel('Accuracy (%)');
    title(sprintf('Fit Type Identification vs. Noise Level %s (%d test cases)', titleSuffix, numCases));
    legend({'N_1 - Perfect Identification', 'N_2 - Type Identification', 'N_3 - ≤Complexity'}, 'Location', 'best');
    grid on;
    box on;
    set(gca, 'FontSize', 10);
    axis tight;
    hold off;
    
    % Save plot
    savePlot(hFig, sprintf('replot_noiseStudy_N%d', numCases));
end

function savePlot(hFig, baseFilename)
    % Save plot to results folder
    
    resultsFolder = 'parameterStudy_results';
    if ~exist(resultsFolder, 'dir')
        mkdir(resultsFolder);
    end
    
    filename = fullfile(resultsFolder, sprintf('%s_%s.png', baseFilename, datestr(now,'yyyymmdd_HHMMSS')));
    
    try
        print(hFig, filename, '-dpng');
        fprintf('Plot saved: %s\n', filename);
    catch
        warning('Could not save plot to %s', filename);
    end
end