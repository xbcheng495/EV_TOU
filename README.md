# EV Charging, Time-of-Use Tariffs, and Renewable Mismatch

This repository contains the core analysis code for the paper:

**The Hidden Costs and Renewable Mismatch of Electric Vehicle Time-of-Use Tariffs**

The code documents the main empirical and counterfactual workflow used to study how time-of-use (TOU) electricity tariffs affect electric-vehicle public charging behavior, grid ramping shocks, renewable-energy alignment, carbon emissions, and consumer welfare.

Raw charging-session data are not included because they are proprietary. The repository is therefore intended as a transparent code archive rather than a fully self-contained replication package.

## Repository structure

```text
code/
  00_install_stata_packages.do
  01_tou_tariff_rules.py
  02_rdd_price_transitions.do
  03_elasticity_ols_ppml.do
  04_counterfactual_flat_pricing.do
  05_grid_renewable_emissions.do
  06_welfare_analysis.do
docs/
  data_requirements.md
  workflow.md
  code_manifest.csv
data/
  Placeholder for restricted input data
outputs/
  figures/
  tables/
```

## Core modules

1. **TOU tariff rules**: embeds readable public provincial TOU schedules with English province/city names and assigns expected prices to charging sessions.
2. **RDiT / Donut RD**: estimates instantaneous charging responses around tariff transition thresholds.
3. **OLS and PPML elasticity estimation**: estimates intensive-margin and extensive-margin price responses.
4. **Counterfactual pricing**: constructs a revenue-neutral flat-rate benchmark.
5. **Grid, renewable, and emission outcomes**: calculates load profiles, ramping shocks, renewable mismatch, EGA, and CO2 emissions.
6. **Welfare analysis**: computes time-cost and consumer-surplus decompositions.

## How to use

Run the scripts from the repository root. Before running, place the required restricted inputs under `data/` or modify the path macros at the top of each script.

See:

- `docs/data_requirements.md` for input files and variables
- `docs/workflow.md` for the recommended execution order
- `docs/code_manifest.csv` for script-to-output mapping
