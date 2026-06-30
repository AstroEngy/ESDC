% input_processing — Load and pre-process all ESDC input data
%
% PURPOSE:
%   Reads the three input sources (simulation config, mission parameters,
%   hardware database + DOF), then derives any missing mass/power values by
%   applying SMAD statistical scaling laws and initialises the orbit model.
%   Returns the three data structures needed by the evolver.
%
% INTENT:
%   Centralises all I/O and pre-processing so the evolver receives complete,
%   consistent data structs regardless of which subset of parameters the user
%   provided.  The "adaptive input pre-processing" step makes ESDC robust to
%   partially-specified inputs — users need only supply the parameters they
%   know (total mass, or payload mass, or total power) and the rest are
%   estimated from historical spacecraft statistics (SMAD).
%
% Parameters:  none
% Returns:
%   mission_parameters   (struct): Input case(s) with mission constraints.
%       .Satellite_parameters.input_case{i}: per-case struct containing at
%       least .derived (estimated masses/powers/sc_type) and .orbit (orbit
%       timing parameters).
%   database             (struct): Hardware reference data and scaling lookup
%       tables.  .reference_data holds component catalogues; .DOF holds the
%       mutation space definition.
%   simulation_parameters (struct): Solver configuration (see
%       read_input_simulation_parameter for full field list).
%
% Usage:
%   [input, db_data, config] = input_processing()
%
% HOW TO TEST:
%   1. Call with the default input files and verify that all three returned
%      structs are non-empty and that input.Satellite_parameters.input_case
%      contains at least one cell with a .derived.sc_type field (1–4).
%   2. Provide a minimal input (mass_total only) and verify that all
%      subsystem mass and power fields are populated in .derived.
%   3. Provide payload mass only (no mass_total) and confirm mass_total
%      is estimated via the payload-fraction SMAD path.
%   4. Provide inconsistent inputs (e.g. mass_total AND mass_payload > mass_total)
%      and verify a warning or error is raised.
%   5. Test with orbit_height specified vs omitted and confirm that
%      .orbit.orbit.height is set to the supplied or default value.
%
% SAFEGUARDS TO ADD (future work):
%   - Validate that derived.mass_total > 0 and is not NaN before returning.
%   - Check that at least one of mass_total, mass_payload, power_total is
%     provided in each input case; raise a clear error otherwise.
%   - Confirm that sc_type is in {1,2,3,4} after determination.
function [mission_parameters database simulation_parameters]= input_processing()

 % ---- Step 1: Read simulation settings first (provides prefer_xml flag) ---
    [simulation_parameters] = read_input_simulation_parameter();

    % Extract prefer_xml flag (default false if not set)
    prefer_xml = false;
    if isfield(simulation_parameters, 'Simulation_parameters') && ...
       isfield(simulation_parameters.Simulation_parameters, 'io') && ...
       isfield(simulation_parameters.Simulation_parameters.io, 'prefer_xml')
      prefer_xml = logical(simulation_parameters.Simulation_parameters.io.prefer_xml);
    end
    if prefer_xml
      disp('IO mode: XML preferred (YAML used as fallback)');
    end

    % ---- Step 2: Read mission design constraints ----------------------------
    [mission_parameters] =  read_input_mission_parameter(prefer_xml);

    % ---- Step 3: Read hardware reference database and DOF ------------------
    [database]    =  read_reference_data(prefer_xml);
    database.DOF  =  read_DOF(prefer_xml);

    disp(' ')
    disp('Input Reading complete')
    disp(' ')

    disp('Adaptive Input Preprocessing')
    disp(' ')

    % ---- Step 4: Derive missing parameters for each input case -------------
    % system_completion_estimation fills in any subsystem masses and powers
    % that were not directly provided, using SMAD statistical fractions.
    % orbit_initialize computes orbit timing from height or sc_type default.
    %
    % TODO: extend loop to handle multiple cases in one simulation run.
    input_cases = mission_parameters.Satellite_parameters.input_case;
    for i= 1:size(input_cases,2)
      mission_parameters.Satellite_parameters.input_case{i}(1,1).derived = system_completion_estimation(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
      mission_parameters.Satellite_parameters.input_case{i}(1,1).orbit = orbit_initialize(mission_parameters.Satellite_parameters.input_case{i}(1,1), simulation_parameters);
    end

end

% system_completion_estimation — Estimate missing subsystem masses and powers
%
% PURPOSE:
%   Given whatever subset of mass/power fields the user provided, derives
%   all remaining values using SMAD statistical fractions for the spacecraft
%   type.  Supports three input modes:
%     a) mass_total known  → scale all subsystem masses and powers from it.
%     b) power_total known → infer mass_total first, then scale masses.
%     c) neither total known → infer totals from the known partial budgets.
%
% INTENT:
%   Allows the tool to work with any level of design detail.  A user who
%   knows only payload mass can still produce a complete spacecraft estimate.
%
% Parameters:
%   inputs (struct): one input_case with optional fields: mass_total,
%          mass_payload, mass_propulsion, power_total, power_payload, etc.
%   sim    (struct): simulation_parameters, provides margin and sc_type
%          thresholds.
%
% Returns:
%   derived_parameters (struct): .known, .unknown (mass/power sub-structs),
%          .sc_type (integer 1–4).
%
% HOW TO TEST:
%   1. Supply only mass_total=1000; verify all subsystem masses sum to ~1000.
%   2. Supply only mass_payload=200; verify mass_total is estimated and > 200.
%   3. Supply only power_total=5000; verify mass_total is derived from power.
%   4. Supply no fields at all; confirm the 'Insufficient knowns' error fires.
function [derived_parameters]   = system_completion_estimation(inputs, sim)
  derived_parameters = struct;

  % ---- Define the expected mass and power field names ----------------------
  % These match the field names in the input XML/YAML files.
  % If a field is present in inputs it is "known"; otherwise it is "unknown"
  % and will be estimated by SMAD scaling.
  %Available mass fields          %may or may not be defineable in external file
  masses = {
  'mass_total'
  %'mass_propellant'
  'mass_payload'
  'mass_structmech'
  'mass_thermal'
  'mass_power'
  'mass_TTC'
  'mass_ADC'
  'mass_propulsion'
  'mass_other'
  };
  
  %Available power fields
  powers = {
  'power_total'
  'power_payload'
  'power_structmech'
  'power_thermal'
  'power_power'
  'power_TTC'
  'power_ADC'
  'propulsion_power'
  };
  
  % Create structures for known and unknown data
  known = struct();
  unknown = struct();
  
  % ---- Classify inputs into known/unknown structs --------------------------
  % Make structures for known and unknown inputs masses
  for i=1:numel(masses)
    if isfield(inputs,cellstr(masses{i}))
      known.mass.(masses{i})=inputs.(masses{i});
    else
      unknown.mass.(masses{i})=0;
    end
  endfor
  
  % Make structure for known and unknown input powers
  for i=1:numel(powers)
    if isfield(inputs,cellstr(powers{i}))
      known.power.(powers{i})=inputs.(powers{i});
    else
      unknown.power.(powers{i})=0;
    end
  endfor

   %disp(known)
  
