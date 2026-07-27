# Project boundaries

Each folder is designed to stand on its own. The separation is substantive, not
only visual.

| Project | Professional capability represented | Data included | Cross-project imports |
|---|---|---|---|
| Payments statistics | statistical production, country trends, outliers, validation, migration and Python/SQL systems | deterministic synthetic PSP submissions | none |
| Agri-food and climate | price transmission, international data harmonisation and time-series econometrics | deterministic synthetic price, cost, output and climate series | none |
| Vocational training and PRTR | administrative-data architecture, survey indicators, sectoral analysis, KPIs and policy reporting | deterministic synthetic EPA-style and PRTR-style records | none |
| Call Reports | regulatory banking panels and holding-company aggregation | no source data; authorised WRDS files required | none |

## Payments statistics

This is the vacancy-facing project. It is not presented as work performed at the
ECB. It demonstrates transferable skills through an original synthetic
production system.

## Agri-food and climate

This project is inspired by research tasks at Banco de España, but it contains
no institutional code, estimates or source files. Its generated coefficients
are examples, not replications of unpublished work.

## Vocational training and PRTR

The project preserves analytical concepts from the user's Stata workflow:
weights, age filters, FP definitions, ACT1 branches, four-quarter measures,
green-linked classifications and `t+2` descriptive comparisons. It does not
contain EPA microdata or internal government records.

## Call Reports

The notebook preserves the complete supplied analytical workflow. It is
separate from the payments project because it represents a distinct IESE
research assignment and requires its own licensed inputs.

## Safe description

> This repository contains independent public reconstructions of four research
> workflows from my experience. The Python projects use synthetic data; the
> Call Reports notebook requires authorised source files. They demonstrate my
> methods and data-engineering choices without publishing institutional data or
> results.
