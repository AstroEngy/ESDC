# ESDC User Documentation

## 1. Overview

### What is ESDC?

The **Evolutionary System Design Converger (ESDC)** is a holistic spacecraft mission and system design automation tool developed to accelerate Phase 0/A feasibility studies. It combines heuristic-based algorithms with evolutionary optimization to explore vast design spaces and identify optimal spacecraft configurations.

**Key capability:** ESDC automatically designs spacecraft propulsion, power, thermal, and structural subsystems across a wide range of mission scenarios, handling the complex interdependencies that typically make early-phase design challenging.

### Who Should Use This Tool?

- **Mission designers** conducting Phase 0/A preliminary feasibility studies
- **System engineers** exploring trade-space for spacecraft concepts
- **Propulsion specialists** evaluating technology selection for various mission profiles
- **Students and researchers** studying spacecraft design optimization

### Primary Inputs & Outputs

**Input:** A single spacecraft mission case specifying orbital parameters, delta-v budget, power availability, and mission duration.

**Output:** 
- Optimized spacecraft design (mass budget, component selection)
- Subsystem performance parameters (thrust, power, thermal)
- Trade-space visualizations (mass margin vs. propellant, performance metrics)
- 18 parallel evolutionary lineages (seeds) for statistical robustness

---

## 2. Quick Start (5-Minute Guide)

### Running Your First Case

1. **Start Octave** and navigate to the ESDC root directory:
   ```octave
   cd /path/to/ESDC
   pkg load io
   javaaddpath("path/to/xerces/xercesImpl.jar")
   javaaddpath("path/to/xerces/xml-apis.jar")
   ```

2. **Run ESDC with default input:**
   ```octave
   ESDC(1)
   ```
   This creates a simulation run with ID 1, reads from `Input/ESDC_Input.xml`, and generates output in `Output/1/`.

3. **Run ESDC with example configuration:**
   ```octave
   % Edit Code/Input/read_input_mission_parameter.m:
   % Uncomment a specific example path, e.g.:
   % input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_low_mass_high_thrust';
   % Then run:
   ESDC(2)
   ```

4. **Review output:**
   - Best candidates: `Output/2/ESDC_best_candidates.xml`
   - Convergence history: `Output/2/ESDC_evolution_history.xml`
   - Execution log: `Output/2/ESDC_tool.log`

---

## 3. Installation & Environment Setup

### System Requirements

| Component | Requirement |
|-----------|-------------|
| **OS** | Windows, macOS, or Linux |
| **Octave** | v8.2 or higher |
| **Java** | Java Runtime Environment (JRE) 8+, on system PATH |
| **Octave IO package** | Required for XML parsing |
| **Xerces library** | Apache Xerces Java 2.12.2 (.jar files) |

### Complete Setup Steps

