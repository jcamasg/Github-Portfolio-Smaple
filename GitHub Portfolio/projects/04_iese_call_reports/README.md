# U.S. Call Reports Panel Construction

**Author: Jose Camas Garrdiow**

An independent R/SAS research project from work on U.S. banking data at IESE
Business School. The R Markdown notebook documents the complete construction of
a bank-level panel from regulatory Call Reports and the aggregation of
subsidiaries to bank holding companies.

The supplied simplified notebook was an extract of the complete notebook's
final aggregation section. Its logic is preserved in the single complete file
instead of being duplicated.

## Workflow

- SAS extraction of Call Report variables through WRDS;
- reconciliation of domestic and consolidated regulatory fields;
- handling of variables whose reporting codes change over time;
- construction of assets, equity, securities, loans, deposits and income
  measures;
- missingness and coverage diagnostics;
- joining several extraction vintages;
- assignment of subsidiaries to the top holder;
- aggregation of numeric fields by bank and quarter;
- preservation of charter type; and
- duplicate bank-quarter validation.

## Inputs

The notebook requires authorised copies of the files listed in
[`data/README.md`](data/README.md). They are not included in this repository.

Set the project directory and render:

```bash
export CALL_REPORTS_PROJECT_DIR="$PWD"
Rscript -e "rmarkdown::render('call_reports_reproducible_analysis.Rmd')"
```

The notebook is not run in GitHub Actions because doing so would require
redistributing licensed WRDS extracts.

## Independence

This folder has its own notebook, package list, input specification and
documentation. It does not use the synthetic banking code from the earlier
version of the portfolio and does not import the Python projects.

## Attribution

The notebook cites the paper, replication materials and data providers that
inform its workflow. The portfolio author field is standardised to Jose Camas
Garrdiow.