% spacecraft type derivation — priority: explicit sc_type > orbit_height > delta_v
  sc_data = struct();
  if isfield(inputs, 'sc_type')
    sc_data.sc_type = inputs.sc_type;
  end
  if isfield(inputs, 'orbit_height') && inputs.orbit_height > 0
    sc_data.orbit_height = inputs.orbit_height;
  end
  if isfield(inputs, 'deltav')
    sc_data.dv = inputs.deltav;
  end
  sc_thresholds = struct();
  if isstruct(sim) && isfield(sim, 'Simulation_parameters') ...
      && isfield(sim.Simulation_parameters, 'defaults') ...
      && isfield(sim.Simulation_parameters.defaults, 'sc_type_thresholds')
    sc_thresholds = sim.Simulation_parameters.defaults.sc_type_thresholds;
  end
  sc_type = determine_sc_type(sc_data, sc_thresholds);
  derived_parameters.sc_type= sc_type;
  
  %if no knowns, nothing to do
  if not(isfield(known,'power')) && not(isfield(known,'mass'))
    disp(' ')
    disp('If anything would be known - yeah - that d great');
    disp('Define at least one system or mass - quitting ESDC');
    error('Insufficient knowns');
  endif
  
  margin = 0.3; %TODO config parameter
  
  if isfield(known,'mass') && isfield(known.mass,'mass_total')
    [known unknown]  = system_with_known_mass_total(known, unknown, margin, sc_type);
  elseif isfield(known,'power') &&isfield(known.power,'power_total')
    [known unknown] = system_with_known_totalpower(known, unknown, margin, sc_type);
  elseif isfield(unknown.mass,'mass_total') && isfield(unknown.power,'power_total')
    [known unknown] = system_with_unknown_totals(known, unknown, margin, sc_type);
  endif
  
  %disp(unknown);
  %disp(known);
  
  derived_parameters.known = known;
  derived_parameters.unknown = unknown;
