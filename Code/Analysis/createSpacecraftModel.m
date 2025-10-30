% createSpacecraftModel: Initializes a comprehensive spacecraft model structure
%
% This function sets up a detailed model for a spacecraft, incorporating system-level,
% orbit-level, and subsystem-level data. The resulting structure is organized with 
% specific fields for mass, power, and other key parameters, ensuring a thorough representation 
% of the spacecraft's characteristics. 
%
% Output:
%   - spacecraft: A structured array containing the spacecraft model with initialized fields.
%
% The spacecraft structure includes:
%   - System: Overall system data including total mass and power requirements.
%   - Orbit: Orbit-related data including height, central body, and maneuvers.
%   - Subsystems: Detailed subsystems such as Payload, Telemetry Tracking & Control (TTC),
%     Power Processing System (PPS), Propulsion, Thermal Control System (TCS), Attitude, 
%     Determination and Control (AOCS), Structure Mechanisms, and Others.
%
% Each subsystem is created using the helper function createSubsystem, which initializes
% standard fields for mass and power, and allows for further customization as needed.
%
% Example:
%   spacecraft = createSpacecraftModel();
%   % Further customization and population of the spacecraft structure can be done
%   % based on specific mission requirements and data inputs.
%
% See also: createSubsystem

function spacecraft = createSpacecraftModel()
    % Initialize top-level structure
    spacecraft = struct();
    
    % System-level data
    spacecraft.System = struct();
    spacecraft.System.TotalMass.Value = []; % kg
    spacecraft.System.TotalMass.Requirement = []; % kg, input requirement
    spacecraft.System.TotalMass.Unit = 'kg';

    spacecraft.System.TotalMassDry.Value = []; % kg
    spacecraft.System.TotalMassDry.Requirement = []; % kg, input requirement
    spacecraft.System.TotalMassDry.Unit = 'kg';


    spacecraft.System.TotalPower.Value = []; % Watts
    spacecraft.System.TotalPower.Requirement = []; % Watts, input requirement
    spacecraft.System.TotalPower.Unit = 'Watts';

    spacecraft.System.MarginMass.Value = []; % kg of margin mass of the S/C
    spacecraft.System.MarginMass.Unit = 'kg';

    spacecraft.System.MarginPower.Value = []; % W of margin power of the S/C
    spacecraft.System.MarginPower.Unit = 'W';

    % Orbit data
    spacecraft.Orbit = struct();
    spacecraft.Orbit.OrbitHeight.Value = []; % km
    spacecraft.Orbit.OrbitHeight.MinRequirement = []; % km, minimum input requirement
    spacecraft.Orbit.OrbitHeight.Requirement = []; % km, set input requirement
    spacecraft.Orbit.OrbitHeight.MaxRequirement = []; % km, maximum input requirement
    spacecraft.Orbit.OrbitHeight.Unit = 'km';
    spacecraft.Orbit.CentralBody = ''; % e.g., 'Earth', 'Mars', 'Sun'

    % Orbit Maneuvers data
    spacecraft.Orbit.Maneuvers = struct();
    spacecraft.Orbit.Maneuvers.Thrust.Value = {}; % N, thrust of the spacecraft's engines
    spacecraft.Orbit.Maneuvers.Thrust.Requirement = {}; % N, thrust requirement
    spacecraft.Orbit.Maneuvers.Thrust.Unit = 'N'; % Unit for thrust

    spacecraft.Orbit.Maneuvers.SpecificImpulse.Value = {}; % s, specific impulse (c_e)
    spacecraft.Orbit.Maneuvers.SpecificImpulse.Requirement = {}; % s, specific impulse requirement
    spacecraft.Orbit.Maneuvers.SpecificImpulse.Unit = 's'; % Unit for specific impulse

    spacecraft.Orbit.Maneuvers.Duration.Value = {}; % s, duration of the maneuver
    spacecraft.Orbit.Maneuvers.Duration.Requirement = {}; % s, duration requirement
    spacecraft.Orbit.Maneuvers.Duration.Unit = 's'; % Unit for duration

    spacecraft.Orbit.Maneuvers.DeltaV.Value = {}; % m/s, delta-v of the maneuver
    spacecraft.Orbit.Maneuvers.DeltaV.Requirement = {}; % m/s, delta-v requirement
    spacecraft.Orbit.Maneuvers.DeltaV.Unit = 'm/s'; % Unit for delta-v

    % Mission data

    spacecraft.Mission.MissionDuration.Value = {};              % a, duration of the mission
    spacecraft.Mission.MissionDuration.Requirement = {};        % a, requirement for duration of the mission
    spacecraft.Mission.MissionDuration.Unit = 'years';          % Unit for mission duration 
    % Subsystem-level data
    spacecraft.Subsystems = struct();
    spacecraft.Subsystems.Payload = createSubsystem('Payload');
    spacecraft.Subsystems.TTC = createSubsystem('Telemetry Tracking & Control');
    spacecraft.Subsystems.PPS = createSubsystem('Power Processing System');
    spacecraft.Subsystems.Propulsion = createSubsystem('Propulsion');
    spacecraft.Subsystems.TCS = createSubsystem('Thermal Control System');
    spacecraft.Subsystems.AOCS = createSubsystem('Attitude, Determination and Control');
    spacecraft.Subsystems.OBC = createSubsystem('On-board Computer');
    spacecraft.Subsystems.StructureMechanisms = createSubsystem('Structure Mechanisms');
    spacecraft.Subsystems.Other = createSubsystem('Other');

    % Display the final structure
    disp(spacecraft)
end

% createSubsystem: Initializes an empty subsystem structure
%
% This helper function creates a template for a subsystem, including fields
% for mass and power. Each subsystem can be further customized
% with specific requirements and values as needed.

function subsystem = createSubsystem(name)
    subsystem = struct();
    subsystem.Name = name;
    subsystem.Mass.Value = []; % kg, mass value
    subsystem.Mass.Requirement = []; % kg, input requirement
    subsystem.Mass.Margin = []; % kg, mass margin
    subsystem.Mass.Unit = 'kg';
    subsystem.Power.Value = []; % W, power value
    subsystem.Power.Requirement = []; % W, input requirement
    subsystem.Power.Margin = []; % W, power margin
    subsystem.Power.Unit = 'W';
    subsystem.Components = struct(); % Subsystem components appedned during runtime
    subsystem.Properties = struct(); % Subsystem properties appended during runtime
end
