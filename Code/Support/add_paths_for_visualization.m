% add_paths_for_visualization — Register all visualization sub-folders on the path
%
% PURPOSE:
%   Adds every sub-folder of Code/Output/Visualization/ to the Octave/MATLAB
%   search path so that visualization helper functions can be called by name
%   without fully-qualified paths.  Called once at ESDC() startup.
%
% INTENT:
%   The visualization tree is deep (multiple levels of sub-folders) and
%   evolves independently of the solver core.  Centralizing path registration
%   here means neither ESDC.m nor the visualization functions themselves need
%   to know the exact directory layout.
%
% Parameters:  none
% Returns:     none (side-effect: modifies Octave/MATLAB path)
%
% HOW TO TEST:
%   1. Call add_paths_for_visualization() then check that
%      which('visualize_lineage') resolves to the correct file.
%   2. Remove one of the listed paths from the workspace and verify that a
%      missing-path warning is produced (currently no warning is emitted —
%      see safeguard note below).
%
% SAFEGUARDS TO ADD (future work):
%   - Loop over the paths to be added with an exist() check and issue a
%     warning for any folder that is missing rather than silently skipping.
%   - Consider replacing the explicit list with
%       addpath(genpath('Code/Output/Visualization'))
%     so new sub-folders are picked up automatically without editing this file.
function [] = add_paths_for_visualization()
  % Each addpath call registers one visualization sub-folder.
  % The hierarchy mirrors the functional decomposition of the plot pipeline:
  %   visualize_plot_case  ->  visualize_input_case  ->  augment/animate/save/set
  addpath("Code/Output/Visualization");
  addpath("Code/Output/Visualization/visualize_plot_case");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/animate_and_save_visualization");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case/add_min_max_values_for_continuous_dofs");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case/add_number_of_subsystems");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case/add_subsystems_fieldnames");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case/add_subsystems_line_colors");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case/add_visualization_filename");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/augment_plot_case/add_visualization_lineages");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/save_visualization");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance/plot_dummy_graphics");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance/set_axis_labels");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance/set_axis_limits");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance/set_plot_legend");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance/set_plot_title");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/set_visualization_appearance/set_viewing_angle");
  addpath("Code/Output/Visualization/visualize_plot_case/visualize_input_case/visualize_lineage");
end