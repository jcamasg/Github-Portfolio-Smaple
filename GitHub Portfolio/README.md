# Applied Economic Research Portfolio

**Jose Camas Garrdiow**

This repository contains four independent research projects drawn from the
types of work I have conducted in a central bank, academic research and the
Spanish centre of government. Each folder has its own code, documentation,
dependencies, data policy, examples and execution command. No Python project
imports code from another.

The projects demonstrate methods and research engineering. They do not
redistribute confidential or licensed data and do not reproduce official or
unpublished institutional results.

## Independent projects

| Folder | Project | Language | Main methods |
|---|---|---|---|
| [`01_ecb_payments_statistics`](projects/01_ecb_payments_statistics/) | Payments statistics production system | Python | source integration, data contracts, outliers, revisions, migration UAT, SQLite and SDMX |
| [`02_bde_agrifood_climate`](projects/02_bde_agrifood_climate/) | Agri-food price transmission and climate risk | Python | cointegration, ECM, asymmetric pass-through, VAR, local projections and panel fixed effects |
| [`03_government_vocational_training_prtr`](projects/03_government_vocational_training_prtr/) | Vocational training, youth employment and PRTR | Python | survey weights, FP comparisons, activity panels, fuzzy matching, KPIs and descriptive regional analysis |
| [`04_iese_call_reports`](projects/04_iese_call_reports/) | U.S. Call Reports panel construction | R/SAS | regulatory data cleaning, reporting-regime reconciliation and holding-company aggregation |

## Structure

```text
projects/
├── 01_ecb_payments_statistics/
│   ├── payments_statistics_pipeline.py
│   ├── README.md
│   ├── requirements.txt
│   ├── data/README.md
│   └── examples/
├── 02_bde_agrifood_climate/
│   ├── agrifood_climate_econometrics.py
│   ├── README.md
│   ├── requirements.txt
│   ├── data/README.md
│   └── examples/
├── 03_government_vocational_training_prtr/
│   ├── vocational_training_prtr_evaluation.py
│   ├── stata/vocational_training_prtr_full_workflow.do
│   ├── README.md
│   ├── requirements.txt
│   ├── data/README.md
│   └── examples/
└── 04_iese_call_reports/
    ├── call_reports_reproducible_analysis.Rmd
    ├── README.md
    ├── requirements-r.txt
    ├── data/README.md
    └── examples/
```

The analytical files are intentionally complete workflows rather than small
fragments:

- payments statistics: more than 2,000 lines;
- agri-food and climate econometrics: more than 2,000 lines;
- vocational training and PRTR: more than 2,000 lines; and
- consolidated FP/PRTR Stata workflow: more than 5,000 lines; and
- Call Reports R Markdown: more than 1,000 lines.

Their length comes from explicit data-generating processes, validation,
transformations, estimation and reporting. There are no numbered filler
functions or tests whose purpose is to count lines.

## Running a project

Enter the chosen project directory and follow its README. For example:

```bash
cd projects/01_ecb_payments_statistics
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python payments_statistics_pipeline.py all --profile ci
```

The other Python projects use the same pattern. Each writes only to its own
`outputs/` directory and returns a non-zero exit code when a local acceptance
check fails.

The Call Reports project requires authorised WRDS inputs and is therefore not
executed automatically.

## Reproducibility

GitHub Actions treats the Python folders as three separate jobs. Each job:

1. installs the requirements declared inside that project;
2. compiles only that project's main file;
3. runs the project from its own working directory; and
4. uploads that project's lightweight report and validation table.

This makes independence observable in CI rather than merely asserted in the
folder structure.

## Portfolio boundaries

- Python inputs are deterministic synthetic data.
- The payments API client is offline by default.
- Banco de España, government and IESE source files are not included.
- WRDS data must be supplied by an authorised user.
- Broad green-linked branches are not presented as a direct count of green
  jobs.
- The PRTR `t` to `t+2` relationship is descriptive and not causal.

See [`docs/project_boundaries.md`](docs/project_boundaries.md) for a precise
mapping between each public project and the professional capability it
demonstrates.

## Author and licence

Jose Camas Garrdiow

MIT Licence. Third-party data and research remain subject to their own terms.