#### 1. Install GNU Octave
   - Download from [octave.org](https://www.gnu.org/software/octave/download.html)
   - Verify installation:
     ```octave
     octave --version
     ```

#### 2. Install and Load Octave IO Package
   ```octave
   pkg install -forge io
   pkg load io
   ```
   (Add `pkg load io` to your `.octave.rc` file to auto-load on startup)

#### 3. Install and Configure Xerces
   - Download **Xerces2 Java 2.12.2** from [Apache](https://xerces.apache.org/mirrors.cgi)
   - Extract to a convenient directory (e.g., `C:\xerces` or `~/xerces`)
   - Add to Octave (Windows example, adjust path accordingly):
     ```octave
     javaaddpath("C:\\xerces\\xercesImpl.jar");
     javaaddpath("C:\\xerces\\xml-apis.jar");
     ```
   - Add these lines to `.octave.rc` for automatic loading

#### 4. Clone/Download ESDC Repository
   ```bash
   git clone https://github.com/aerospaceresearch/ESDC.git
   cd ESDC
   ```

---

## 4. Core Concepts

### Spacecraft Classification (Spacraft Type)

ESDC automatically classifies spacecraft into four types based on orbital parameters and mission delta-v. This classification drives default mission durations and propulsion system selection.

| **Type** | **Classification** | **Altitude Range** | **Δv Threshold** | **Default Mission Duration** | **Typical Example** |
|----------|------------------|--------------------|------------------|-----------------------------|-------------------|
| **1** | No Propulsion | Passive (natural decay) | < 30 m/s | 3 years | Nanosatellite, passive drag or collision avoidance only |
| **2** | Low Earth Orbit (LEO) | < 2,000 km | ≤ 2,000 m/s | 5 years | ISS resupply, Starlink constellation, altitude maintenance |
| **3** | High Earth / GEO | 2,000–45,000 km | 2,000–4,300 m/s | 15 years | GEO comsats, inclination change, station-keeping |
| **4** | Planetary / Deep Space | Beyond Earth | > 4,300 m/s | 10 years | Mars rover, Lunar lander, outer planet probe |

**Priority chain:** Spacecraft type is determined by:
1. Explicit `sc_type` parameter (if provided)
2. `orbit_height` inference (LEO vs. High orbit)
3. `deltav` inference (GEO vs. Planetary)

### Evolutionary Algorithm Basics

ESDC uses a **population-based evolutionary algorithm** to explore the design trade space:

- **Population size:** 18 independent lineages (seeds)
- **Mutation operators:** Random changes to propulsion type, propellant, thrust, c_e (specific impulse)
- **Fitness criterion:** Maximize spacecraft mass margin (≈ available budget for contingencies)
- **Hard constraints:** Propulsion system must satisfy minimum thrust requirement from maneuver duration
- **Convergence:** Lineage stops evolving once no fitness improvement occurs for 10+ generations

### Thrust Minimum Constraint

The evolver enforces a hard constraint: evolved spacecraft must deliver enough thrust to complete the required delta-v burn within a user-specified time window. This constraint is critical for avoiding unrealistic EP-only designs for tight-burn-window missions.

**Formula:** `thrust_min = m_propellant * c_e / t_burn_max`

**Example:** For a 4,000 kg spacecraft with Δv=200 m/s and 72-hour burn-window:
- **thrust_min ≈ 11 N**
- Electric propulsion (max ~0.3 N for 5 kW HET) → hard-rejected
- Chemical propulsion (9–200 N range) → only technology that passes

---

## 5. Input Parameters: Complete Reference

### How to Provide Input

ESDC reads spacecraft and mission parameters from an XML file. You can:

1. **Use the default input file:** `Input/ESDC_Input.xml`
2. **Use a pre-built example:** (see Section 6)
3. **Create a custom input:** Copy an existing file and modify parameters

### Input File Structure

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Satellite_parameters>
  <input_case dcep_show="False">
    <!-- Define your mission case here -->
    <orbit_height>500</orbit_height>
    <mass_total>4000</mass_total>
    <!-- ... more parameters ... -->
  </input_case>
  <!-- Additional cases can be stacked; ESDC runs each sequentially -->
</Satellite_parameters>
```

### Parameters: Detailed Reference

#### **Orbit Definition** (Choose ONE)

| Parameter | Type | Unit | Default | Range | Description |
|-----------|------|------|---------|-------|-------------|
| `orbit_height` | float | km | 350 | 350–45,000 | Orbital altitude above Earth surface. Drives spacecraft type classification via LEO boundary (2,000 km). |
| `deltav` | float | m/s | — | 10–20,000 | Total mission delta-v budget (orbit insertion, inclination, station-keeping, deorbit). If provided WITHOUT `orbit_height`, used to infer spacecraft type. |
| `sc_type` | integer | — | *inferred* | 1, 2, 3, 4 | Explicit spacecraft type. Overrides all inference chains (highest priority). |

**Notes:**
- Provide EITHER `orbit_height` OR infer from `deltav`; providing both uses orbit-based classification
- LEO boundary: 2,000 km; GEO/HEO boundary: ~35,786 km

#### **Spacecraft Mass (Wet Mass)**

| Parameter | Type | Unit | Default | Range | Notes |
|-----------|------|------|---------|-------|-------|
| `mass_total` | float | kg | 155–4,000 | 25–16,221 | Total spacecraft mass including propellant. SMAD scalings assume total mass ≥ 25 kg (CubeSat+) and ≤ 16,221 kg (large GEO). |

**Typical values by spacecraft type:**
- **sc_type 1 (No Propulsion):** 3,100–8,900 kg
- **sc_type 2 (LEO):** 4,000–12,000 kg  
- **sc_type 3 (HEO/GEO):** 1,800–4,400 kg
- **sc_type 4 (Planetary):** 1,700–4,300 kg

#### **Power Budget**

| Parameter | Type | Unit | Default | Range | Notes |
|-----------|------|------|---------|-------|-------|
| `propulsion_power` | float | W | ~200–20,000 | 100–100,000 | Electrical power available for propulsion subsystem. Higher power enables higher thrust via electric thrusters (HET, ion, arcjet). |

**Guidance:**
- **Low EP (continuous station-keeping):** 1,000–4,000 W/spacecraft
- **High thrust (chemical or high-power EP):** 5,000–20,000 W
- **No propulsion (sc_type=1):** Typically 50–500 W (minimal thrusting)

#### **Mission Duration & Burn-Time Constraint**

| Parameter | Type | Unit | Default | Range | Notes |
|-----------|------|------|---------|-------|-------|
| `mission_duration` | float | years | *sc_type-dependent* | 1–30 | Total spacecraft operational lifetime. Used with `propulsion_time_fraction` to derive maximum burn time and thus `thrust_min`. |
| `propulsion_time_fraction` | float | — | 0.10 | 0.01–0.50 | Fraction of mission duration available for propulsion burns. Default (10%) based on SMAD 2011 station-keeping studies. 1%=aggressive burn window. |
| `maneuver_duration_max` | float | s | *derived* | 100–86,400 | Maximum *single* burn duration [seconds]. Takes **priority** over `propulsion_time_fraction` if both are provided. Used for missions with time-constrained maneuvers (e.g. collision avoidance, lunar orbit insertion). |

**Examples:**
- **5-year mission, 10% EP duty:** `mission_duration=5`, `propulsion_time_fraction=0.10` → `t_burn_max ≈ 15.8 million seconds`
- **20-hour burn limit:** `maneuver_duration_max=72000` → `thrust_min` must be high enough to complete Δv in 20 hours

#### **Technology Preference (Optional)**

| Parameter | Type | Unit | Default | Values | Purpose |
|-----------|------|------|---------|--------|---------|
| `thrust_mode` | string | — | "any" | "any", "high", "low" | Constrain propulsion technology selection. "high"=chemical/HET/arcjet, "low"=gridded-ion/FEEP/electrospray. Useful for mission-specific requirements. |

**Technology ranges:**
- **"high":** Chemical (0.5–200 N), HET (0.03–0.3 N @ 5 kW), arcjet (0.04–3.3 N)
- **"low":** Gridded-ion (1–10 mN), FEEP (µN range), electrospray (40–200 µN)

#### **Optional Payload / Power Floor Constraints** (Advanced)

| Parameter | Type | Unit | Default | Notes |
|-----------|------|------|---------|-------|
| `mass_payload` | float | kg | *free* | If specified, evolver rejects designs where payload mass falls below this limit. |
| `power_payload` | float | W | *free* | If specified, ensures minimum power available for non-propulsion systems. |

---

### Default Values Summary Table

| Scenario | `mass_total` | `deltav` | `propulsion_power` | `mission_duration` | `propulsion_time_fraction` | Expected Result |
|----------|---------------|----------|-------------------|-------------------|---------------------------|-----------------|
| **LEO baseline** | 4,000 kg | 200 m/s | 2,000 W | 5 yr | 0.10 | HET or low-thrust EP; 15–20 Mweeks of station-keeping |
| **LEO high-thrust** | 4,000 kg | 400 m/s | 20,000 W | 2 yr | 0.01 | Chemical or high-power HET; rapid orbit insertion/change |
| **GEO baseline** | 3,500 kg | 3,000 m/s | 5,000 W | 15 yr | 0.10 | Bipropellant chemical or resistojet; long station-keeping |
| **CubeSat** | 150 kg | 150 m/s | 100 W | 3 yr | 0.10 | Monopropellant hydrazine or low-power gridded-ion |
| **Lunar mission** | 2,000 kg | 4,500 m/s | 10,000 W | 5 yr | 0.10 | Chemical bipropellant; energy-limited by Lunar gravity |

---

## 6. Example Configurations

ESDC includes **11 pre-built, validated example configurations** demonstrating different spacecraft types and technology choices. All are located in `Documentation/Example Files/Input/` and `Output/`.

### Example Set A: No Propulsion (sc_type=1)

| Example | Input File | Output File | Key Parameters | Technology Selected | Key Result |
|---------|-----------|------------|-----------------|-------------------|-----------|
| **No-Prop Low Mass** | `..._sc1_no_prop_low_mass.xml` | `..._sc1_no_prop_low_mass.xml` | 3,100 kg, 30 m/s, 2,300 W, 3 yr, 10% | *None (passive only)* | Baseline passive CubeSat design; validates constraint handling |
| **No-Prop High Mass** | `..._sc1_no_prop_high_mass.xml` | `..._sc1_no_prop_high_mass.xml` | 8,900 kg, 30 m/s, 1,800 W, 5 yr, 10% | *None (passive only)* | Large passive satellite (e.g., science orbiter on coast); validates scaling |

### Example Set B: LEO High-Thrust (sc_type=2, thrust_mode="high")

| Example | Mass | Δv | Power | Duration | Duty | **Technology** | **Design Thrust** | **Isp** | Notes |
|----------|------|-----|-------|----------|------|-------------|-------------------|--------|-------|
| **LEO Low-Mass High-Thrust** | 4,000 kg | 400 m/s | 20,000 W | 2 yr | 1% | **Hall Thruster (HET)** | 300–1,000 mN | 1,600–1,800 s | Aggressive burns; high-power HET selected |
| **LEO High-Mass High-Thrust** | 12,000 kg | 400 m/s | 60,000 W | 2 yr | 1% | **Chemical or HET** | ~10 N | ~260–1,700 s | Large spacecraft; bipropellant or high-power HET |

### Example Set C: LEO Low-Thrust EP (sc_type=2, thrust_mode="low")

| Example | Mass | Δv | Power | Duration | Duty | **Technology** | **Design Thrust** | **Isp** | Notes |
|----------|------|-----|-------|----------|------|-------------|-------------------|--------|-------|
| **LEO Low-Mass Low-Thrust** | 4,000 kg | 200 m/s | 4,000 W | 7 yr | 15% | **Gridded-Ion or FEEP** | ~100 mN | 2,000–3,500 s | Continuous low-power EP; excellent Isp, low mass margin |
| **LEO High-Mass Low-Thrust** | 12,000 kg | 200 m/s | 12,000 W | 7 yr | 15% | **Gridded-Ion** | ~200–300 mN | 2,500–3,000 s | Large constellation spacecraft; optimized for duty cycles |

### Example Set D: LEO Chemical (sc_type=2, thrust_mode="high" + maneuver_duration_max)

| Example | Mass | Δv | Power | Duration | Constraint | **Technology** | **Design Thrust** | **Isp** | Notes |
|----------|------|-----|-------|----------|-----------|-------------|-------------------|--------|-------|
| **LEO Low-Mass Chemical** | 4,000 kg | 200 m/s | 2,000 W | 5 yr | 20-hr burn | **Chemical (Hydrazine)** | ~91 N | ~220 s | Time-constrained burn forces chemical selection (EP too low thrust). Demonstrates physics-based selection. |

### Example Set E: High Earth Orbit / GEO (sc_type=3)

| Example | Input File | Output File | Mass | Δv | Power | Duration | **Technology** | Notes |
|---------|-----------|------------|------|-----|-------|----------|-------------|-------|
| **HEO Low Mass** | `..._sc3_heo_low_mass.xml` | `..._sc3_heo_low_mass.xml` | 1,800 kg | 3,000 m/s | 18,000 W | 15 yr | Bipropellant chemical or resistojet | Long mission; energy-limited trajectory; low propellant fraction |
| **HEO High Mass** | `..._sc3_heo_high_mass.xml` | `..._sc3_heo_high_mass.xml` | 4,400 kg | 3,000 m/s | 13,000 W | 15 yr | Bipropellant or high-Isp EP | On-station satellites; mature design envelope |

### Example Set F: Planetary / Deep Space (sc_type=4)

| Example | Input File | Output File | Mass | Δv | Power | Duration | **Technology** | Notes |
|---------|-----------|------------|------|-----|-------|----------|-------------|-------|
| **Planetary Low Mass** | `..._sc4_planetary_low_mass.xml` | `..._sc4_planetary_low_mass.xml` | 1,700 kg | 5,000 m/s | 25,000 W | 10 yr | Chemical bipropellant | Lunar lander or Mars orbital insertion; gravity-assist dominates |
| **Planetary High Mass** | `..._sc4_planetary_high_mass.xml` | `..._sc4_planetary_high_mass.xml` | 4,300 kg | 5,000 m/s | 26,000 W | 10 yr | Bipropellant ± orbiting station chemical | Large outer-planet probe; Isp trade-off with mission fuel |

### How to Run Examples

1. **Edit** `Code/Input/read_input_mission_parameter.m` and uncomment the example you want:
   ```octave
   % input_path = 'Documentation/Example Files/Input/ESDC_Input_sc2_leo_low_mass_high_thrust';
   ```

2. **Run ESDC:**
   ```octave
   ESDC(runID)
   ```
   ESDC creates an output directory `Output/runID/` with the optimized design.

3. **Compare with reference output:**
   - Your output: `Output/runID/ESDC_best_candidates.xml`
   - Reference: `Documentation/Example Files/Output/ESDC_Output_sc2_leo_low_mass_high_thrust.xml`
   - Designs should match within 1–2% (evolutionary randomness).

---

## 7. Running the Tool

### Execution Modes

#### **Mode 1: Interactive (Recommended for Single Runs)**

```octave
% Load packages
pkg load io
javaaddpath("C:\\path\\to\\xerces\\xercesImpl.jar");
javaaddpath("C:\\path\\to\\xerces\\xml-apis.jar");

% Run ESDC with a specific run ID
cd /path/to/ESDC
ESDC(runID)
```

**Output:** Run ID 1, 2, 3, etc. create separate output directories `Output/1/`, `Output/2/`, etc.

#### **Mode 2: Batch Processing (For Parameter Studies)**

Create an Octave script `my_study.m`:

```octave
pkg load io
javaaddpath("C:\\path\\to\\xerces\\xercesImpl.jar");
javaaddpath("C:\\path\\to\\xerces\\xml-apis.jar");

% Run a series of cases
for runID = 1:10
  fprintf('Starting run %d...\n', runID);
  ESDC(runID);
  fprintf('Completed run %d\n', runID);
end
```

Run it:
```octave
my_study
```

### Understanding the Execution Flow

1. **Input Processing** (~1 sec)
   - Loads mission parameters from XML file
   - Infers spacecraft type
   - Validates inputs (mass > 0, deltav > 0, etc.)
   - Initializes optimization configuration

2. **Evolutionary Algorithm** (~20–60 sec depending on case complexity)
   - Generates 18 random initial spacecraft designs
   - Runs ~20–100+ generations of mutation/selection
   - Each generation tests 18 designs against fitness criterion
   - Lineages converge when no fitness improvement found

3. **Component Selection** (~5–10 sec)
   - Selects hardware components matching evolved design
   - Performs subsystem mass/power analysis (SMAD scaling)
   - Validates thermal, structural constraints

4. **Output Generation** (~2–5 sec)
   - Writes optimized design to XML
   - Exports evolution history and best candidates
   - Generates performance summary

**Total time:** ~30–80 seconds for a typical case (varies by hardware/search space size)

### Console Output Interpretation

```
Starting Evolution ...
 
Iterated generations: 10
Iterated generations: 20
Iterated generations: 30
...
Component Selection complete
XML Output complete
ESDC complete
Total execution time: 45.23 seconds (0.75 minutes)
```

**What it means:**
- "Iterated generations" = evolver is running normally
- If you see 10s of "Iterated" lines with no convergence → normal (long search)
- "Component Selection complete" = best design found; now matching hardware
- "ESDC complete" = run succeeded; check `Output/runID/` for files

---

## 8. Understanding Outputs

### Output File Structure

```
Output/
  runID/
    ESDC_best_candidates.xml       (Optimal design per input case)
    ESDC_evolution_history.xml     (Full evolution lineage for debugging/analysis)
    ESDC_tool.log                  (Execution log, warnings)
```

### Key Metrics in ESDC_best_candidates.xml

#### **Mass Budget**

```xml
<mass_total>4000.0</mass_total>                      <!-- Entered wet mass -->
<subsystem_masses>
  <mass_propellant>354.1</mass_propellant>          <!-- Propellant burned during mission -->
  <mass_propulsion>120.5</mass_propulsion>          <!-- Thruster + tank + PPU mass -->
  <mass_power>485.3</mass_power>                    <!-- Solar panels + battery -->
  <mass_payload>1200.0</mass_payload>               <!-- User-defined mission payload -->
  <m_margin>1840.2</m_margin>                       <!-- Contingency mass (dry MTTL margin) -->
  <m_dry_nomargin>3000.0</m_dry_nomargin>          <!-- Spacecraft dry mass -->
</subsystem_masses>
```

**Interpretation:**
- **Healthy design:** `m_margin > 15%` of dry mass = ~10% of total mass
- **Tight design:** `m_margin < 5%` = risky, minimal contingency
- **Over-designed:** `m_margin > 40%` = excessive margin, inefficient

#### **Propulsion Performance**

```xml
<propulsion_system>
  <system_type>HET</system_type>                      <!-- Selected technology -->
  <propellant>Xenon</propellant>                      <!-- Propellant choice -->
  <design_thrust>250.0</design_thrust>               <!-- [mN] equivalent thrust -->
  <design_c_e>17500.0</design_c_e>                   <!-- [m/s] specific impulse -->
  <design_propellant_mass>150.5</design_propellant_mass>  <!-- [kg] propellant required -->
</propulsion_system>
```

**Key calculations:**
- **Isp [seconds]** = c_e / g₀ where g₀ = 9.81 m/s²
- **Total impulse** = design_thrust × burn_time = m_prop × c_e
- **Propellant fraction** = m_prop / m_total (check: should be 3–15% for EP, 10–30% for chemical)

#### **Mission Parameters**

```xml
<mission_parameters>
  <thrust_min>10.61</thrust_min>                      <!-- [N] minimum required thrust -->
  <thrust_min_satisfied>1</thrust_min_satisfied>     <!-- Boolean: design meets constraint -->
  <deltav_required>200.0</deltav_required>           <!-- [m/s] user input -->
  <deltav_achievable>202.3</deltav_achievable>       <!-- [m/s] design can deliver -->
</mission_parameters>
```

### Guidance on Interpreting Results

| Metric | Good Range | Concern | Action |
|--------|-----------|---------|--------|
| **m_margin** | 10–40% of dry mass | < 5% | Increase power, mass, or propulsion time budget |
| **Propellant fraction** | 3–10% (EP), 10–30% (Chemical) | > 40% | Reduce Δv requirement or increase total mass |
| **thrust_min_satisfied** | 1 (True) | 0 (False) | Increase `propulsion_power` or `maneuver_duration_max` |
| **Isp match** | Within factor of 1.2 of mission requirement | Deviate > 20% | Check propellant match in DB, increase power |

---

## 9. Limitations

### Physical/Technical Limitations

#### **1. Spacecraft Type Classification**

| Limitation | Impact | Workaround |
|-----------|--------|---------|
| Classification based on altitude & Δv only; no explicit orbit shape (ellipse, polar, etc.) | Equatorial vs. polar orbits have different Δv costs | Specify `deltav` explicitly; provide mission-specific Δv budget |
| Default mission durations are generic; specific missions may differ | May not reflect real deorbit budgets or contingency | Override with `maneuver_duration_max` or adjust `mission_duration` |

#### **2. Propulsion System Coverage**

| Limitation | Technology Gap | Notes |
|-----------|----------------|----|
| Database contains flight-heritage systems only (~40 entries across 8 tech types) | Cutting-edge thrusters (ICP, gridded-ion v2.0, etc.) not included | Data sources: Goebel & Katz 2008, SETS datasheets; periodic updates possible |
| Mixed propellants in DB (H2/N2 mixtures, etc.) may not be available from all vendors | Propellant availability not checked | Specify high-confidence propellants: Xenon (HET), Hydrazine (chemical/mono) |
| LEO-focused (most entries @ 1–5 kW); limited high-power entries | Missions requiring >20 kW may not find optimal designs | Extrapolation possible but with caution; request DB extension |

#### **3. Mass Scaling**

| Limitation | Impact | Notes |
|-----------|--------|-------|
| SMAD scaling valid for 25–16,000 kg spacecraft only | CubeSats <25 kg or giant GEO >16,000 kg may scale incorrectly | Input clamping: minimum 25 kg enforced | 
| Scaling correlations are statistical averages | Individual spacecraft may deviate 20–50% from prediction | Results are estimates for Phase 0/A; detailed design required pre-Phase B |
| Thermal and structural constraints simplified | Real designs need detailed thermal/FEA analysis | Use as feasibility gateway, not final design |

#### **4. Evolutionary Algorithm**

| Limitation | Impact | Mitigation |
|-----------|--------|---------|
| Stochastic search (random mutations) can get stuck in local optima | Different runs may yield different results (± 2–5% margin variation) | 18 seeds + parallel lineages reduce likelihood; re-run if suspicious |
| Convergence depends on search space complexity; tight constraints may cause early stall | Some cases complete in 20 generations; others need 100+ | If convergence is slow (>500 gen), increase `propulsion_time_fraction` to relax `thrust_min` |
| No guaranteed global optimum | Design may not be globally optimal, only locally optimal | For critical missions, run multiple times with different random seeds |

### Scope Limitations

#### **What ESDC Does NOT Model (at the moment)**

- **Attitude determination & control (ADC/ADCS):** Simplified gyro/reaction-wheel mass estimates only
- **Communications (TT&C):** Minimal subsystem sizing; assumes standard transponders
- **Thermal vacuum behavior:** Ground-based scalings; space radiator optimization not detailed
- **Launch vehicle integration:** No launch cost, fit-check, or compatibility analysis
- **Reliability/redundancy:** Single-string designs; no N+1 redundancy synthesis
- **Power generation detail:** Solar cells and batteries selected for availability; not designed from scratch
- **Desorption/off-gassing:** Assumes standard space-qualified components
- **Debris/micrometeorite protection:** Material selection assumes MMOD standard shielding

#### **Suitable Use Cases**

✅ **Good fits:**
- Phase 0/A feasibility studies
- Technology trade studies (chemical vs. EP, different propellants)
- Design-space exploration across missions
- Teaching/learning spacecraft design

❌ **Poor fits:**
- Detailed Phase B/C design
- Final mass budget for procurement
- Precise thermal budget (need detailed analysis)
- Highly specialized missions (Earth-Moon transfers, asteroid deflection, etc.)

---

## 10. Troubleshooting

### Common Issues & Solutions

#### **Issue 1: "ERROR: No input definition file"**

**Symptom:**
```
ERROR: No input definition file: xmlread: couldn't load and parse "Input/ESDC_Input.xml"
```

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Xerces library not loaded | Run `javaaddpath("...xercesImpl.jar"); javaaddpath("...xml-apis.jar");` before ESDC |
| XML file not found / path wrong | Check file exists: verify spelling in `read_input_mission_parameter.m` |
| Malformed XML (syntax error) | Validate XML: use online validator or try `xmlread()` directly in Octave |
| File has non-ASCII characters | Save file as UTF-8 without BOM |

**Debug steps:**
```octave
% Test if xmlread works:
test_struct = xmlread('Input/ESDC_Input.xml');
disp('XML load successful');
```

---

#### **Issue 2: "Thrust_min_satisfied = 0" (design violates burn-time constraint)**

**Symptom:**
```xml
<thrust_min_satisfied>0</thrust_min_satisfied>
```
Design can't deliver required Δv in specified time window.

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| `maneuver_duration_max` too short for low-power EP | Increase `maneuver_duration_max` or switch to `thrust_mode='high'` |
| `propulsion_power` too low for constraint | Increase `propulsion_power` (W) in input |
| `propulsion_time_fraction` too small | Increase fraction (e.g., 0.10 → 0.20) to relax burn-time constraint |
| Database doesn't have thrusters matching the power/Δv combo | Reduce Δv or increase power budget |

**Example fix:**
```xml
<!-- Original (failing) -->
<propulsion_power>500</propulsion_power>
<propulsion_time_fraction>0.01</propulsion_time_fraction>

<!-- Fixed version -->
<propulsion_power>5000</propulsion_power>      <!-- 10× more power -->
<propulsion_time_fraction>0.10</propulsion_time_fraction>  <!-- 10× more time -->
```

---

#### **Issue 3: "Chemical propulsion won't select" or "Always selects HET"** (LEGACY)

**Status:** ✅ **Fixed in recent releases.** This was a known evolver bug affecting seed validation and chemical thrust calculation. Chemical propulsion now selects naturally when appropriate via physics-based thrust constraints.

**Legacy symptom (pre-fix):** Even with `thrust_mode='high'`, the design would select HET/arcjet instead of chemical.

**What was fixed:**
- **Seed validation:** Invalid seeds no longer get artificially inflated mass margins
- **Chemical thrust:** Now computed from DB performance data directly, not via EP formula
- **Convergence:** Lineages that never find valid solutions now stall correctly instead of prolonging search

**If you still encounter this (edge cases):**

| Approach | When to use |
|----------|------------|
| **Add burn-time constraint** | For tight-window missions: specify `maneuver_duration_max` to force chemistry via physics (thrust_min too high for EP to satisfy) |
| **Reduce power budget** | If you want to force propulsion down to low-power regime (e.g., battery-limited missions) |
| **Increase mission duration** | For very relaxed burn windows; allows any technology to compete fairly |

**Worked example:** See **ESDC_Input_sc2_leo_low_mass_chemical.xml** in `Documentation/Example Files/Input/`. Run 130 demonstrates natural chemical selection via physics-based constraint (no workarounds needed).

---

#### **Issue 4: Mass margin = 0 or negative**

**Symptom:**
```xml
<m_margin>0.0</m_margin>  <!-- or negative value -->
```
Spacecraft is over-constrained; power/propulsion/structure budgets exceed total mass.

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Unrealistic input combination (tiny mass, huge Δv, tight burn) | Relax constraints: increase `mass_total` or `propulsion_power` |
| Power budget too low for required delta-v | Increase `propulsion_power` |
| Payload mass floor set too high | Reduce `mass_payload` constraint or increase `mass_total` |

**Validation check:**
```octave
% Rough feasibility check (before running ESDC)
m_prop_min = deltav / c_e_typical  % c_e_typical ~ 2500 m/s for HET
m_dry_min = 0.7 * m_total  % Rough dry-mass fraction
m_margin_estimate = m_total - m_prop_min - m_dry_min
if m_margin_estimate < 0.15 * m_total
  warning('Tight design; large Δv for small spacecraft')
end
```

---

#### **Issue 5: Convergence exceeds expected generations (~100+)**

**Symptom:**
```
Iterated generations: 50
Iterated generations: 75
Iterated generations: 100+
... (continues longer than expected)
```

**Context:** ESDC terminates each lineage after 10+ generations without fitness improvement. Typical cases converge in 20–50 generations total; 100+ is uncommon and indicates a search space issue.

**Causes & Solutions:**

| Cause | Solution |
|-------|----------|
| Constraints are unrealistic (thrust_min impossible to satisfy) | **Most common.** Verify `thrust_min_satisfied=1` in output; if 0, increase `propulsion_power`, `maneuver_duration_max`, or `mission_duration` |
| Extremely loose constraints (huge power budget, tiny Δv) | Many near-equivalent designs compete → flat fitness landscape → slow convergence. Normal behavior; designs are robust. |
| Very tight design space (conflicting mass, power, Δv) | Evolver struggles to find feasible mutations. **Action:** Relax constraints or accept slower run time (still completes) |

**Note:** Lineages WILL converge eventually (within 500 generation limit). This is not a hang; it's just a slow search. Monitor `ESDC_tool.log` in `Output/runID/` for progress messages.

---

#### **Issue 6: Different results on re-run (non-deterministic)**

**Symptom:** Running the same input twice gives slightly different designs (e.g., HET vs. arcjet, or margin 21% vs. 23%).

**Cause:** Evolutionary algorithms use random initialization; different random seeds → different paths through search space.

**Is this a problem?** No, this is normal and expected.

**If you need reproducible results:**
```octave
% Edit ESDC_Simulation_parameters.xml:
<random_seed>42</random_seed>  <!-- Use fixed seed -->
```
Or use Octave's reproducibility:
```octave
rng(42);  % Set global random seed before ESDC(runID)
```

---

### Validation Checklist

Before trusting ESDC output, verify:

- [ ] **Inputs are physically reasonable** (mass > 0, 0 < Δv < 20 km/s, 0 < power < 100 kW)
- [ ] **Spacecraft type classification is correct** (check inferred sc_type matches mission intent)
- [ ] **Propellant_fraction is sensible** (3–15% for EP, 10–30% for chemical—not 0.01% or 70%)
- [ ] **Thrust_min_satisfied = 1** (design can actually deliver Δv in specified time)
- [ ] **Mass margin > 10%** (allows contingency; margin = 0 is red flag)
- [ ] **Isp is in expected range** (HET: 1,500–1,850 s; Ion: 2,500–3,500 s; Chemical: 200–300 s)
- [ ] **Component count is reasonable** (e.g., 1 thruster for CubeSat, 2–4 for large GEO)

---

## 11. Frequently Asked Questions (FAQ)

### **Q: How long does ESDC take to run?**

**A:** Typically **30–80 seconds** per case on modern hardware (2–4 GHz CPU). Factors affecting runtime:
- **Simulation complexity:** Simple cases (low Δv, lots of power) → 30 sec; tight constraints → 60+ sec
- **Hardware:** Older laptops may take 2–3× longer
- **Convergence:** Most cases converge in 20–50 generations; complex cases need 100+

**Tip:** Batch runs (10+ cases) take ~5–10 minutes total; start them before lunch!

---

### **Q: Can I run ESDC on macOS or Linux?**

**A:** Yes! ESDC is OS-agnostic Octave code. The setup is identical except for file paths:

**Windows path example:**
```octave
javaaddpath("C:\\xerces\\xercesImpl.jar");
```

**macOS/Linux path example:**
```octave
javaaddpath("/usr/local/xerces/xercesImpl.jar");
```

All .m files and XML files work on any OS. Some Octave packages may need reinstall per OS, but `pkg install -forge io` handles that.

---

### **Q: What if my spacecraft doesn't fit any of the 4 types (sc_type 1–4)?**

**A:** ESDC uses a conservative classification scheme; you can override it:

```xml
<sc_type>2</sc_type>    <!-- Explicitly force sc_type = LEO -->
```

Alternatively, the evolver will auto-classify based on altitude and Δv and fall back to nearest match. For unusual missions (Earth-Moon, asteroid), approximate as the closest type and manually adjust scaling in post-processing.

---

### **Q: Can I add new propulsion systems to the database?**

**A:** Yes. Edit `Database/ESDC_Reference_Data_Systems.xml` (or `.yaml`):

1. Find the technology section (e.g., `<HET>`, `<chemical>`)
2. Add a new `<thruster>` entry with your data:
   ```xml
   <thruster>
     <type>HET</type>
     <name>My Custom Thruster</name>
     <c_e>18000</c_e>
     <power><min>2000</min><max>5000</max></power>
     <efficiency><min>0.50</min><max>0.60</max></efficiency>
     <propellant>Xenon</propellant>
     <source>My Paper / Datasheet</source>
   </thruster>
   ```
3. Clear the database hash: `rm Database/ESDC_Reference_Data_Systems_hash`
4. Re-run ESDC

The evolver will include your thruster in the search space.

---

### **Q: Why does ESDC sometimes select weird propellants (e.g., Bismuth for FEEP)?**

**A:** ESDC has access to all propellants in the database for each technology. This includes:

- **FEEP:** Indium (standard), Bismuth (rare, high atomic mass for small impulse bits)
- **Electrospray:** EMI-Imidazolium (ionic liquid)
- **Chemical:** Hydrazine, Hydrogen Peroxide, Methane (test systems)

**Normal behavior:** Low-Δv missions may select Bismuth FEEP (highest mass efficiency). This is not wrong; it's just uncommon in practice.

**To exclude unusual propellants:** Remove them from the database or add a constraint in code (advanced users only).

---

### **Q: My propellant combination doesn't exist in the DB. What happens?**

**A:** The evolver replaces missing propellant-thruster pairs with literature-fallback efficiencies:

| Technology | Fallback Isp (assumed c_e) | Used when |
|-----------|--------------------------|----------|
| HET | 1,700 s (c_e ≈ 17,000 m/s) | Propellant not found in DB |
| Chemical | 1,500 s (c_e ≈ 2,000 m/s) | Propellant not found |
| FEEP | 2,000 s (c_e ≈ 9,000 m/s) | Propellant not found |

This allows the evolver to continue searching, but the result is less accurate. **Best practice:** Stick to proven combinations (Xe for HET, N2H4 for chemical, etc.).

---

### **Q: How do I export results to a report or further analysis?**

**A:** ESDC outputs are in XML, which you can parse in any tool:

**Option 1: Octave parsing**
```octave
best_design = xml2struct('Output/1/ESDC_best_candidates.xml');
best_design = typeset_struct(best_design);
m_margin = best_design.Satellite_parameters.output.subsystem_masses.m_margin
propulsion_type = best_design.Satellite_parameters.output.propulsion_system.system_type
```

**Option 2: Python / Excel**
```python
import xml.etree.ElementTree as ET
tree = ET.parse('Output/1/ESDC_best_candidates.xml')
root = tree.getroot()
mass_total = root.find('.//mass_total').text
print(f"Total mass: {mass_total} kg")
```

**Option 3: Manual export**
- Copy XML to Excel (Data → From XML)
- Use any XML-to-CSV tool for spreadsheet analysis

---

### **Q: Can ESDC optimize for cost or schedule instead of mass?**

**A:** ESDC's fitness criterion is configurable via `ESDC_Simulation_parameters.xml`. Three optimization strategies are available:

| Fitness Criterion | Default | How to Enable | Best For |
|-------------------|---------|--------------|----------|
| **Maximize Mass Margin** | ✅ Yes | `maximize_mass_margin` | Robustness, design contingency, Phase 0/A feasibility (default) |
| **Minimize Total Mass** | — | `minimize_total_mass` | Lightweight designs, launch-cost-limited missions, CubeSats |
| **Maximize Payload Mass** | — | `maximize_payload_mass` | Science-payload-focused missions, maximizing operational capacity |

**How to change the fitness criterion:**

Edit `Input/ESDC_Simulation_parameters.xml`:
```xml
<fitness_criterion>maximize_mass_margin</fitness_criterion>
<!-- Change to 'minimize_total_mass' or 'maximize_payload_mass' -->
```

Or use pre-built parameter files:
```octave
javaaddpath("C:\\path\\to\\xerces\\xercesImpl.jar");
javaaddpath("C:\\path\\to\\xerces\\xml-apis.jar");

% In read_input_mission_parameter.m, change simulation_parameter_path to:
simulation_parameter_path = 'Input/Example_Files/ESDC_Simulation_parameters_minimize_total_mass.xml'

ESDC(runID)
```

**Which to choose:**
- **Maximize Mass Margin** (default): Safest choice; maximizes design robustness and contingency
- **Minimize Total Mass**: For missions where launch cost dominates or payload capacity is flexible
- **Maximize Payload Mass**: For science missions where payload capacity is the primary objective

---

### **Q: What happens if I provide conflicting inputs (e.g., "no propulsion" but Δv=1000 m/s)?**

**A:** ESDC attempts to reconcile conflicts with a priority chain:

1. **Explicit `sc_type`** takes highest priority
2. If not given, **`orbit_height`** determines type (LEO vs. HEO)
3. If orbit not given, **`deltav`** infers type

Example:
```xml
<sc_type>1</sc_type>           <!-- Force No Propulsion -->
<orbit_height>500</orbit_height>  <!-- Contradicts: LEO classification -->
<deltav>500</deltav>            <!-- Contradicts: GEO classification -->
```
**Result:** sc_type=1 (No Propulsion) overwrites all inferences; propulsion system ignored; design proceeds with only passive attitude control.

**Best practice:** Provide only the necessary parameters to avoid confusion.

---

## 12. Support & Further Resources

### Getting Help

- **Code issues / bugs:** Open an issue on [GitHub](https://github.com/aerospaceresearch/ESDC)
- **Questions about results:** Review relevant example output
- **Feature requests:** Contact project maintainers

### References

**Foundational Documents:**
- SMAD (Wertz & Larson 2011): "Space Mission Analysis and Design"
- Goebel & Katz 2008: "Fundamentals of Electric Propulsion: Ion and Hall Thrusters"

**Example Missions Modeled by ESDC:**
- **LEO**: ISS resupply, Starlink latitude correction maneuvers
- **GEO**: Commercial comsats, inclination/longitude management
- **Deep Space**: Lunar orbit insertion, Mars fly-bys

### Version History

| Version | Date | Key Changes |
|---------|------|------------|
| 1.0 | Apr 2026 | Initial release; 11 examples, chemical propulsion support, bug fixes (Xe/Xenon, thrust_min validation) |

---

## 13. Appendix: Input Examples

### Example 1: Minimal LEO Mission

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Satellite_parameters>
  <input_case>
    <orbit_height>500</orbit_height>
    <mass_total>2000</mass_total>
    <deltav>100</deltav>
    <propulsion_power>1000</propulsion_power>
  </input_case>
</Satellite_parameters>
```

### Example 2: GEO with Tight Time Constraint

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Satellite_parameters>
  <input_case>
    <orbit_height>35786</orbit_height>
    <mass_total>6000</mass_total>
    <deltav>3000</deltav>
    <propulsion_power>8000</propulsion_power>
    <mission_duration>15</mission_duration>
    <maneuver_duration_max>3600</maneuver_duration_max>  <!-- 1-hour burn limit -->
    <thrust_mode>high</thrust_mode>
  </input_case>
</Satellite_parameters>
```

### Example 3: Multi-Case Run (Parametric Study)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Satellite_parameters>
  <!-- Case 1: Baseline -->
  <input_case>
    <mass_total>4000</mass_total>
    <deltav>200</deltav>
    <propulsion_power>2000</propulsion_power>
  </input_case>
  
  <!-- Case 2: Higher power -->
  <input_case>
    <mass_total>4000</mass_total>
    <deltav>200</deltav>
    <propulsion_power>5000</propulsion_power>  <!-- 2.5× power -->
  </input_case>
  
  <!-- Case 3: Larger spacecraft -->
  <input_case>
    <mass_total>8000</mass_total>        <!-- 2× mass -->
    <deltav>200</deltav>
    <propulsion_power>2000</propulsion_power>
  </input_case>
</Satellite_parameters>
```

ESDC runs all three sequentially; results in `Output/runID/`.

---

**End of User Documentation**

*Last updated: April 2026*
