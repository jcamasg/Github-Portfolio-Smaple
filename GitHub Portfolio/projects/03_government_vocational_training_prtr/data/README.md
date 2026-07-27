# Data

The Python project generates two independent synthetic sources.

## EPA-style repeated cross-sections

Variables retain names from the original analytical workflow so the translation
from Stata is clear:

- `CCAA`, `PROV`
- `EDAD1`
- `AOI`
- `FACTOREL`
- `CICLO`
- `NFORMA`
- `ACT1`

The simulation includes controlled differences by education, age, region,
activity and quarter. It also introduces a small number of type and missing-
value issues so that harmonisation is tested rather than assumed.

## PRTR-style project records

The project table includes places created, green/digital axes, committed and
executed investment, provider type, source system and intentionally inconsistent
regional names.

No actual EPA, Educabase, CoFFEE, ministry or regional data are distributed.
