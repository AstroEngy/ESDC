% select_components  — Component matching for optimal design solutions
%
% Orchestrates per-subsystem component selection across all best-solution
% individuals in evolution_data.  Each subsystem selector scans the reference
% database for real hardware components compatible with the design point and
% appends its results to individual.component_matches.<subsystem>.
%
% Subsystems handled (active):
%   propulsion_system  — thrusters (technology type, propellant, thrust, c_e, power)
%   power_generation   — solar panels & batteries (power, energy capacity)
%
% Subsystems stubbed (commented-out, planned for future implementation):
%   attitude_control   — actuators / magnetorquers / reaction wheels
%   thermal            — heaters / passive elements
%   structure          — bus structures
%   communication      — transceivers / laser links
%   onboard_computer   — OBC boards
%
% Parameters:
%   evolution_data : cell array returned by evolver (best-per-lineage snapshot)
%   db_data        : database struct as loaded by input_processing
%   verbose        : (optional, default false) when true, prints per-individual
%                    propulsion selection diagnostics to the CLI.
%
% Returns:
%   evolution_data : same cell array with component_matches field added/extended
%                   on every individual in evolution_data{end}.
%     individual.component_matches.<subsystem>  — struct with fields:
%       .system_type     technology variant selected / matched
%       .design_*        design-point parameters used for scoring
%       .candidates      struct array sorted by proximity score (best first)
%         .name          component name from DB
%         .score         proximity score  (1 = perfect, 0 = worst)
%         .mass          component mass [kg]   (NaN if not in DB)
%         .source        DB source string
%
% HOW TO TEST:
%   1. Run ESDC() and inspect evolution_data{end}(1,1).component_matches.
%      It should contain .propulsion_system and .power_generation sub-structs.
%   2. For a LEO high-thrust case, verify the top-ranked thruster candidate
%      has thrust >= design_thrust (no under-powered candidate ranks first).
%   3. Set verbose=true explicitly (or remove the override) and verify the
%      CLI prints the lineage-hint vs. selected thruster comparison.
%   4. Test with an sc_type=1 (no propulsion) individual; confirm
%      component_matches.propulsion_system is empty or absent.
%   5. After adding a new subsystem selector, enable it here and run the
%      full test suite to verify no regressions in mass/power budget.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that evolution_data{end} is non-empty before the sub-selectors
%     are called.
%   - Restore the verbose parameter handling (currently overridden to true on
%     line below); controlled verbosity reduces noise in batch runs.

function evolution_data = select_components(evolution_data, db_data, verbose)
  % verbose (optional, default false): set to true to print per-individual
  % propulsion selection diagnostics to the CLI.
  if nargin < 3; verbose = false; end

  disp('Component Selection ...');
  fflush(stdout);
  % NOTE: verbose is currently forced true for diagnostics; set to false for
  % cleaner CLI output in production runs.
  verbose = true;
  evolution_data = select_propulsion_components(evolution_data, db_data, verbose);
  evolution_data = select_power_generation_components(evolution_data, db_data, verbose);
 # evolution_data = select_attitude_control_components(evolution_data, db_data);
 # evolution_data = select_thermal_components(evolution_data, db_data);
 # evolution_data = select_structure_components(evolution_data, db_data);
 # evolution_data = select_communication_components(evolution_data, db_data);
 # evolution_data = select_obc_components(evolution_data, db_data);

  % component_matches are stored on each individual and will be serialized
  % directly into the best-candidates XML by output_XML_best_candidates.

  disp('Component Selection complete');
  disp(' ');
  fflush(stdout);

end
