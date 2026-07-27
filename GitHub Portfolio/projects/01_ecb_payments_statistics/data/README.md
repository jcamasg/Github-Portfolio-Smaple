# Data

The default run generates all project inputs from a fixed random seed. It does
not download or redistribute ECB or PSP records.

The optional `--persist-raw` flag writes synthetic CSV extracts to `data/raw/`.
That folder is ignored by Git.

The generated source bundle contains:

- country metadata;
- a PSP registry;
- a merchant registry;
- quarterly payment cells;
- fraud reports;
- terminal and card inventories;
- revision vintages;
- a macroeconomic panel; and
- operational incidents.

The SDMX client is included as an interface example. Network requests are
disabled by default and are not required to reproduce the project.
