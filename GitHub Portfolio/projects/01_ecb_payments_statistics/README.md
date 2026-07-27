# Payments Statistics Production System

**Author: Jose Camas Garrido**

An independent, synthetic project built for a payments-statistics research
position. It recreates the end-to-end work behind a quarterly official-
statistics production cycle: ingesting heterogeneous PSP submissions,
standardising business concepts, resolving revisions, validating country
trends, preparing an analyst review queue and loading publication-ready
aggregates into a relational database.

No code or data from the other portfolio folders are required.

## Research and production questions

- How should submissions from legacy CSV, regulatory XML, portals and migration
  shadow systems be reconciled?
- Which observation should prevail when a PSP submits several versions of the
  same statistical cell?
- How can anomalous country or instrument trends be surfaced without hiding the
  original values?
- How can flash, first-release and final vintages be compared systematically?
- How should a legacy production system be tested against a candidate system
  before migration?
- How can data contracts, SQL controls and checksums make the workflow
  auditable?

## What the code contains

- synthetic country, PSP, merchant, payments, fraud, card, terminal, incident,
  macro and vintage datasets;
- explicit statistical grains, allowed domains, units and numeric bounds;
- country aliases and amount-unit conversion;
- documented source precedence for revisions;
- missing, negative, timeliness and extreme-ticket flags;
- robust median/MAD peer outliers;
- country-quarter and instrument-quarter tables;
- component-to-total reconciliation;
- a severity-ranked review pack;
- revision bias and mean absolute revision diagnostics;
- a shadow-production migration comparator;
- a minimal ECB Data Portal SDMX 2.1 client with offline fallback;
- a SQLite star schema, analytical views and read-only controls;
- incremental-change detection and SHA-256 manifests; and
- seven project-local acceptance checks.

## Run

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python payments_statistics_pipeline.py all --profile ci
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
python payments_statistics_pipeline.py all --profile ci
```

Profiles:

- `ci`: five countries, twelve PSPs and twenty quarters;
- `demo`: ten countries and a longer time period;
- `full`: all simulated EU countries and the largest source extracts.

Use `--persist-raw` only when you want the generated input CSVs written under
`data/raw/`.

## Main outputs

`outputs/` contains:

- `cleaned_payments.csv`
- `country_quarter.csv`
- `instrument_quarter.csv`
- `review_pack.csv`
- `revision_diagnostics.csv`
- `migration_comparison.csv`
- `payments_statistics.sqlite`
- `data_contracts.csv`
- `acceptance_checks.csv`
- `project_report.md`
- `production_manifest.json`

Selected lightweight outputs from a passing CI run are stored under
`examples/`.

## Interpretation

All values are synthetic. The project demonstrates official-statistics
engineering and analysis but does not reproduce ECB payment statistics.

## External reference

The optional API interface follows the
[ECB Data Portal API overview](https://data.ecb.europa.eu/help/api/overview).
Network access is disabled in the reproducible default run.