endfunction

% system_with_unknown_totals — Estimate totals and all subsystems from partial mass/power knowns
%
% PURPOSE:
%   When neither mass_total nor power_total is specified, but some subsystem
%   masses are known, use inverse-fraction SMAD scaling to back-calculate
%   the total spacecraft mass from the known subsystems, then forward-scale
%   all unknowns.
%
% Parameters:
%   known   (struct): .mass and/or .power fields that were explicitly given.
%   unknown (struct): .mass and .power fields to be estimated.
%   margin  (float):  Design margin fraction (e.g. 0.3 for 30%).
%   sc_type (int):    Spacecraft class 1–4 (determines SMAD fraction table).
%
% Returns: updated [known, unknown] structs.
function [known unknown]        = system_with_unknown_totals(known, unknown, margin, sc_type)
  %known processing

  if isfield(known,'mass')
    unknown_parameters = fieldnames(unknown.mass);
    known_parameters = fieldnames(known.mass);
    
    all_known_masses = 0;
    fracs = [];
    for i=1:numel(known_parameters)
    fracs = [fracs scale_SMAD_parameter_inverse_fraction(known.mass.(known_parameters{i}), sc_type, 'mass_total',strcat('fraction_', known_parameters{i}))];
    all_known_masses = all_known_masses +known.mass.(known_parameters{i});
    end
    
    all_known_fractions = sum(fracs);
    
    %get mass estimates 
    unknown.mass.mass_total_margin = all_known_masses/all_known_fractions;
    unknown.mass.mass_total = unknown.mass.mass_total_margin/(1-margin);
    unknown.mass.m_margin = unknown.mass.mass_total-unknown.mass.mass_total_margin;
    
    %get all system estimates
    for i=1:numel(unknown_parameters)
      if not(strcmp(unknown_parameters{i},'mass_total'))
        unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*unknown.mass.mass_total_margin;
      endif
    endfor
    
    unknown_parameters = fieldnames(unknown.power);
    %get all system powerset
    power_tot_relevant = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total','power_total');

    for i=1:numel(fieldnames(unknown.power))
        if not(strcmp(unknown_parameters{i},'power_total'))
        unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*power_tot_relevant;
        end
    endfor
    
    %restablish sum of total power
    new_power_tot = sum_powers(known.power, unknown.power);
    
     %update total power
    if isfield(unknown.power, 'power_total')
      unknown.power.power_total = new_power_tot;
    elseif isfield(known.power, 'power_total')
      if new_power_tot >  known.power.power_total
        disp('')
        disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
        disp('')
        known.power.power_total = new_power_tot;
      else 
        known.power.p_margin = known.power.power_total-new_power_tot;
        known.power.power_total_margin = new_power_tot;
      end
    end
    unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, 'power_total','fraction_mass_power')*unknown.mass.mass_total_margin;
    
    [unknown.mass.mass_total unknown.mass.m_margin unknown.mass.mass_total_margin] = mass_validate(known.mass, unknown.mass, false);  % no warning: total was derived, not user-given
  else
    % go from powers to total power to total mass to masses  
    
    unknown_parameters = fieldnames(unknown.power);
    known_parameters = fieldnames(known.power);
    
    all_known_powers = 0;
    fracs = [];
    for i=1:numel(known_parameters)
    fracs = [fracs scale_SMAD_parameter_inverse_fraction(known.power.(known_parameters{i}), sc_type, 'power_total',strcat('fraction_', known_parameters{i}))];
    all_known_powers = all_known_powers +known.power.(known_parameters{i});
    end
    
    all_known_fractions = sum(fracs);
    
    unknown.power.power_total = all_known_powers/(all_known_fractions);
    
    unknown_parameters = fieldnames(unknown.power);
    for i=1:numel(fieldnames(unknown.power))
        if not(strcmp(unknown_parameters{i},'power_total'))
        unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.power.power_total, sc_type, 'power_total',strcat('fraction_',unknown_parameters{i}))*unknown.power.power_total;
        end   
    endfor
    
    new_power_tot = sum_powers(known.power, unknown.power);
    
    if new_power_tot >  unknown.power.power_total
        disp('')
        disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
        disp('')
        unknown.power.power_total = new_power_tot;
        unknown.power.p_margin = 0;
        unknown.power.power_total_margin = unknown.power.power_total;
      else 
        unknown.power.p_margin = unknown.power.power_total-new_power_tot;
        unknown.power.power_total_margin = new_power_tot;
      end
    
    %do mass total 
      unknown.mass.mass_total= scale_SMAD_parameter(unknown.power.power_total,sc_type,'power_total', 'mass_total');
      unknown_parameters = fieldnames(unknown.mass);
      unknown.mass.m_margin = unknown.mass.mass_total*margin;
      unknown.mass.mass_total_margin = unknown.mass.mass_total-unknown.mass.m_margin;
      
      
     for i=1:numel(unknown_parameters)
      if not(strcmp(unknown_parameters{i},'mass_total'))
       unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*unknown.mass.mass_total_margin;
      endif
     endfor
     
     mass_new=0;
    for i=1:numel(unknown_parameters)
      if not(strcmp(unknown_parameters{i},'mass_total'))
      mass_new = mass_new +unknown.mass.(unknown_parameters{i});
      endif
    endfor
    unknown.mass.mass_total_margin = mass_new;
    unknown.mass.mass_total = unknown.mass.mass_total_margin*(1+margin);
    unknown.mass.m_margin = unknown.mass.mass_total-unknown.mass.mass_total_margin;
    

  end
  % cases for zero known masses and zero known powerset
