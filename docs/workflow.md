# Workflow

Run all commands from the repository root.

## 1. Python environment

```bash
pip install -r requirements.txt
```

## 2. Stata packages

```stata
do code/00_install_stata_packages.do
```

## 3. TOU tariff assignment

```bash
python code/01_tou_tariff_rules.py
```

This script uses the embedded public provincial TOU tariff rules by default.
Province and city names in the input data should be standardized to English
names matching `NATIONAL_TOU_RATES`.
If `data/tou_rules.json` exists, the external JSON file overrides the embedded
rules. The script creates `data/charging_sessions_with_tou_prices.csv`, which
can be used to build the order-alternative choice panel.

## 4. RDiT / Donut RD analysis

```stata
do code/02_rdd_price_transitions.do
```

Main outputs:

- `outputs/figures/rdd_high_to_low.pdf`
- `outputs/figures/rdd_low_to_high.pdf`
- `outputs/tables/rdd_high_to_low.rtf`
- `outputs/tables/rdd_low_to_high.rtf`

## 5. OLS and PPML elasticity estimation

```stata
do code/03_elasticity_ols_ppml.do
```

Main outputs:

- `outputs/tables/elasticity_estimates.rtf`
- `data/prediction_panel.dta`
- `data/ppml_expected_kwh_model.ster`

## 6. Revenue-neutral flat-rate counterfactual

```stata
do code/04_counterfactual_flat_pricing.do
```

Main outputs:

- `data/counterfactual_predictions.dta`
- `outputs/figures/national_average_price_curve.pdf`

## 7. Grid, renewable, and emission outcomes

```stata
do code/05_grid_renewable_emissions.do
```

Main outputs:

- `outputs/figures/load_and_ramping_shocks.pdf`
- `outputs/figures/renewable_mismatch_load_profiles.pdf`
- `outputs/tables/province_grid_renewable_emissions.csv`
- `outputs/tables/renewable_mismatch_correlations.csv`

## 8. Welfare analysis

```stata
do code/06_welfare_analysis.do
```

Main outputs:

- `outputs/figures/welfare_decomposition.pdf`
- `outputs/tables/welfare_decomposition_by_time.csv`
- `outputs/tables/province_welfare_decomposition.csv`
