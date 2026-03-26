% select_components  — Component matching for optimal design solutions
%
% Orchestrates per-subsystem component selection across all best-solution
% individuals in evolution_data.  Each subsystem selector scans the reference
% database for real hardware components compatible with the design point and
% appends its results to individual.component_matches.<subsystem>.
%
% Subsystems handled:
%   propulsion_system  — thrusters (technology type, propellant, thrust, c_e, power)
%   power_generation   — solar panels & batteries (power, energy capacity)
%   attitude_control   — actuators / magnetorquers / reaction wheels (mass, power)
%   thermal            — heaters / passive elements (mass, power)
%   structure          — bus structures (mass)
%   communication      — transceivers / laser links (mass, power)
%   onboard_computer   — OBC boards (mass, power)
%
% Parameters:
%   evolution_data : cell array returned by evolver (best-per-lineage snapshot)
%   db_data        : database struct as loaded by input_processing
%   config         : configuration struct (simulation parameters)
%   runID          : run identifier (used for output path)
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
%         + subsystem-specific performance fields

function evolution_data = select_components(evolution_data, db_data, verbose)
  % verbose (optional, default false): set to true to print per-individual
  % propulsion selection diagnostics to the CLI.
  if nargin < 3; verbose = false; end

  disp('Component Selection ...');
  fflush(stdout);
  verbose = true;
  evolution_data = select_propulsion_components(evolution_data, db_data, verbose);
 # evolution_data = select_power_generation_components(evolution_data, db_data);
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