endfunction 

% scale_SMAD_parameter_inverse_fraction — Invert a SMAD fraction to recover input variable
%
% PURPOSE:
%   Given a known subsystem value (e.g. known payload mass), and the
%   statistical correlation  y = fraction(x) * x  (where x = mass_total),
%   back-calculate x.  Used when only partial budgets are known and the
%   total must be inferred.
%
% Parameters:
%   y              (float):  Known subsystem value.
%   sc_type        (int):    Spacecraft class 1–4.
%   x              (string): Reference parameter name (e.g. 'mass_total').
%   file_parameter (string): Fraction name (e.g. 'fraction_mass_payload').
%
% Returns:
%   fraction (float): The fraction y/x_derived (dimensionless).
function [fraction]             = scale_SMAD_parameter_inverse_fraction(y,sc_type,x, file_parameter)
  % assemble filename
  
  orbits = {'No Propulsion','Low Earth', 'High Earth','Planetary'};
  filename = strcat('Database/Scaling/scaling_spacecraft_',orbits{sc_type},'_parameter_',x,'_to_',file_parameter,'.csv');
  
  if exist(filename)
    data = dlmread(filename,",");
    %disp(data)
  else
    disp(filename);
    error(strcat('ERROR: File not found: ', filename));
  end
  
  frac_vals =data(3,:);
  x_vals = data(4,:);
  
  non_frac_vals = frac_vals.*x_vals;
  
  x_derived= interp1(non_frac_vals,x_vals, y,'linear','extrap');
  fraction= y/x_derived;
