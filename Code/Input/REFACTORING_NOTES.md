# Input Processing Block - Refactoring v2.0

## Summary of Changes

### Code Reduction
- **Before:** 1,249 lines
- **After:** 795 lines
- **Reduction:** 454 lines (36% smaller)

### Key Improvements

#### 1. **Unified Architecture**
- Single entry point: `update_scaling_model(force_update_flag)`
- Eliminated duplicate functions for spacecraft vs systems
- Shared utility functions for data extraction and validation

#### 2. **Cleaner Separation of Concerns**
- **Database Management:** Hash checking, reading, updating
- **Spacecraft Correlations:** Dedicated section for spacecraft processing
- **Systems Correlations:** Dedicated section for component/system processing
- **Utilities:** Reusable helper functions
- **Storage:** YAML writing and file management
- **Fitting:** Original `data_fitting()` preserved unchanged

#### 3. **Output Format**
Individual YAML files per correlation:
```
Database/Scaling/
├── spacecraft/
│   ├── LEO_m_total_to_p_total.yaml
│   └── GEO_m_payload_to_p_payload.yaml
├── systems/
│   ├── propulsion_arcjet_thruster_NH3_mass_to_power_jet.yaml
│   └── power_photovoltaic_cell_mass_to_power_max.yaml
└── scaling_index.yaml
```

Each YAML file contains:
- Correlation metadata (type, category, parameters, units)
- Raw data (x, y values, names, sources)
- Fit results (coefficients, R², RMSE, fitted curves)
- Generation metadata (timestamp, data point count)

#### 4. **Robust Error Handling**
- Try-catch blocks around database processing
- Warnings instead of fatal errors for individual correlations
- Continues processing even if some correlations fail

#### 5. **Improved Maintainability**
- Clear function names and documentation
- Consistent naming conventions
- Logical code organization with section headers
- Config-driven exclusion lists (easy to modify)

### Functions Retained
- `data_fitting()` - Original implementation preserved as requested

### Functions Eliminated (Consolidated)
- `update_SC_scaling()` - Merged into `update_scaling_model()`
- `update_generic_spacecraft_scaling_model()` - Replaced by `generate_spacecraft_correlations()`
- `update_system_scaling()` - Merged into `update_scaling_model()`
- `update_generic_component_scaling_model()` - Replaced by `generate_systems_correlations()`
- `update_generic_spacecraft_scaling_a_to_b()` - Replaced by `save_correlation_yaml()`
- `update_generic_component_scaling_a_to_b()` - Replaced by `save_correlation_yaml()`
- `update_generic_spacecraft_system_scaling_a_to_b()` - Consolidated
- `write_selected_data_to_file()` - Replaced by `write_yaml()`
- `sort_data_to_x()` - Logic integrated into `save_correlation_yaml()`
- `make_makeshift_graph()` - Replaced by `generate_correlation_plot()`
- `get_parameter_unit()` - Kept and simplified
- `read_reference_data()` - Consolidated into `read_database()`
- `read_reference_spacecraft_data()` - Consolidated into `read_database()`

### New Functions Added
- `database_changed()` - Unified database change detection
- `check_hash()` - Generic hash checking
- `update_hash_files()` - Update all hash files at once
- `write_hash()` - Generic hash writing
- `generate_spacecraft_correlations()` - Process all spacecraft correlations
- `extract_spacecraft_data()` - Extract data pairs for spacecraft
- `generate_systems_correlations()` - Process all system correlations
- `process_component()` - Handle component with sub-categorization
- `generate_component_correlations()` - Generate correlations for components
- `extract_component_data()` - Extract data pairs for components
- `get_unique_values()` - Get unique field values from data array
- `get_numeric_fields()` - Find all numeric fields in dataset
- `save_correlation_yaml()` - Save correlation to YAML file
- `fit_scaling_law()` - Wrapper around data_fitting with metadata
- `estimate_poly_degree()` - Estimate polynomial degree heuristic
- `write_yaml()` - YAML file writer
- `write_yaml_recursive()` - Recursive YAML structure writer
- `escape_yaml_string()` - Escape special characters
- `generate_correlation_plot()` - Create visualization plots
- `save_scaling_index()` - Save index file
- `load_scaling_index()` - Load index file

## Usage

### Basic Usage
```matlab
% Auto-detect changes and update if needed
scaling_model = update_scaling_model(false);

% Force regeneration of all correlations
scaling_model = update_scaling_model(true);
```

### Output Structure
```matlab
scaling_model = 
  struct with fields:
    version: '2.0'
    generated: '2026-01-29 15:30:00'
    spacecraft: {12×1 cell}  % Paths to YAML files
    systems: {45×1 cell}     % Paths to YAML files
```

## Benefits

1. **Modularity:** Each correlation is independent
2. **Git-Friendly:** Individual file changes tracked separately
3. **Selective Loading:** Load only needed correlations
4. **Debugging:** Easier to identify and fix issues
5. **Extensibility:** Easy to add new correlation types
6. **Maintainability:** Clearer code structure
7. **Performance:** Potential for parallel processing
8. **Metadata:** Rich metadata stored with each correlation

## Backward Compatibility

The old CSV files are no longer generated. To migrate existing code:

**Before:**
```matlab
data = csvread('Database/Scaling/scaling_spacecraft_LEO_parameter_m_total_to_p_total.csv');
```

**After:**
```matlab
corr = read_file_auto('Database/Scaling/spacecraft/LEO_m_total_to_p_total.yaml');
x_data = corr.data.x;
y_data = corr.data.y;
x_fit = corr.fit.x_fit;
y_fit = corr.fit.y_fit;
```

## Notes

- Original file backed up as: `Input_Processing_block_v1_backup.m`
- PNG visualizations still generated for spacecraft correlations
- Systems visualization can be enabled by modifying `generate_correlation_plot()`
- `data_fitting()` function unchanged as requested
