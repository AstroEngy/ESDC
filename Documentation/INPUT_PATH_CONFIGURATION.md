# ESDC Input Path Configuration Guide

## Overview

The ESDC input file path is now **externalized and configurable** without editing code. Users can specify which mission parameter input file to use through multiple methods with a clear priority order.

---

## Configuration Methods (Priority Order)

### 1. Environment Variable (Highest Priority) ⭐

**Best for:** CI/CD pipelines, batch processing, scripted runs

Set the `ESDC_INPUT_PATH` environment variable to override all other configuration:

#### Linux/macOS/Bash:
```bash
export ESDC_INPUT_PATH='Input/ESDC_Input_LEO_300kg_Arcjet'
octave ESDC.m
```

#### PowerShell:
```powershell
$env:ESDC_INPUT_PATH = 'Input/ESDC_Input_LEO_300kg_Arcjet'
octave ESDC.m
```

#### MATLAB/Octave (inside script):
```matlab
setenv('ESDC_INPUT_PATH', 'Input/ESDC_Input_LEO_300kg_Arcjet');
ESDC  % or your main entry point
```

---

### 2. Config File (Recommended for Interactive Use) 📝

**Best for:** Interactive work, changing default behavior

Edit `Input/ESDC_Simulation_parameters.yaml` and change the `input_file_path` setting:

```yaml
Simulation_parameters:
  io:
    prefer_xml: false
    input_file_path: 'Input/ESDC_Input_LEO_650ms_1500W'  # ← Change this
```

**Examples:**
```yaml
    # 300 kg Arcjet mission
    input_file_path: 'Input/ESDC_Input_LEO_300kg_Arcjet'

    # 300 kg Medium EP mission
    input_file_path: 'Input/ESDC_Input_LEO_300kg_MediumEP'

    # Generic LEO with 1500W and 400 m/s
    input_file_path: 'Input/ESDC_Input_LEO_1500W_400ms'

    # Template with all fields
    input_file_path: 'Input/ESDC_Input_all_fields_template_revision_v2'
```

---

### 3. Hardcoded Fallback (Lowest Priority)

If neither environment variable nor config file setting is found, the code falls back to:
```
'Input/ESDC_Input_LEO_650ms_1500W'
```

This ensures ESDC always has a valid input to work with.

---

## Workflow Examples

### Example 1: Quick Switch for Interactive Testing

```bash
# Currently using ESDC_Input_LEO_650ms_1500W, want to test 300kg Arcjet

# Step 1: Edit ESDC_Simulation_parameters.yaml
vi Input/ESDC_Simulation_parameters.yaml
# Change: input_file_path: 'Input/ESDC_Input_LEO_300kg_Arcjet'

# Step 2: Run ESDC
octave ESDC.m

# Output will show:
# [get_input_file_path] Using input_file_path from ESDC_Simulation_parameters.yaml: Input/ESDC_Input_LEO_300kg_Arcjet
```

### Example 2: Batch Processing Multiple Cases

```bash
#!/bin/bash
# Run ESDC with 5 different input configurations

cases=(
  'Input/ESDC_Input_LEO_300kg_Arcjet'
  'Input/ESDC_Input_LEO_300kg_MediumEP'
  'Input/ESDC_Input_LEO_1500W_400ms'
  'Input/ESDC_Input_LEO_650ms_1500W'
  'Input/ESDC_Input_LEO_1500W_400ms_open_mass'
)

for case in "${cases[@]}"; do
  echo "Running case: $case"
  export ESDC_INPUT_PATH="$case"
  octave ESDC.m
  echo "Completed: $case"
  echo "---"
done
```

### Example 3: Python Wrapper Script

```python
import subprocess
import os

input_files = [
    'Input/ESDC_Input_LEO_300kg_Arcjet',
    'Input/ESDC_Input_LEO_300kg_MediumEP',
    'Input/ESDC_Input_LEO_1500W_400ms',
]

for input_file in input_files:
    env = os.environ.copy()
    env['ESDC_INPUT_PATH'] = input_file
    
    print(f"Running: {input_file}")
    result = subprocess.run(['octave', 'ESDC.m'], env=env)
    print(f"Exit code: {result.returncode}\n")
```

---

## How It Works (Technical Details)

### Resolution Flow

```
┌─────────────────────────────────────────────────┐
│ read_input_mission_parameter() called           │
└────────────────────┬────────────────────────────┘
                     │
                     ├─→ Check environment: ESDC_INPUT_PATH
                     │   └─→ Found? ✓ Use it → Read file
                     │       Found? ✗ Continue
                     │
                     ├─→ Read ESDC_Simulation_parameters.yaml
                     │   └─→ Extract io.input_file_path
                     │       Found? ✓ Use it → Read file
                     │       Found? ✗ Continue
                     │
                     └─→ Use default fallback
                         'Input/ESDC_Input_LEO_650ms_1500W'
                         └─→ Read file
```

