# Vocational Training, Youth Employment and the PRTR

**Author: Jose Camas Garrdiow**

An independent policy-evaluation project inspired by work in the Spanish
Prime Minister's Office. It translates the logic of a multi-file Stata analysis
into a portable Python workflow using synthetic EPA-style microdata and
synthetic PRTR project records.

It imports no code from the payments or agri-food projects.

The folder also includes
`stata/vocational_training_prtr_full_workflow.do`, a consolidated and
path-sanitised copy of the supplied Stata analyses. Its nine named sections
preserve the EPA, FP comparison, activity, green-axis, lagged PRTR linkage and
territorial fuzzy-matching workflows. The Python file is the portable,
independently tested reconstruction; the Stata file documents the underlying
research development.

## Questions

- How have weighted youth employment and unemployment indicators evolved for
  FP and non-FP groups?
- How do FP outcomes compare separately with secondary-or-lower and university
  groups?
- Which broad activity branches account for youth employment?
- How can green-transition-linked branches be tracked without calling them a
  direct measure of green jobs?
- How can regional PRTR project records be reconciled when territorial names
  differ?
- What can be learned descriptively by linking training places in `t` with
  labour-market outcomes in `t+2`?

## Stata logic reproduced

- EPA files from 2021Q1 onward;
- respondents younger than 25;
- `FACTOREL` survey weights;
- AOI 3–4 employed, 5–6 unemployed and 7–9 inactive;
- `NFORMA == "SP"` for the FP group;
- FP/no-FP, FP/secondary and FP/university comparisons;
- complete CCAA × quarter × FP × ACT1 grids;
- four-quarter sums and derived rates;
- 2021=100 activity indices;
- ACT1 branch shares;
- core green-linked branches ACT1 2, 3 and 4;
- regional-name normalisation and fuzzy matching;
- PRTR places and investment by CCAA/year; and
- descriptive `t` to `t+2` linkage.

## Run

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python vocational_training_prtr_evaluation.py --profile ci
```

To use the Stata archive with authorised local inputs:

```stata
global PROJECT_ROOT "/path/to/project/data"
do "stata/vocational_training_prtr_full_workflow.do"
```

Review the section-specific input filenames before execution. The source is
included for analytical traceability; institutional data are not supplied.

The script creates:

- weighted FP labour-market panels;
- FP comparator tables;
- complete activity and green-linked panels;
- a territorial matching audit;
- PRTR KPI and milestone tables;
- a lagged regional linkage;
- descriptive regression output;
- seven project-local checks;
- a Markdown report; and
- an HTML dashboard.

Selected outputs from a passing run are included under `examples/`.

## Identification boundary

The regional relationship is not presented as causal. PRTR allocation can
respond to earlier labour-market conditions; no untreated counterfactual or
parallel-trends design is established. The code records this limitation in the
regression diagnostics and generated report.

## Confidentiality

The project does not contain EPA microdata, Educabase records, ministerial
files, regional administrative data or official PRTR results.
