# Agri-food Price Transmission and Climate Risk

**Author: Jose Camas Garrdiow**

An independent econometric project inspired by research assistance in the
International Economics and Euro Area Division of Banco de España. It studies
two linked questions using synthetic monthly data:

1. how upstream prices and input costs pass through producers, processors and
   retailers; and
2. how ENSO innovations affect commodity prices and food output.

The project contains no Banco de España code, data or results and imports
nothing from the other portfolio folders.

## Data architecture

The script creates and harmonises:

- producer, processor and retail price indices;
- energy, fertiliser, wage and transport costs;
- FAO-style global commodity prices;
- NOAA-style ENSO, drought, precipitation and temperature indicators; and
- country-product food-output indices.

Every source has an explicit grain and source-key validation.

## Econometric workflow

- levels, logs, differences and annual growth rates;
- augmented Dickey-Fuller auxiliary regressions;
- Engle-Granger residual-based cointegration diagnostics;
- error-correction pass-through models;
- separate upstream increases and decreases;
- distributed-lag selection with AIC, BIC and HQIC;
- reduced-form VAR estimation and Cholesky impulse responses;
- panel local projections with unit/time effects and clustered inference;
- rolling-window pass-through;
- panel fixed effects; and
- a clearly labelled mechanical policy scenario.

The code deliberately exposes the design matrices, covariance estimators and
diagnostics rather than hiding every step behind a high-level package.

## Run

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python agrifood_climate_econometrics.py --profile ci
```

Profiles:

- `ci`: four countries, three products and 2014–2023;
- `demo`: eight countries, six products and 2011–2025;
- `full`: the longest simulated monthly panel.

## Main outputs

- `monthly_panel.csv`
- `unit_root_tests.csv`
- `lag_selection.csv`
- `ecm_coefficients.csv`
- `asymmetric_ecm.csv`
- `var_irfs.csv`
- `local_projection_irfs.csv`
- `rolling_estimates.csv`
- `panel_fixed_effects.csv`
- `counterfactual.csv`
- `model_diagnostics.csv`
- `acceptance_checks.csv`
- `project_report.md`

Selected tables from a passing CI run are included under `examples/`.

## Methodological boundary

Residual-based cointegration tests have non-standard critical values, so the
project reports the auxiliary statistic without fabricating a small-sample
p-value. VAR ordering is documented, local projections use clustered
large-sample inference, and the counterfactual is labelled a scenario rather
than a causal forecast.