endfunction



% system_with_known_totalpower — Estimate total mass and all subsystems from known total power
%
% PURPOSE:
%   When power_total is explicitly provided but mass_total is not, infer
%   mass_total using the SMAD power_total → mass_total correlation, then
%   apply margin and forward-scale all subsystem masses and powers.
%
% Parameters / Returns: same pattern as system_with_known_mass_total.
function [known unknown]        = system_with_known_totalpower(known, unknown, margin, sc_type)               % when only total mass is known, this. % missing case with total
    unknown_parameters = fieldnames(unknown.mass);
    
    % get unknown total mass first % inverse search here from correlation power total to total mass 
    unknown.mass.mass_total =  scale_SMAD_parameter(known.power.power_total, sc_type, 'power_total','mass_total');  % redefine as unknown here
    unknown.mass.m_margin = unknown.mass.mass_total*margin;
    unknown.mass.mass_total_margin = unknown.mass.mass_total- unknown.mass.m_margin;
    
    for i=1:numel(unknown_parameters)
      %known.mass.mass_total
      if not(strcmp(fieldnames(unknown.mass){i},'mass_total'))
        unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*unknown.mass.mass_total_margin;
      end
    endfor
    
    %unknown power estimate handling
    if isfield(unknown,'power')
      unknown_parameters = fieldnames(unknown.power);
      
      % for consistence in power estimates, do not apply a given power total
      power_tot_relevant = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total','power_total');
      
      for i=1:numel(fieldnames(unknown.power))
          if not(strcmp(unknown_parameters{i},'power_total'))
          unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(unknown.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*power_tot_relevant;
          end
      endfor

      %restablish sum of total power
      new_power_tot = sum_powers(known.power, unknown.power);
      
       %update total power
      if isfield(unknown.power, 'power_total')
        unknown.power.power_total = new_power_tot;
      elseif isfield(known.power, 'power_total')
        if new_power_tot >  known.power.power_total
          disp('')
          disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
          disp('')
          known.power.power_total = new_power_tot;
        else 
          known.power.p_margin = known.power.power_total-new_power_tot;
          known.power.power_total_margin = new_power_tot;
        end
      end
    
    %update mass of power system
    unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, 'power_total','fraction_mass_power')*unknown.mass.mass_total_margin;
    end
  
    % total mass check
    [known.mass.mass_total known.mass.m_margin known.mass.mass_total_margin] = mass_validate(known.mass,unknown.mass);
endfunction