### Helper Function

A new function `get_input_file_path()` implements the priority logic:

```matlab
function input_file_path = get_input_file_path(simulation_parameters)
  % Priority 1: Environment variable
  env_path = getenv('ESDC_INPUT_PATH');
  if ~isempty(env_path)
    return env_path
  end
  
  % Priority 2: Config file
  if simulation_parameters.io.input_file_path is set
    return simulation_parameters.io.input_file_path
  end
  
  % Priority 3: Default
  return 'Input/ESDC_Input_LEO_650ms_1500W'
end
```

---

## Available Input Files

### Quick Reference

| Filename | Mass | Orbit | Propulsion | Delta-V | Power | Notes |
|----------|------|-------|-----------|---------|-------|-------|
| `ESDC_Input_LEO_650ms_1500W` | 200 kg | LEO | — | 650 m/s | 1500 W | Default |
| `ESDC_Input_LEO_1500W_400ms` | — | LEO | — | 400 m/s | 1500 W | Open mass |
| `ESDC_Input_LEO_300kg_Arcjet` | 300 kg | LEO | Arcjet | 400 m/s | 2500 W | Example |
| `ESDC_Input_LEO_300kg_MediumEP` | 300 kg | LEO | Medium EP | 400 m/s | — | Example |
| `ESDC_Input_all_fields_template_revision_v2` | Various | LEO | — | — | — | Template |

For a complete list, see `Input/` directory.

---

## Verification

### Check Which Input File is Being Used

Run ESDC and look for the diagnostic messages:

```
Reading Simulation Parameter Input File
Success
 
[get_input_file_path] Using ESDC_INPUT_PATH from environment: Input/ESDC_Input_LEO_300kg_Arcjet
Reading Mission Parameter Input File: Input/ESDC_Input_LEO_300kg_Arcjet
Success
```

Messages will show:
- `Using ESDC_INPUT_PATH from environment:` → Priority 1 (environment variable)
- `Using input_file_path from ESDC_Simulation_parameters.yaml:` → Priority 2 (config file)
- `Using default fallback path:` → Priority 3 (hardcoded default)

---

## Migration Guide (For Existing Code)

### Before (Code Changes Required):
```matlab
% Had to edit read_input_mission_parameter.m:
input_path = 'Input/ESDC_Input_LEO_300kg_Arcjet';  % ← Hardcoded
```

### After (No Code Changes):
```yaml
# Edit ESDC_Simulation_parameters.yaml:
input_file_path: 'Input/ESDC_Input_LEO_300kg_Arcjet'
```

Or set environment variable in any shell/script before running.

---

## Troubleshooting

### Problem: "ERROR: No input definition file"

**Cause:** The path specified doesn't exist or is incorrectly formatted.

**Solution:**
1. Check the path exists: `ls Input/ESDC_Input_LEO_300kg_Arcjet.yaml`
2. Ensure path uses forward slashes `/` (not backslashes `\`)
3. Path should be relative to ESDC root directory
4. Verify no typos in environment variable: `echo $ESDC_INPUT_PATH`

### Problem: Wrong Input File Being Used

**Solution:** Check priority by running ESDC and reading diagnostic output:
```
[get_input_file_path] Using input_file_path from ESDC_Simulation_parameters.yaml: ...
```

If using environment variable, ensure it's set:
```bash
echo $ESDC_INPUT_PATH  # Should print your path, not empty
```

---

## Best Practices

✅ **DO:**
- Use environment variables for automated/CI workflows
- Use config file edits for interactive development
- Document which input file a study uses in project notes

❌ **DON'T:**
- Hardcode paths in ESDC.m or other core files
- Rely on environment variables for permanent settings (they get lost)
- Mix environment variable and config file paths (confusing!)

---

## Summary

| Use Case | Method | Priority | Example |
|----------|--------|----------|---------|
| CI/CD pipeline | Environment variable | 1 | `export ESDC_INPUT_PATH='Input/ESDC_Input_LEO_300kg_Arcjet'` |
| Interactive work | Config file | 2 | Edit `ESDC_Simulation_parameters.yaml` |
| Default fallback | Code | 3 | `'Input/ESDC_Input_LEO_650ms_1500W'` |

**Start here:** Edit `Input/ESDC_Simulation_parameters.yaml` and change `input_file_path` to your desired case.

