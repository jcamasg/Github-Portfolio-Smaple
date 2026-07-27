# Vocational Training and PRTR Evaluation

**Author: Jose Camas Garrdiow**

This report is generated from synthetic EPA-style microdata and synthetic project records. It is not an official evaluation.

## Project scale

- FP region-quarter cells: 680
- Complete activity cells: 7,480
- PRTR region-year observations: 51
- Linked t-to-t+2 observations: 51
- Synthetic KPIs achieved: 5/5

## KPI status

| kpi_id | name | actual | target | achieved |
| --- | --- | --- | --- | --- |
| FP_01 | Training places created | 88537.0 | 30000 | True |
| FP_02 | Green-axis place share | 38.45285022081164 | 30 | True |
| FP_03 | Digital-axis place share | 25.187209867061227 | 22 | True |
| FP_04 | Investment execution | 85.68768759599438 | 85 | True |
| FP_05 | Territorial coverage | 17.0 | 17 | True |

## Latest FP labour-market indicators

| ccaa_name | period | unemployment_rate_4q | employment_population_rate_4q |
| --- | --- | --- | --- |
| Andalucía | 2025Q4 | 43.28 | 40.46 |
| Extremadura | 2025Q4 | 34.04 | 44.52 |
| Castilla y León | 2025Q4 | 36.38 | 45.5 |
| Castilla-La Mancha | 2025Q4 | 34.88 | 46.2 |
| Comunitat Valenciana | 2025Q4 | 38.29 | 46.31 |
| Cataluña | 2025Q4 | 36.7 | 43.47 |
| País Vasco | 2025Q4 | 31.4 | 45.01 |
| La Rioja | 2025Q4 | 43.71 | 40.46 |
| Cantabria | 2025Q4 | 35.7 | 45.69 |
| Galicia | 2025Q4 | 32.76 | 49.26 |
| Illes Balears | 2025Q4 | 30.41 | 50.38 |
| Canarias | 2025Q4 | 33.34 | 48.07 |
| Comunidad de Madrid | 2025Q4 | 38.02 | 43.29 |
| Navarra | 2025Q4 | 43.89 | 41.47 |
| Región de Murcia | 2025Q4 | 36.0 | 46.72 |
| Asturias | 2025Q4 | 36.67 | 42.9 |
| Aragón | 2025Q4 | 35.25 | 46.69 |

## Acceptance checks

| project | check | status | observed | expected | detail |
| --- | --- | --- | --- | --- | --- |
| vocational_training | validation_has_no_failures | pass | 0 | 0 | All non-null and range rules must pass after source coercion. |
| vocational_training | weighted_population_identity | pass | 1.0913936421275139e-11 | < 1e-8 | Employed + unemployed + inactive equals the weighted population. |
| vocational_training | activity_shares_sum_to_100 | pass | 2.842170943040401e-14 | < 1e-8 | Activity shares use one unrepeated employed denominator. |
| vocational_training | territorial_matches_reviewed | pass | 1.0 | 1.0 | Every unique reported region has an accepted auditable match. |
| vocational_training | lagged_linkage_nonempty | pass | 51 | > 0 | PRTR years have both t and t+2 synthetic labour outcomes. |
| vocational_training | descriptive_design_labelled | pass | False | False | Regional correlations are not advertised as causal effects. |
| vocational_training_prtr | deterministic_seed | pass | 7eff8797b91a7f0516a738c0963da3a7f77ac32bc54007bdc5fe9c3d573c417d | 7eff8797b91a7f0516a738c0963da3a7f77ac32bc54007bdc5fe9c3d573c417d | Repeated runs create identical KPI evidence. |

## Identification boundary

The regional relationship between PRTR places in year t and green-linked employment in t+2 is descriptive. Allocation is not random, a counterfactual is not established and no causal effect is claimed.