% system_with_known_mass_total — Scale all subsystems from a known total mass
%
% PURPOSE:
%   When mass_total is explicitly provided, apply margin, then use SMAD
%   mass fraction tables to estimate all unknown subsystem masses and powers.
%   Known subsystems are preserved; power system mass is updated when the
%   summed power estimate changes.
%
% Parameters / Returns: see system_with_unknown_totals.
function [known unknown]        = system_with_known_mass_total(known, unknown, margin, sc_type)                % when only total mass is known, this. % missing case with total power?
  
    if isfield(unknown,'mass')
      %disp(unknown)
      unknown_parameters = fieldnames(unknown.mass);
      
      known.mass.m_margin = known.mass.mass_total*margin;
      known.mass.mass_total_margin = known.mass.mass_total- known.mass.m_margin;
      
      for i=1:numel(fieldnames(unknown.mass))
        %known.mass.mass_total
        unknown.mass.(unknown_parameters{i}) = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*known.mass.mass_total_margin;
      endfor
    end 
    
    
    %power handling
    if isfield(unknown,'power')
      unknown_parameters = fieldnames(unknown.power);
      
      % for consistence in power estimates, do not apply a given power total
      power_tot_relevant = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total','power_total');
      
      for i=1:numel(fieldnames(unknown.power))
          if not(strcmp(unknown_parameters{i},'power_total'))
            unknown.power.(unknown_parameters{i}) = scale_SMAD_parameter(known.mass.mass_total_margin, sc_type, 'mass_total',strcat('fraction_',unknown_parameters{i}))*power_tot_relevant;
          end
      endfor

      %restablish sum of total power
      if isfield(known,'power')
        new_power_tot = sum_powers(known.power, unknown.power);
      else
        standin.variable.name = 0
        new_power_tot = sum_powers(standin.variable, unknown.power);
      endif

    
    
       %update total power
      if isfield(unknown.power, 'power_total')
        unknown.power.power_total = new_power_tot;
      elseif isfield(known.power, 'power_total')
        if new_power_tot >  known.power.power_total
          disp('')
          disp((strcat('Info: Total power estimate increased to',{' '}, num2str(new_power_tot), ' W')){1});
          disp('')
          known.power.power_total = new_power_tot;
        else 
          known.power.p_margin = known.power.power_total-new_power_tot;
          known.power.power_total_margin = new_power_tot;
        end
      end
      
      %update mass of power system
      unknown.mass.mass_power = scale_SMAD_parameter(new_power_tot, sc_type, 'power_total','fraction_mass_power')*known.mass.mass_total;
    end
    % total mass check
    if isfield(unknown,'mass')
      [known.mass.mass_total known.mass.m_margin known.mass.mass_total_margin] = mass_validate(known.mass, unknown.mass);
    end
endfunction

% sum_powers — Sum all non-total power fields from known and unknown structs
%
% PURPOSE:
%   Adds up every individual subsystem power (excluding the 'power_total'
%   field itself) across both known and unknown power structs.  Used to
%   recompute power_total after all subsystem powers have been estimated,
%   ensuring internal consistency.
%
% Parameters:
%   p_known   (struct): Power fields that were explicitly given.
%   p_unknown (struct): Power fields that were derived/estimated.
%
% Returns:
%   p_new (float): Sum of all subsystem powers [W], excluding power_total.
function [p_new]   = sum_powers(p_known, p_unknown)                                              % updates: the total system power input fields of known and unknown.power
  
  % case handling if known or unknown power total
    %disp(p_known);
    %disp(p_unknown);
    p_new = 0;
    %add derived system powers
    parameters= fieldnames(p_known);
    for i=1:numel(parameters)
      if not(strcmp(parameters{i},'power_total'))
      p_new = p_new+p_known.(parameters{i});
      end
    end
    
    %add known system powers
    parameters= fieldnames(p_unknown);
    for i=1:numel(parameters)
      if not(strcmp(parameters{i},'power_total'))
        p_new = p_new + p_unknown.(parameters{i});
      end
    end
    
endfunction

