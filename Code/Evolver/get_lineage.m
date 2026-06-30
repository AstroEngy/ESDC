% get_lineage — Extract the history of one lineage from the generation archive
%
% PURPOSE:
%   Collects all historical individuals for a specific case/seed combination
%   (i.e. one evolutionary lineage) into a flat cell array.  Used by fitness
%   comparison functions (test_maximize_parameter, test_lineage_convergence_simple)
%   which need access to prior generations of the same lineage to evaluate
%   improvement trends.
%
% INTENT:
%   Decouples the lineage-history logic from the generation storage format.
%   The generation_data cell array stores all [n_cases × n_seeds] structs;
%   this function slices out a single (n_case, n_individual) trajectory.
%
% Parameters:
%   generation_data  (cell): Full generation archive as produced by evolver.
%                    generation_data{g}(i, j) = individual at generation g,
%                    case i, lineage j.
%   n_case           (int): Case index (row in the population matrix).
%   n_individual     (int): Seed/lineage index (column in the matrix).
%
% Returns:
%   lineage (cell): 1×n_gen cell, lineage{g} = individual at generation g.
%
% HOW TO TEST:
%   1. Create a dummy generation_data with 3 generations, 1 case, 2 seeds.
%      Call get_lineage(generation_data, 1, 1) and verify you get 3 entries
%      all belonging to case 1, seed 1.
%   2. Verify that modifying an entry in lineage does NOT modify generation_data
%      (cell arrays in Octave/MATLAB are value-type; verify independence).
%
% SAFEGUARDS TO ADD (future work):
%   - Validate n_case and n_individual are within bounds of generation_data{1}
%     to give a clear error rather than an indexing exception.
function lineage = get_lineage(generation_data, n_case, n_individual)
  % Walk all stored generations and collect this lineage's individual at each step.
  lineage = {};
  for i=1:size(generation_data,2)
    lineage{end+1} = generation_data{i}(n_case, n_individual);
  end
end