% mass_validate — Reconcile subsystem masses against the total mass budget
%
% PURPOSE:
%   Sums all individual subsystem masses from both known and unknown structs
%   and compares the result with the declared mass_total.  Updates margin
%   accordingly.  Warns (optionally) when subsystems exceed the total.
%
% Parameters:
%   m_known           (struct): Mass fields that were explicitly given.
%   m_unknown         (struct): Mass fields that were estimated.
%   warn_if_exceeded  (logical, optional, default true): Print a console
%                     warning when the mass budget is exceeded.
%
% Returns:
%   mass_total        (float): Total system mass [kg].
%   m_margin          (float): Remaining margin mass [kg] (0 if exceeded).
%   mass_total_margin (float): Total mass minus margin [kg].
%
% HOW TO TEST:
%   1. Supply masses that sum to exactly mass_total; verify m_margin = 0.
%   2. Supply masses that sum LESS than mass_total; verify m_margin > 0.
%   3. Supply masses that exceed mass_total; verify m_margin = 0 and
%      mass_total is set to the actual sum (not the original budget).
function [mass_total m_margin mass_total_margin] = mass_validate(m_known, m_unknown, warn_if_exceeded)  % checks the applicable masses of the system, recalculates the available margin
  if nargin < 3; warn_if_exceeded = true; end
  
  m_new = 0;
  % add derived system masses
  parameters= fieldnames(m_unknown);
  for i=1:numel(parameters)
    if not(strcmp(parameters{i},'mass_total') || strcmp(parameters{i},'m_margin') || strcmp(parameters{i},'mass_total_margin'))
      m_new=m_new +m_unknown.(parameters{i});
    endif
  endfor

  % add known system masses
  parameters= fieldnames(m_known);
  for i=1:numel(parameters)
    if not(strcmp(parameters{i},'mass_total') || strcmp(parameters{i},'m_margin') || strcmp(parameters{i},'mass_total_margin'))
      m_new=m_new +m_known.(parameters{i});
    endif
  endfor

  if isfield(m_unknown, 'mass_total')
      m_tot         = m_unknown.mass_total;
      m_tot_margin  = m_unknown.mass_total_margin;
      m_margin_old  = m_unknown.m_margin;
  elseif isfield(m_known, 'mass_total')
      m_tot         = m_known.mass_total;
      m_tot_margin  = m_known.mass_total_margin;
      m_margin_old  = m_known.m_margin;
  end
  % compare sum to previous margin sum

  diff_m = m_tot_margin - m_new;
  
  %new residual margin mass 
  m_margin = m_margin_old + diff_m;
  mass_total_margin = m_tot - m_margin; 

  if (m_new > m_tot || m_margin < 0)
    if warn_if_exceeded
      disp('Warning: Total mass limit exceeded!');
    end
    mass_total = m_new;
    m_margin = 0;
  else
    mass_total = m_tot;
  endif

endfunction


% orbit_initialize — Compute orbital timing parameters for the input case
%
% PURPOSE:
%   Given the mission input, determines the orbit height (from the input
%   directly or from sc_type defaults) and calls orbit_parameters_Earth()
%   to compute orbit period, sun/shadow time fractions and other timing
%   data needed by the power system analysis.
%
% Parameters:
%   mission_inputs (struct): one input_case, may contain .orbit_height [km].
%   sim            (struct): simulation_parameters with defaults.orbit.*
%
% Returns:
%   mission_parameters (struct): .orbit field containing the orbit timing
%       struct from orbit_parameters_Earth().
%
% HOW TO TEST:
%   1. Provide orbit_height=500 (LEO); confirm orbit period ≈ 5675 s.
%   2. Omit orbit_height with sc_type=2 (LEO); confirm default LEO height
%      is used from sim.Simulation_parameters.defaults.orbit.Low_Earth.
%   3. Provide orbit_height below orbit_min; confirm orbit_min is used.
function [mission_parameters] = orbit_initialize(mission_inputs, sim)
  mission_parameters = struct;
  if isfield(mission_inputs,'orbit_height')                                                                  % case for given orbit height
    if (mission_inputs.orbit_height > sim.Simulation_parameters.defaults.orbit_min)                           % compare if min is correct
      height = mission_inputs.orbit_height;
    else
      % Clamp to minimum allowed orbit height (from simulation defaults)
      height = sim.Simulation_parameters.defaults.orbit_min;
    end
    mission_parameters.orbit =  orbit_parameters_Earth(height);
  else                                                                                                      % case for unknown orbit height, but use default from orbit type (no prop, LEO, GEO, probe)
    % Select default orbit height based on sc_type classification
    if mission_inputs.derived.sc_type == 1
      height = sim.Simulation_parameters.defaults.orbit.no_propulsion;
    elseif mission_inputs.derived.sc_type == 2
      height = sim.Simulation_parameters.defaults.orbit.Low_Earth;
    elseif mission_inputs.derived.sc_type == 3
      height = sim.Simulation_parameters.defaults.orbit.High_Earth;
    else
      height = sim.Simulation_parameters.defaults.orbit_min;
    end           
    mission_parameters.orbit =  orbit_parameters_Earth(height);    % missing case for space probe
  end
  %disp(height)
  %disp(mission_parameters)
  % if not, do estimate by orbit type bla 
  
endfunction
