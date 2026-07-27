from __future__ import annotations

"""
Synthetic vocational-training policy evaluation and portfolio orchestration.

This module translates the analytical structure of a real Stata workflow into
portable Python.  It recreates four tasks from the author's work on Spain's
Recovery and Resilience Plan:

1. harmonising quarterly labour-force survey microdata;
2. comparing young people in vocational education and training (FP) with
   non-FP, secondary and university groups;
3. tracking youth employment by broad activity branch and by a transparent
   "green-transition-linked" classification; and
4. linking PRTR-funded FP places in year t to descriptive labour-market changes
   in year t+2 across autonomous communities.

All records are simulated.  The exercise does not reproduce confidential
administrative data, official estimates or unpublished government results.
The lagged regional linkage is explicitly descriptive and is not presented as a
causal estimate.  Reproducibility, careful denominators and honest interpretation
are treated as part of the analysis rather than as documentation afterthoughts.
"""

from dataclasses import asdict, dataclass, field
from difflib import SequenceMatcher
from html import escape
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence
import argparse
import hashlib
import json
import math
import sys
import unicodedata

import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# Public classifications used by the synthetic EPA-style microdata
# ---------------------------------------------------------------------------


CCAA_LABELS: dict[int, str] = {
    1: "Andalucía",
    2: "Aragón",
    3: "Asturias",
    4: "Illes Balears",
    5: "Canarias",
    6: "Cantabria",
    7: "Castilla y León",
    8: "Castilla-La Mancha",
    9: "Cataluña",
    10: "Comunitat Valenciana",
    11: "Extremadura",
    12: "Galicia",
    13: "Comunidad de Madrid",
    14: "Región de Murcia",
    15: "Navarra",
    16: "País Vasco",
    17: "La Rioja",
    18: "Ceuta",
    19: "Melilla",
}


ACTIVITY_LABELS: dict[int, str] = {
    0: "Agriculture, forestry and fishing",
    1: "Food, textiles, wood, paper and other manufacturing",
    2: "Extractive, energy, water, waste, chemicals and metals",
    3: "Machinery, electrical equipment and transport equipment",
    4: "Construction",
    5: "Trade and hospitality",
    6: "Transport and communications",
    7: "Business and financial services",
    8: "Public administration, education and health",
    9: "Other services",
    99: "Unclassified",
}


GREEN_CORE_ACTIVITIES = {2, 3, 4}
GREEN_BROAD_ACTIVITIES = {0, 2, 3, 4, 6, 7}
DIGITAL_PROXY_ACTIVITIES = {6, 7}


EDUCATION_LABELS: dict[str, str] = {
    "FP": "Vocational education and training",
    "SECONDARY_OR_LOWER": "Secondary education or lower",
    "UNIVERSITY": "University education",
    "OTHER": "Other or unclassified education",
}


LABOUR_STATUS_LABELS: dict[int, str] = {
    3: "employed",
    4: "employed",
    5: "unemployed",
    6: "unemployed",
    7: "inactive",
    8: "inactive",
    9: "inactive",
}


def add_constant(values: pd.DataFrame | np.ndarray) -> np.ndarray:
    """Create a project-local regression design with an intercept."""

    array = np.asarray(values, dtype=float)
    if array.ndim == 1:
        array = array.reshape(-1, 1)
    return np.column_stack([np.ones(array.shape[0]), array])


def ols_fit(
    outcome: pd.Series | np.ndarray,
    design: pd.DataFrame | np.ndarray,
) -> dict[str, Any]:
    """Small transparent OLS implementation used by the descriptive linkage."""

    y = np.asarray(outcome, dtype=float).reshape(-1, 1)
    x = np.asarray(design, dtype=float)
    if x.ndim == 1:
        x = x.reshape(-1, 1)
    valid = np.isfinite(y.ravel()) & np.isfinite(x).all(axis=1)
    y = y[valid]
    x = x[valid]
    beta = np.linalg.pinv(x.T @ x) @ x.T @ y
    residuals = y - x @ beta
    observations, parameters = x.shape
    variance = float(
        (
            (residuals.T @ residuals)
            / max(observations - parameters, 1)
        ).item()
    )
    covariance = variance * np.linalg.pinv(x.T @ x)
    fitted = x @ beta
    total = float(np.square(y - y.mean()).sum())
    unexplained = float(np.square(residuals).sum())
    return {
        "beta": beta.ravel(),
        "resid": residuals.ravel(),
        "fitted": fitted.ravel(),
        "vcov": covariance,
        "r2": 1 - unexplained / total if total else np.nan,
        "nobs": int(observations),
    }


def normal_cdf(value: float) -> float:
    return 0.5 * (1 + math.erf(value / math.sqrt(2)))


def regression_table(
    terms: Sequence[str],
    coefficients: np.ndarray,
    covariance: np.ndarray,
) -> pd.DataFrame:
    """Return coefficients and large-sample inference in a stable schema."""

    beta = np.asarray(coefficients, dtype=float)
    standard_errors = np.sqrt(np.clip(np.diag(covariance), 0, None))
    statistics = np.divide(
        beta,
        standard_errors,
        out=np.full_like(beta, np.nan),
        where=standard_errors > 0,
    )
    p_values = [
        2 * (1 - normal_cdf(abs(float(statistic))))
        if np.isfinite(statistic)
        else np.nan
        for statistic in statistics
    ]
    return pd.DataFrame(
        {
            "term": list(terms),
            "coefficient": beta,
            "standard_error": standard_errors,
            "t_statistic": statistics,
            "p_value": p_values,
            "lower_95": beta - 1.96 * standard_errors,
            "upper_95": beta + 1.96 * standard_errors,
        }
    )


def ensure_dir(path: str | Path) -> Path:
    destination = Path(path)
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def safe_divide(
    numerator: pd.Series,
    denominator: pd.Series,
) -> pd.Series:
    denominator_numeric = pd.to_numeric(denominator, errors="coerce")
    numerator_numeric = pd.to_numeric(numerator, errors="coerce")
    return numerator_numeric / denominator_numeric.replace(0, np.nan)


def normalise_spanish_name(value: Any) -> str:
    """Normalise regional/municipal labels for deterministic matching."""

    text = "" if pd.isna(value) else str(value)
    text = text.strip().upper()
    decomposed = unicodedata.normalize("NFKD", text)
    ascii_text = "".join(
        character
        for character in decomposed
        if not unicodedata.combining(character)
    )
    for punctuation in (",", ".", "-", "/", "(", ")", "'"):
        ascii_text = ascii_text.replace(punctuation, " ")
    aliases = {
        "COMUNIDAD AUTONOMA DE ": "",
        "COMUNIDAD DE ": "",
        "REGION DE ": "",
        "PRINCIPADO DE ": "",
        "ILLES ": "",
    }
    for prefix, replacement in aliases.items():
        ascii_text = ascii_text.replace(prefix, replacement)
    return " ".join(ascii_text.split())


def weighted_sum(
    frame: pd.DataFrame,
    indicator: pd.Series,
    weight: str = "FACTOREL",
) -> float:
    weights = pd.to_numeric(frame[weight], errors="coerce").fillna(0)
    values = indicator.fillna(False).astype(float)
    return float((weights * values).sum())


def period_from_cycle(cycle: pd.Series) -> pd.PeriodIndex:
    """Translate the EPA-style cycle index used in the source Stata scripts."""

    numeric = pd.to_numeric(cycle, errors="coerce")
    year = 2021 + np.floor((numeric - 194) / 4)
    quarter = ((numeric - 194) % 4) + 1
    labels = (
        year.astype("Int64").astype(str)
        + "Q"
        + quarter.astype("Int64").astype(str)
    )
    return pd.PeriodIndex(labels, freq="Q")


def rolling_four_quarter_sum(
    frame: pd.DataFrame,
    *,
    group: Sequence[str],
    columns: Sequence[str],
    time: str = "quarter_period",
) -> pd.DataFrame:
    """Rolling four-quarter sum with a complete-window requirement."""

    output = frame.sort_values([*group, time]).copy()
    for column in columns:
        output[f"{column}_4q"] = (
            output.groupby(list(group), group_keys=False)[column]
            .rolling(window=4, min_periods=4)
            .sum()
            .reset_index(level=list(range(len(group))), drop=True)
        )
    return output


def markdown_table(frame: pd.DataFrame, maximum_rows: int = 18) -> str:
    if frame.empty:
        return "_No observations._"
    sample = frame.head(maximum_rows).copy()
    sample = sample.replace([np.inf, -np.inf], np.nan)
    sample = sample.astype(object).where(sample.notna(), "")
    columns = [str(column) for column in sample.columns]
    header = "| " + " | ".join(columns) + " |"
    separator = "| " + " | ".join(["---"] * len(columns)) + " |"
    body = [
        "| "
        + " | ".join(
            str(row[column]).replace("|", "/")
            for column in sample.columns
        )
        + " |"
        for _, row in sample.iterrows()
    ]
    return "\n".join([header, separator, *body])


# ---------------------------------------------------------------------------
# Synthetic EPA-style microdata
# ---------------------------------------------------------------------------


@dataclass
class EpaSimulationProfile:
    start: str
    end: str
    observations_per_region_quarter: int
    regions: list[int]


def epa_profile(name: str) -> EpaSimulationProfile:
    profiles = {
        "ci": EpaSimulationProfile(
            start="2021Q1",
            end="2025Q4",
            observations_per_region_quarter=180,
            regions=list(range(1, 18)),
        ),
        "demo": EpaSimulationProfile(
            start="2021Q1",
            end="2026Q1",
            observations_per_region_quarter=650,
            regions=list(range(1, 20)),
        ),
        "full": EpaSimulationProfile(
            start="2021Q1",
            end="2026Q1",
            observations_per_region_quarter=1800,
            regions=list(range(1, 20)),
        ),
    }
    if name not in profiles:
        raise ValueError(f"Unknown EPA simulation profile: {name}")
    return profiles[name]


@dataclass
class EpaMicrodataFactory:
    """Generate repeated cross-sections with survey weights and known trends."""

    seed: int = 2029
    profile: EpaSimulationProfile = field(
        default_factory=lambda: epa_profile("ci")
    )

    def __post_init__(self) -> None:
        self.rng = np.random.default_rng(self.seed)
        self.quarters = pd.period_range(
            self.profile.start,
            self.profile.end,
            freq="Q",
        )

    def simulate(self) -> pd.DataFrame:
        rows: list[dict[str, Any]] = []
        person_id = 0
        region_effects = {
            region: self.rng.normal(0, 0.18)
            for region in self.profile.regions
        }
        for quarter_index, quarter in enumerate(self.quarters):
            national_cycle = (
                0.10 * math.sin(quarter_index / 3.2)
                + 0.018 * quarter_index
            )
            for region in self.profile.regions:
                region_effect = region_effects[region]
                observations = self.profile.observations_per_region_quarter
                for _ in range(observations):
                    person_id += 1
                    age = int(self.rng.integers(16, 30))
                    sex = str(self.rng.choice(["F", "M"]))
                    education = self._education_group(age, quarter_index)
                    activity = self._activity_branch(
                        education,
                        region,
                        quarter_index,
                    )
                    status = self._labour_status(
                        education,
                        age,
                        activity,
                        region_effect,
                        national_cycle,
                    )
                    sample_weight = float(
                        self.rng.lognormal(mean=5.7, sigma=0.42)
                    )
                    rows.append(
                        {
                            "person_id": f"P{person_id:09d}",
                            "CCAA": region,
                            "PROV": region * 2
                            + int(self.rng.integers(0, 2)),
                            "EDAD1": age,
                            "SEXO": sex,
                            "AOI": status,
                            "FACTOREL": sample_weight,
                            "CICLO": 194 + quarter_index,
                            "NFORMA": self._nforma_code(education),
                            "ACT1": activity if status in {3, 4} else np.nan,
                            "education_group_truth": education,
                            "reference_quarter": str(quarter),
                            "source_file": (
                                f"epa_{quarter.year}t{quarter.quarter}.dta"
                            ),
                        }
                    )
        output = pd.DataFrame(rows)
        return self.inject_source_issues(output)

    def _education_group(self, age: int, time_index: int) -> str:
        fp_probability = np.clip(
            0.20
            + 0.014 * time_index
            + 0.07 * (18 <= age <= 23),
            0.12,
            0.48,
        )
        university_probability = np.clip(
            0.10 + 0.055 * max(age - 18, 0),
            0.05,
            0.44,
        )
        draw = self.rng.random()
        if draw < fp_probability:
            return "FP"
        if draw < fp_probability + university_probability:
            return "UNIVERSITY"
        if draw < 0.94:
            return "SECONDARY_OR_LOWER"
        return "OTHER"

    def _activity_branch(
        self,
        education: str,
        region: int,
        time_index: int,
    ) -> int:
        probabilities = np.array(
            [
                0.05,
                0.10,
                0.08,
                0.08,
                0.09,
                0.22,
                0.09,
                0.10,
                0.13,
                0.06,
            ],
            dtype=float,
        )
        if education == "FP":
            probabilities[[2, 3, 4, 6]] += np.array(
                [0.025, 0.035, 0.030, 0.020]
            )
            probabilities[[5, 8]] -= np.array([0.060, 0.050])
        if education == "UNIVERSITY":
            probabilities[[7, 8]] += np.array([0.070, 0.055])
            probabilities[[0, 4, 5]] -= np.array([0.025, 0.040, 0.060])
        green_expansion = min(0.035, 0.0022 * time_index)
        probabilities[[2, 3, 4]] += green_expansion / 3
        probabilities[5] -= green_expansion
        if region in {1, 5, 10, 11, 12}:
            probabilities[0] += 0.025
            probabilities[7] -= 0.025
        probabilities = np.clip(probabilities, 0.005, None)
        probabilities = probabilities / probabilities.sum()
        return int(self.rng.choice(np.arange(10), p=probabilities))

    def _labour_status(
        self,
        education: str,
        age: int,
        activity: int,
        region_effect: float,
        national_cycle: float,
    ) -> int:
        employment_score = (
            -0.40
            + 0.12 * (age - 18)
            + 0.36 * (education == "FP")
            + 0.48 * (education == "UNIVERSITY")
            + 0.16 * (activity in GREEN_CORE_ACTIVITIES)
            + region_effect
            + national_cycle
        )
        employment_probability = 1 / (1 + math.exp(-employment_score))
        inactivity_probability = np.clip(
            0.58
            - 0.055 * (age - 16)
            - 0.08 * (education == "FP")
            - 0.05 * (education == "UNIVERSITY"),
            0.06,
            0.72,
        )
        draw = self.rng.random()
        if draw < inactivity_probability:
            return int(self.rng.choice([7, 8, 9], p=[0.62, 0.25, 0.13]))
        if self.rng.random() < employment_probability:
            return int(self.rng.choice([3, 4], p=[0.82, 0.18]))
        return int(self.rng.choice([5, 6], p=[0.74, 0.26]))

    def _nforma_code(self, education: str) -> str:
        return {
            "FP": "SP",
            "SECONDARY_OR_LOWER": "SE",
            "UNIVERSITY": "UN",
            "OTHER": "OT",
        }[education]

    def inject_source_issues(self, frame: pd.DataFrame) -> pd.DataFrame:
        output = frame.copy()
        string_weight_rows = output.sample(
            frac=0.002,
            random_state=self.seed + 1,
        ).index
        output["FACTOREL"] = output["FACTOREL"].astype(object)
        output.loc[string_weight_rows, "FACTOREL"] = output.loc[
            string_weight_rows,
            "FACTOREL",
        ].map(lambda value: f"{float(value):.3f}")
        lower_rows = output.sample(
            frac=0.003,
            random_state=self.seed + 2,
        ).index
        output.loc[lower_rows, "NFORMA"] = output.loc[
            lower_rows,
            "NFORMA",
        ].astype(str).str.lower()
        missing_education_rows = output.sample(
            frac=0.004,
            random_state=self.seed + 3,
        ).index
        output.loc[missing_education_rows, "NFORMA"] = None
        return output


# ---------------------------------------------------------------------------
# Microdata harmonisation and validation
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class EpaVariable:
    name: str
    description: str
    nullable: bool
    expected_type: str
    minimum: float | None = None
    maximum: float | None = None


EPA_DICTIONARY: tuple[EpaVariable, ...] = (
    EpaVariable(
        "person_id",
        "Synthetic row identifier.",
        False,
        "string",
    ),
    EpaVariable(
        "CCAA",
        "Autonomous community code.",
        False,
        "integer",
        1,
        19,
    ),
    EpaVariable(
        "PROV",
        "Synthetic province code.",
        False,
        "integer",
        1,
        99,
    ),
    EpaVariable(
        "EDAD1",
        "Age in completed years.",
        False,
        "integer",
        16,
        99,
    ),
    EpaVariable(
        "AOI",
        "Labour-market status code.",
        False,
        "integer",
        3,
        9,
    ),
    EpaVariable(
        "FACTOREL",
        "Survey expansion factor.",
        False,
        "float",
        0,
        None,
    ),
    EpaVariable(
        "CICLO",
        "Quarter sequence index.",
        False,
        "integer",
        194,
        None,
    ),
    EpaVariable(
        "NFORMA",
        "Education/training group code.",
        True,
        "string",
    ),
    EpaVariable(
        "ACT1",
        "Broad economic activity, available for employed respondents.",
        True,
        "integer",
        0,
        9,
    ),
)


class EpaHarmoniser:
    """Apply the type and classification rules present in the Stata workflow."""

    numeric_columns = [
        "CCAA",
        "PROV",
        "EDAD1",
        "AOI",
        "FACTOREL",
        "CICLO",
        "ACT1",
    ]

    def harmonise(
        self,
        frame: pd.DataFrame,
        *,
        maximum_age: int = 25,
        include_missing_as_non_fp: bool = True,
    ) -> pd.DataFrame:
        output = frame.copy()
        self._assert_required_columns(output)
        for column in self.numeric_columns:
            output[column] = pd.to_numeric(output[column], errors="coerce")
        output["NFORMA"] = (
            output["NFORMA"]
            .astype("string")
            .str.strip()
            .str.upper()
            .replace({"": pd.NA, "<NA>": pd.NA})
        )
        output = output.loc[output["EDAD1"] < maximum_age].copy()
        output = output.dropna(subset=["AOI", "CCAA", "CICLO", "FACTOREL"])
        output["quarter_period"] = period_from_cycle(output["CICLO"])
        output["year"] = output["quarter_period"].map(
            lambda period: period.year
        )
        output["quarter"] = output["quarter_period"].map(
            lambda period: period.quarter
        )
        output["period"] = output["quarter_period"].astype(str)
        output["ccaa_name"] = output["CCAA"].astype(int).map(CCAA_LABELS)
        output["labour_status"] = output["AOI"].astype(int).map(
            LABOUR_STATUS_LABELS
        )
        output["employed"] = output["labour_status"].eq("employed")
        output["unemployed"] = output["labour_status"].eq("unemployed")
        output["inactive"] = output["labour_status"].eq("inactive")
        output["active"] = output["employed"] | output["unemployed"]
        output["fp_group"] = pd.Series(
            np.nan,
            index=output.index,
            dtype=float,
        )
        observed_education = output["NFORMA"].notna()
        fp_observation = output["NFORMA"].eq("SP").fillna(False)
        output.loc[observed_education & ~fp_observation, "fp_group"] = 0.0
        output.loc[fp_observation, "fp_group"] = 1.0
        if include_missing_as_non_fp:
            output["fp_group"] = output["fp_group"].fillna(0)
        output["education_group"] = output["NFORMA"].map(
            {
                "SP": "FP",
                "SE": "SECONDARY_OR_LOWER",
                "UN": "UNIVERSITY",
                "OT": "OTHER",
            }
        )
        if include_missing_as_non_fp:
            output["education_group"] = output[
                "education_group"
            ].fillna("OTHER")
        output["act1"] = output["ACT1"].where(
            output["ACT1"].between(0, 9),
            99,
        )
        output["act1"] = output["act1"].fillna(99).astype(int)
        output["activity_name"] = output["act1"].map(ACTIVITY_LABELS)
        output["green_core"] = output["act1"].isin(
            GREEN_CORE_ACTIVITIES
        )
        output["green_broad"] = output["act1"].isin(
            GREEN_BROAD_ACTIVITIES
        )
        output["digital_proxy"] = output["act1"].isin(
            DIGITAL_PROXY_ACTIVITIES
        )
        return output.reset_index(drop=True)

    def _assert_required_columns(self, frame: pd.DataFrame) -> None:
        required = {variable.name for variable in EPA_DICTIONARY}
        missing = required.difference(frame.columns)
        if missing:
            raise ValueError(f"EPA extract misses columns: {sorted(missing)}")

    def validation_report(self, frame: pd.DataFrame) -> pd.DataFrame:
        rows: list[dict[str, Any]] = []
        for variable in EPA_DICTIONARY:
            if variable.name not in frame:
                rows.append(
                    {
                        "variable": variable.name,
                        "check": "required_column",
                        "failures": 1,
                        "status": "fail",
                        "detail": variable.description,
                    }
                )
                continue
            values = frame[variable.name]
            missing = int(values.isna().sum())
            rows.append(
                {
                    "variable": variable.name,
                    "check": "nullability",
                    "failures": missing if not variable.nullable else 0,
                    "status": (
                        "fail"
                        if missing and not variable.nullable
                        else "pass"
                    ),
                    "detail": variable.description,
                }
            )
            if variable.minimum is not None or variable.maximum is not None:
                numeric = pd.to_numeric(values, errors="coerce")
                invalid = pd.Series(False, index=frame.index)
                if variable.minimum is not None:
                    invalid |= numeric < variable.minimum
                if variable.maximum is not None:
                    invalid |= numeric > variable.maximum
                failures = int(invalid.fillna(False).sum())
                rows.append(
                    {
                        "variable": variable.name,
                        "check": "range",
                        "failures": failures,
                        "status": "pass" if failures == 0 else "fail",
                        "detail": (
                            f"[{variable.minimum}, {variable.maximum}]"
                        ),
                    }
                )
        duplicate_people = int(frame["person_id"].duplicated().sum())
        rows.append(
            {
                "variable": "person_id",
                "check": "unique_identifier",
                "failures": duplicate_people,
                "status": "pass" if duplicate_people == 0 else "fail",
                "detail": "One row per synthetic respondent.",
            }
        )
        return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Weighted labour-market indicators
# ---------------------------------------------------------------------------


def aggregate_labour_market(
    microdata: pd.DataFrame,
    *,
    grouping: Sequence[str],
) -> pd.DataFrame:
    """Create weighted denominators once, then derive all rates consistently."""

    rows: list[dict[str, Any]] = []
    for keys, part in microdata.groupby(list(grouping), dropna=False):
        if not isinstance(keys, tuple):
            keys = (keys,)
        row = dict(zip(grouping, keys))
        total_young = float(part["FACTOREL"].sum())
        employed = weighted_sum(part, part["employed"])
        unemployed = weighted_sum(part, part["unemployed"])
        inactive = weighted_sum(part, part["inactive"])
        active = employed + unemployed
        row.update(
            {
                "total_young": total_young,
                "employed": employed,
                "unemployed": unemployed,
                "inactive": inactive,
                "active": active,
                "sample_observations": len(part),
            }
        )
        rows.append(row)
    output = pd.DataFrame(rows)
    output["unemployment_rate"] = (
        100 * safe_divide(output["unemployed"], output["active"])
    )
    output["employment_active_rate"] = (
        100 * safe_divide(output["employed"], output["active"])
    )
    output["employment_population_rate"] = (
        100 * safe_divide(output["employed"], output["total_young"])
    )
    output["activity_rate"] = (
        100 * safe_divide(output["active"], output["total_young"])
    )
    identity_gap = (
        output["total_young"]
        - output[["employed", "unemployed", "inactive"]].sum(axis=1)
    )
    output["population_identity_gap"] = identity_gap
    return output


def fp_nofp_quarterly_panel(microdata: pd.DataFrame) -> pd.DataFrame:
    panel = aggregate_labour_market(
        microdata.dropna(subset=["fp_group"]),
        grouping=[
            "CCAA",
            "ccaa_name",
            "year",
            "quarter",
            "period",
            "quarter_period",
            "fp_group",
        ],
    )
    panel = rolling_four_quarter_sum(
        panel,
        group=["CCAA", "fp_group"],
        columns=[
            "total_young",
            "employed",
            "unemployed",
            "inactive",
            "active",
        ],
    )
    panel["unemployment_rate_4q"] = (
        100 * safe_divide(panel["unemployed_4q"], panel["active_4q"])
    )
    panel["employment_active_rate_4q"] = (
        100 * safe_divide(panel["employed_4q"], panel["active_4q"])
    )
    panel["employment_population_rate_4q"] = (
        100
        * safe_divide(panel["employed_4q"], panel["total_young_4q"])
    )
    panel["activity_rate_4q"] = (
        100 * safe_divide(panel["active_4q"], panel["total_young_4q"])
    )
    panel["fp_label"] = panel["fp_group"].map(
        {0.0: "Non-FP", 1.0: "FP"}
    )
    return panel


def fp_comparison_wide(panel: pd.DataFrame) -> pd.DataFrame:
    measures = [
        "unemployment_rate",
        "employment_active_rate",
        "employment_population_rate",
        "activity_rate",
        "unemployment_rate_4q",
        "employment_active_rate_4q",
        "employment_population_rate_4q",
        "activity_rate_4q",
    ]
    index = [
        "CCAA",
        "ccaa_name",
        "year",
        "quarter",
        "period",
        "quarter_period",
    ]
    wide = panel.pivot_table(
        index=index,
        columns="fp_group",
        values=measures,
        aggfunc="first",
    ).reset_index()
    wide.columns = [
        (
            str(column)
            if not isinstance(column, tuple)
            else (
                str(column[0])
                if column[1] == ""
                else f"{column[0]}_{'fp' if column[1] == 1 else 'nonfp'}"
            )
        )
        for column in wide.columns
    ]
    for measure in measures:
        fp = f"{measure}_fp"
        nonfp = f"{measure}_nonfp"
        if fp in wide and nonfp in wide:
            wide[f"gap_{measure}_fp_minus_nonfp"] = wide[fp] - wide[nonfp]
    return wide


def education_comparison_panel(microdata: pd.DataFrame) -> pd.DataFrame:
    relevant = microdata.loc[
        microdata["education_group"].isin(
            ["FP", "SECONDARY_OR_LOWER", "UNIVERSITY"]
        )
    ].copy()
    panel = aggregate_labour_market(
        relevant,
        grouping=[
            "CCAA",
            "ccaa_name",
            "quarter_period",
            "period",
            "education_group",
        ],
    )
    panel = rolling_four_quarter_sum(
        panel,
        group=["CCAA", "education_group"],
        columns=[
            "total_young",
            "employed",
            "unemployed",
            "active",
        ],
    )
    panel["unemployment_rate_4q"] = (
        100 * safe_divide(panel["unemployed_4q"], panel["active_4q"])
    )
    panel["employment_rate_4q"] = (
        100 * safe_divide(panel["employed_4q"], panel["total_young_4q"])
    )
    panel["education_label"] = panel["education_group"].map(
        EDUCATION_LABELS
    )
    return panel


def comparison_gaps(panel: pd.DataFrame) -> pd.DataFrame:
    index = ["CCAA", "ccaa_name", "quarter_period", "period"]
    wide = panel.pivot_table(
        index=index,
        columns="education_group",
        values=["unemployment_rate_4q", "employment_rate_4q"],
        aggfunc="first",
    ).reset_index()
    wide.columns = [
        (
            str(column)
            if not isinstance(column, tuple)
            else (
                str(column[0])
                if column[1] == ""
                else f"{column[0]}_{column[1].lower()}"
            )
        )
        for column in wide.columns
    ]
    for comparator in ("secondary_or_lower", "university"):
        wide[f"unemployment_gap_fp_vs_{comparator}"] = (
            wide["unemployment_rate_4q_fp"]
            - wide[f"unemployment_rate_4q_{comparator}"]
        )
        wide[f"employment_gap_fp_vs_{comparator}"] = (
            wide["employment_rate_4q_fp"]
            - wide[f"employment_rate_4q_{comparator}"]
        )
    return wide


# ---------------------------------------------------------------------------
# Activity branches, green axis and complete zero-cell panels
# ---------------------------------------------------------------------------


def activity_denominators(microdata: pd.DataFrame) -> pd.DataFrame:
    return aggregate_labour_market(
        microdata.dropna(subset=["fp_group"]),
        grouping=[
            "CCAA",
            "ccaa_name",
            "year",
            "quarter",
            "period",
            "quarter_period",
            "fp_group",
        ],
    )


def employed_by_activity(microdata: pd.DataFrame) -> pd.DataFrame:
    employed = microdata.loc[
        microdata["employed"] & microdata["fp_group"].notna()
    ].copy()
    employed["weighted_employed"] = employed["FACTOREL"]
    return (
        employed.groupby(
            [
                "CCAA",
                "ccaa_name",
                "year",
                "quarter",
                "period",
                "quarter_period",
                "fp_group",
                "act1",
                "activity_name",
            ],
            as_index=False,
            dropna=False,
        )
        .agg(
            employed_activity=("weighted_employed", "sum"),
            sample_employed=("person_id", "size"),
        )
    )


def complete_activity_grid(
    denominators: pd.DataFrame,
    activity: pd.DataFrame,
) -> pd.DataFrame:
    keys = [
        "CCAA",
        "ccaa_name",
        "year",
        "quarter",
        "period",
        "quarter_period",
        "fp_group",
    ]
    activity_reference = pd.DataFrame(
        {
            "act1": list(ACTIVITY_LABELS),
            "activity_name": list(ACTIVITY_LABELS.values()),
        }
    )
    base = denominators[keys].drop_duplicates().copy()
    base["_join"] = 1
    activity_reference["_join"] = 1
    grid = base.merge(activity_reference, on="_join").drop(columns="_join")
    output = grid.merge(
        activity,
        on=[*keys, "act1", "activity_name"],
        how="left",
        validate="one_to_one",
    )
    output["employed_activity"] = output["employed_activity"].fillna(0)
    output["sample_employed"] = output["sample_employed"].fillna(0)
    denominator_columns = [
        "total_young",
        "employed",
        "unemployed",
        "inactive",
        "active",
    ]
    output = output.merge(
        denominators[keys + denominator_columns],
        on=keys,
        how="left",
        validate="many_to_one",
    )
    output["activity_employment_active_rate"] = (
        100 * safe_divide(output["employed_activity"], output["active"])
    )
    output["activity_employment_share"] = (
        100 * safe_divide(output["employed_activity"], output["employed"])
    )
    output["green_core"] = output["act1"].isin(GREEN_CORE_ACTIVITIES)
    output["green_broad"] = output["act1"].isin(GREEN_BROAD_ACTIVITIES)
    output["digital_proxy"] = output["act1"].isin(
        DIGITAL_PROXY_ACTIVITIES
    )
    return output


def activity_panel(microdata: pd.DataFrame) -> pd.DataFrame:
    denominators = activity_denominators(microdata)
    activity = employed_by_activity(microdata)
    panel = complete_activity_grid(denominators, activity)
    panel = rolling_four_quarter_sum(
        panel,
        group=["CCAA", "fp_group", "act1"],
        columns=["employed_activity", "employed", "active"],
    )
    panel["employed_activity_4q_average"] = (
        panel["employed_activity_4q"] / 4
    )
    panel["activity_share_4q"] = (
        100
        * safe_divide(panel["employed_activity_4q"], panel["employed_4q"])
    )
    panel["activity_active_rate_4q"] = (
        100
        * safe_divide(panel["employed_activity_4q"], panel["active_4q"])
    )
    baseline = (
        panel.loc[panel["year"] == 2021]
        .groupby(["CCAA", "fp_group", "act1"])["employed_activity_4q"]
        .mean()
        .rename("baseline_2021")
    )
    panel = panel.merge(
        baseline,
        on=["CCAA", "fp_group", "act1"],
        how="left",
    )
    panel["employment_index_2021_100"] = (
        100
        * safe_divide(panel["employed_activity_4q"], panel["baseline_2021"])
    )
    return panel


def check_activity_shares(panel: pd.DataFrame) -> pd.DataFrame:
    usable = panel.loc[panel["act1"].between(0, 9)].copy()
    grouped = (
        usable.groupby(
            ["CCAA", "fp_group", "quarter_period"],
            as_index=False,
        )["activity_employment_share"]
        .sum()
        .rename(columns={"activity_employment_share": "share_sum"})
    )
    grouped["absolute_gap_from_100"] = (grouped["share_sum"] - 100).abs()
    grouped["status"] = np.where(
        grouped["absolute_gap_from_100"] <= 1e-8,
        "pass",
        "review",
    )
    return grouped


def green_employment_panel(activity: pd.DataFrame) -> pd.DataFrame:
    core = activity.loc[activity["green_core"]].copy()
    grouping = [
        "CCAA",
        "ccaa_name",
        "year",
        "quarter",
        "period",
        "quarter_period",
        "fp_group",
    ]
    output = (
        core.groupby(grouping, as_index=False)
        .agg(
            green_employed=("employed_activity", "sum"),
            employed=("employed", "mean"),
            active=("active", "mean"),
            total_young=("total_young", "mean"),
        )
        .sort_values(["CCAA", "fp_group", "quarter_period"])
    )
    output = rolling_four_quarter_sum(
        output,
        group=["CCAA", "fp_group"],
        columns=[
            "green_employed",
            "employed",
            "active",
            "total_young",
        ],
    )
    output["green_employed_4q_average_thousand"] = (
        output["green_employed_4q"] / 4 / 1000
    )
    output["green_employment_share_4q"] = (
        100
        * safe_divide(output["green_employed_4q"], output["employed_4q"])
    )
    output["green_active_rate_4q"] = (
        100
        * safe_divide(output["green_employed_4q"], output["active_4q"])
    )
    baseline = (
        output.loc[output["year"] == 2021]
        .groupby(["CCAA", "fp_group"])["green_employed_4q"]
        .mean()
        .rename("green_baseline_2021")
    )
    output = output.merge(
        baseline,
        on=["CCAA", "fp_group"],
        how="left",
    )
    output["green_index_2021_100"] = (
        100
        * safe_divide(
            output["green_employed_4q"],
            output["green_baseline_2021"],
        )
    )
    output["classification_note"] = (
        "Employment in broad branches linked to the green transition; "
        "not a direct measure of green jobs."
    )
    return output


# ---------------------------------------------------------------------------
# Synthetic PRTR administrative data and territorial matching
# ---------------------------------------------------------------------------


@dataclass
class PrtrTrainingFactory:
    seed: int = 2030
    years: tuple[int, ...] = (2021, 2022, 2023)

    def __post_init__(self) -> None:
        self.rng = np.random.default_rng(self.seed)

    def simulate_projects(self) -> pd.DataFrame:
        rows: list[dict[str, Any]] = []
        project_number = 0
        for year in self.years:
            for region_code, region_name in CCAA_LABELS.items():
                if region_code in {18, 19}:
                    continue
                projects = int(self.rng.integers(4, 11))
                for _ in range(projects):
                    project_number += 1
                    green_axis = bool(
                        self.rng.random()
                        < 0.34 + 0.05 * (year - self.years[0])
                    )
                    places = int(
                        self.rng.lognormal(
                            mean=5.3 + 0.25 * green_axis,
                            sigma=0.55,
                        )
                    )
                    committed = float(
                        places
                        * self.rng.uniform(4_500, 10_500)
                    )
                    rows.append(
                        {
                            "project_id": f"FP-{year}-{project_number:05d}",
                            "region_reported": self._noisy_region(
                                region_name,
                                project_number,
                            ),
                            "year_prtr": year,
                            "places_created": places,
                            "green_axis": int(green_axis),
                            "digital_axis": int(
                                self.rng.random() < 0.28
                            ),
                            "committed_investment_eur": committed,
                            "executed_investment_eur": committed
                            * self.rng.uniform(0.68, 1.02),
                            "provider_type": str(
                                self.rng.choice(
                                    [
                                        "public_training_centre",
                                        "regional_network",
                                        "sectoral_partnership",
                                    ],
                                    p=[0.64, 0.23, 0.13],
                                )
                            ),
                            "source_system": str(
                                self.rng.choice(
                                    [
                                        "ministry_extract",
                                        "regional_portal",
                                        "milestone_file",
                                    ]
                                )
                            ),
                        }
                    )
        return pd.DataFrame(rows)

    def _noisy_region(self, value: str, project_number: int) -> str:
        variations = {
            "Andalucía": ["Andalucia", "Junta de Andalucía"],
            "Illes Balears": ["Baleares", "Illes Balears"],
            "Castilla y León": ["Castilla-Leon", "Castilla y León"],
            "Castilla-La Mancha": [
                "Castilla La Mancha",
                "Castilla-La Mancha",
            ],
            "Comunitat Valenciana": [
                "Comunidad Valenciana",
                "C. Valenciana",
            ],
            "Comunidad de Madrid": ["Madrid", "Comunidad Madrid"],
            "Región de Murcia": ["Murcia", "Región Murcia"],
            "País Vasco": ["Pais Vasco", "Euskadi"],
        }
        candidates = variations.get(value, [value])
        return candidates[project_number % len(candidates)]


@dataclass(frozen=True)
class FuzzyMatch:
    reported_name: str
    official_name: str
    official_code: int
    score: float
    method: str
    accepted: bool


class TerritorialMatcher:
    """Exact aliases first, transparent fuzzy comparison second."""

    def __init__(
        self,
        official: dict[int, str] | None = None,
        threshold: float = 0.78,
    ):
        self.official = official or CCAA_LABELS
        self.threshold = threshold
        self.aliases = {
            "JUNTA DE ANDALUCIA": "ANDALUCIA",
            "BALEARES": "BALEARS",
            "C VALENCIANA": "VALENCIANA",
            "COMUNIDAD VALENCIANA": "VALENCIANA",
            "MADRID": "MADRID",
            "COMUNIDAD MADRID": "MADRID",
            "MURCIA": "MURCIA",
            "REGION MURCIA": "MURCIA",
            "EUSKADI": "VASCO",
            "PAIS VASCO": "VASCO",
        }
        self.normalised_official = {
            code: normalise_spanish_name(name)
            for code, name in self.official.items()
        }

    def match_one(self, value: Any) -> FuzzyMatch:
        reported = "" if pd.isna(value) else str(value)
        normalised = normalise_spanish_name(reported)
        normalised = self.aliases.get(normalised, normalised)
        exact = [
            code
            for code, official_name in self.normalised_official.items()
            if official_name == normalised
            or official_name.endswith(normalised)
            or normalised.endswith(official_name)
        ]
        if exact:
            code = exact[0]
            return FuzzyMatch(
                reported_name=reported,
                official_name=self.official[code],
                official_code=code,
                score=1.0,
                method="normalised_exact_or_alias",
                accepted=True,
            )
        scored = [
            (
                SequenceMatcher(
                    None,
                    normalised,
                    official_name,
                ).ratio(),
                code,
            )
            for code, official_name in self.normalised_official.items()
        ]
        score, code = max(scored)
        return FuzzyMatch(
            reported_name=reported,
            official_name=self.official[code],
            official_code=code,
            score=float(score),
            method="sequence_similarity",
            accepted=bool(score >= self.threshold),
        )

    def apply(
        self,
        frame: pd.DataFrame,
        column: str,
    ) -> tuple[pd.DataFrame, pd.DataFrame]:
        unique_values = frame[column].drop_duplicates().tolist()
        matches = [self.match_one(value) for value in unique_values]
        audit = pd.DataFrame(asdict(match) for match in matches)
        mapping_code = dict(
            zip(audit["reported_name"], audit["official_code"])
        )
        mapping_name = dict(
            zip(audit["reported_name"], audit["official_name"])
        )
        mapping_accepted = dict(
            zip(audit["reported_name"], audit["accepted"])
        )
        output = frame.copy()
        output["CCAA"] = output[column].map(mapping_code)
        output["ccaa_name"] = output[column].map(mapping_name)
        output["territorial_match_accepted"] = output[column].map(
            mapping_accepted
        )
        return output, audit


def aggregate_prtr_projects(
    projects: pd.DataFrame,
) -> pd.DataFrame:
    output = (
        projects.groupby(
            ["CCAA", "ccaa_name", "year_prtr"],
            as_index=False,
        )
        .agg(
            total_places_prtr=("places_created", "sum"),
            green_places_prtr=(
                "places_created",
                lambda values: float(
                    values[
                        projects.loc[values.index, "green_axis"].eq(1)
                    ].sum()
                ),
            ),
            digital_places_prtr=(
                "places_created",
                lambda values: float(
                    values[
                        projects.loc[values.index, "digital_axis"].eq(1)
                    ].sum()
                ),
            ),
            committed_investment_eur=(
                "committed_investment_eur",
                "sum",
            ),
            executed_investment_eur=(
                "executed_investment_eur",
                "sum",
            ),
            projects=("project_id", "nunique"),
        )
    )
    output["green_place_share"] = (
        100
        * safe_divide(
            output["green_places_prtr"],
            output["total_places_prtr"],
        )
    )
    output["digital_place_share"] = (
        100
        * safe_divide(
            output["digital_places_prtr"],
            output["total_places_prtr"],
        )
    )
    output["execution_rate"] = (
        100
        * safe_divide(
            output["executed_investment_eur"],
            output["committed_investment_eur"],
        )
    )
    return output


def annual_green_employment(
    green_panel: pd.DataFrame,
) -> pd.DataFrame:
    usable = green_panel.loc[
        green_panel["fp_group"].eq(1)
        & green_panel["green_employment_share_4q"].notna()
        & ~green_panel["CCAA"].isin([18, 19])
    ].copy()
    return (
        usable.groupby(
            ["CCAA", "ccaa_name", "year"],
            as_index=False,
        )
        .agg(
            green_share_annual=(
                "green_employment_share_4q",
                "mean",
            ),
            green_employed_thousand_annual=(
                "green_employed_4q_average_thousand",
                "mean",
            ),
            green_index_annual=("green_index_2021_100", "mean"),
            available_quarters=("quarter_period", "nunique"),
        )
    )


def lagged_prtr_green_linkage(
    prtr: pd.DataFrame,
    green_annual: pd.DataFrame,
    *,
    lag_years: int = 2,
) -> pd.DataFrame:
    """Descriptive t-to-t+lag linkage matching the documented Stata design."""

    baseline = green_annual.rename(
        columns={
            "year": "year_prtr",
            "green_share_annual": "green_share_t",
            "green_employed_thousand_annual": "green_employed_thousand_t",
            "green_index_annual": "green_index_t",
            "available_quarters": "available_quarters_t",
        }
    )
    future = green_annual.copy()
    future["year_prtr"] = future["year"] - lag_years
    future = future.rename(
        columns={
            "year": "year_outcome",
            "green_share_annual": "green_share_t_lag",
            "green_employed_thousand_annual": (
                "green_employed_thousand_t_lag"
            ),
            "green_index_annual": "green_index_t_lag",
            "available_quarters": "available_quarters_t_lag",
        }
    )
    linkage = prtr.merge(
        baseline[
            [
                "CCAA",
                "year_prtr",
                "green_share_t",
                "green_employed_thousand_t",
                "green_index_t",
                "available_quarters_t",
            ]
        ],
        on=["CCAA", "year_prtr"],
        how="inner",
        validate="one_to_one",
    )
    linkage = linkage.merge(
        future[
            [
                "CCAA",
                "year_prtr",
                "year_outcome",
                "green_share_t_lag",
                "green_employed_thousand_t_lag",
                "green_index_t_lag",
                "available_quarters_t_lag",
            ]
        ],
        on=["CCAA", "year_prtr"],
        how="inner",
        validate="one_to_one",
    )
    linkage["change_green_share_pp"] = (
        linkage["green_share_t_lag"] - linkage["green_share_t"]
    )
    linkage["change_green_employed_thousand"] = (
        linkage["green_employed_thousand_t_lag"]
        - linkage["green_employed_thousand_t"]
    )
    linkage["change_green_index"] = (
        linkage["green_index_t_lag"] - linkage["green_index_t"]
    )
    linkage["places_per_1000_young_green_workers"] = (
        linkage["green_places_prtr"]
        / linkage["green_employed_thousand_t"].replace(0, np.nan)
    )
    linkage["interpretation"] = (
        "Descriptive regional association; not a causal effect estimate."
    )
    return linkage


def descriptive_linkage_regression(
    linkage: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    variables = [
        "green_places_prtr",
        "green_share_t",
        "committed_investment_eur",
    ]
    model = linkage.dropna(
        subset=["change_green_share_pp", *variables]
    ).copy()
    model["log_green_places"] = np.log1p(model["green_places_prtr"])
    model["log_committed_investment"] = np.log1p(
        model["committed_investment_eur"]
    )
    regressors = [
        "log_green_places",
        "green_share_t",
        "log_committed_investment",
    ]
    design = add_constant(model[regressors])
    result = ols_fit(model["change_green_share_pp"], design)
    table = regression_table(
        ["const", *regressors],
        result["beta"],
        result["vcov"],
    )
    table["interpretation"] = (
        "Conditional descriptive association only; no causal claim."
    )
    diagnostics = pd.DataFrame(
        [
            {
                "observations": result["nobs"],
                "r_squared": result["r2"],
                "outcome": "change_green_share_pp",
                "lag_years": 2,
                "causal_design": False,
                "main_limitation": (
                    "Regional allocation is not randomly assigned and "
                    "parallel trends are not established."
                ),
            }
        ]
    )
    return table, diagnostics


# ---------------------------------------------------------------------------
# Milestones, KPIs and reproducible policy reporting
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class KpiDefinition:
    kpi_id: str
    name: str
    numerator: str
    denominator: str | None
    unit: str
    aggregation: str
    target: float
    direction: str
    owner: str
    evidence_table: str


KPI_REGISTRY: tuple[KpiDefinition, ...] = (
    KpiDefinition(
        kpi_id="FP_01",
        name="Training places created",
        numerator="total_places_prtr",
        denominator=None,
        unit="places",
        aggregation="sum",
        target=30_000,
        direction="at_least",
        owner="education_policy",
        evidence_table="prtr_region_year",
    ),
    KpiDefinition(
        kpi_id="FP_02",
        name="Green-axis place share",
        numerator="green_places_prtr",
        denominator="total_places_prtr",
        unit="percent",
        aggregation="ratio_of_sums",
        target=30,
        direction="at_least",
        owner="green_transition",
        evidence_table="prtr_region_year",
    ),
    KpiDefinition(
        kpi_id="FP_03",
        name="Digital-axis place share",
        numerator="digital_places_prtr",
        denominator="total_places_prtr",
        unit="percent",
        aggregation="ratio_of_sums",
        target=22,
        direction="at_least",
        owner="digital_transition",
        evidence_table="prtr_region_year",
    ),
    KpiDefinition(
        kpi_id="FP_04",
        name="Investment execution",
        numerator="executed_investment_eur",
        denominator="committed_investment_eur",
        unit="percent",
        aggregation="ratio_of_sums",
        target=85,
        direction="at_least",
        owner="programme_management",
        evidence_table="prtr_region_year",
    ),
    KpiDefinition(
        kpi_id="FP_05",
        name="Territorial coverage",
        numerator="CCAA",
        denominator=None,
        unit="regions",
        aggregation="nunique",
        target=17,
        direction="at_least",
        owner="programme_management",
        evidence_table="prtr_region_year",
    ),
)


def evaluate_kpis(prtr: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    for definition in KPI_REGISTRY:
        if definition.aggregation == "sum":
            value = float(prtr[definition.numerator].sum())
        elif definition.aggregation == "nunique":
            value = float(prtr[definition.numerator].nunique())
        elif definition.aggregation == "ratio_of_sums":
            assert definition.denominator is not None
            numerator = float(prtr[definition.numerator].sum())
            denominator = float(prtr[definition.denominator].sum())
            value = 100 * numerator / denominator if denominator else np.nan
        else:
            raise ValueError(
                f"Unsupported KPI aggregation: {definition.aggregation}"
            )
        if definition.direction == "at_least":
            achieved = bool(value >= definition.target)
        elif definition.direction == "at_most":
            achieved = bool(value <= definition.target)
        else:
            raise ValueError(
                f"Unsupported KPI direction: {definition.direction}"
            )
        rows.append(
            {
                **asdict(definition),
                "actual": value,
                "achieved": achieved,
                "distance_to_target": value - definition.target,
            }
        )
    return pd.DataFrame(rows)


def milestone_evidence(
    projects: pd.DataFrame,
    kpis: pd.DataFrame,
) -> pd.DataFrame:
    source_counts = (
        projects.groupby("source_system", as_index=False)
        .agg(
            source_rows=("project_id", "size"),
            source_projects=("project_id", "nunique"),
            source_places=("places_created", "sum"),
            source_investment=("committed_investment_eur", "sum"),
        )
    )
    rows: list[dict[str, Any]] = []
    for kpi in kpis.itertuples(index=False):
        rows.append(
            {
                "evidence_id": f"EVIDENCE-{kpi.kpi_id}",
                "kpi_id": kpi.kpi_id,
                "reported_value": kpi.actual,
                "target": kpi.target,
                "status": "verified" if kpi.achieved else "pending",
                "source_rows": len(projects),
                "unique_projects": projects["project_id"].nunique(),
                "source_systems": "|".join(
                    sorted(projects["source_system"].unique())
                ),
                "reproducibility_note": (
                    "Computed from synthetic project-level records using "
                    "the versioned KPI registry."
                ),
            }
        )
    evidence = pd.DataFrame(rows)
    evidence.attrs["source_reconciliation"] = source_counts.to_dict("records")
    return evidence


# ---------------------------------------------------------------------------
# Outputs and end-to-end research project
# ---------------------------------------------------------------------------


@dataclass
class VocationalTrainingOutputs:
    microdata_validation: pd.DataFrame
    fp_quarterly_panel: pd.DataFrame
    fp_comparison: pd.DataFrame
    education_comparison: pd.DataFrame
    education_gaps: pd.DataFrame
    activity_panel: pd.DataFrame
    activity_share_checks: pd.DataFrame
    green_employment: pd.DataFrame
    territorial_match_audit: pd.DataFrame
    prtr_region_year: pd.DataFrame
    lagged_green_linkage: pd.DataFrame
    linkage_regression: pd.DataFrame
    linkage_diagnostics: pd.DataFrame
    kpi_status: pd.DataFrame
    milestone_evidence: pd.DataFrame


class VocationalTrainingEvaluation:
    """Run the synthetic replica from microdata to policy evidence."""

    def __init__(
        self,
        *,
        seed: int = 2029,
        profile: str = "ci",
    ):
        self.seed = seed
        self.profile_name = profile
        self.profile = epa_profile(profile)

    def run(self) -> VocationalTrainingOutputs:
        raw_microdata = EpaMicrodataFactory(
            seed=self.seed,
            profile=self.profile,
        ).simulate()
        harmoniser = EpaHarmoniser()
        validation = harmoniser.validation_report(raw_microdata)
        microdata = harmoniser.harmonise(
            raw_microdata,
            maximum_age=25,
            include_missing_as_non_fp=True,
        )
        fp_panel = fp_nofp_quarterly_panel(microdata)
        fp_wide = fp_comparison_wide(fp_panel)
        education = education_comparison_panel(microdata)
        education_gaps = comparison_gaps(education)
        activities = activity_panel(microdata)
        share_checks = check_activity_shares(activities)
        green = green_employment_panel(activities)

        raw_projects = PrtrTrainingFactory(seed=self.seed + 1).simulate_projects()
        matched_projects, match_audit = TerritorialMatcher().apply(
            raw_projects,
            "region_reported",
        )
        accepted_projects = matched_projects.loc[
            matched_projects["territorial_match_accepted"]
        ].copy()
        prtr = aggregate_prtr_projects(accepted_projects)
        green_annual = annual_green_employment(green)
        linkage = lagged_prtr_green_linkage(
            prtr,
            green_annual,
            lag_years=2,
        )
        regression, diagnostics = descriptive_linkage_regression(linkage)
        kpis = evaluate_kpis(prtr)
        evidence = milestone_evidence(accepted_projects, kpis)
        return VocationalTrainingOutputs(
            microdata_validation=validation,
            fp_quarterly_panel=fp_panel,
            fp_comparison=fp_wide,
            education_comparison=education,
            education_gaps=education_gaps,
            activity_panel=activities,
            activity_share_checks=share_checks,
            green_employment=green,
            territorial_match_audit=match_audit,
            prtr_region_year=prtr,
            lagged_green_linkage=linkage,
            linkage_regression=regression,
            linkage_diagnostics=diagnostics,
            kpi_status=kpis,
            milestone_evidence=evidence,
        )


def save_vocational_outputs(
    outputs: VocationalTrainingOutputs,
    root: str | Path,
) -> dict[str, Path]:
    destination = ensure_dir(Path(root) / "outputs" / "vocational_training")
    paths: dict[str, Path] = {}
    for name, frame in asdict(outputs).items():
        if not isinstance(frame, pd.DataFrame):
            continue
        path = destination / f"{name}.csv"
        frame.to_csv(path, index=False)
        paths[name] = path
    excel_path = destination / "vocational_training_review_pack.xlsx"
    try:
        with pd.ExcelWriter(excel_path) as writer:
            for name, frame in asdict(outputs).items():
                if isinstance(frame, pd.DataFrame):
                    frame.head(10_000).to_excel(
                        writer,
                        sheet_name=name[:31],
                        index=False,
                    )
        paths["excel_review_pack"] = excel_path
    except (ImportError, ModuleNotFoundError):
        pass
    return paths


def run_vocational_training_case(
    root: str | Path = ".",
    *,
    seed: int = 2029,
    profile: str = "ci",
) -> VocationalTrainingOutputs:
    outputs = VocationalTrainingEvaluation(
        seed=seed,
        profile=profile,
    ).run()
    save_vocational_outputs(outputs, root)
    return outputs


# ---------------------------------------------------------------------------
# Portfolio quality assurance
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class CheckResult:
    project: str
    check: str
    status: str
    observed: Any
    expected: str
    detail: str


def check(
    project: str,
    name: str,
    condition: bool,
    observed: Any,
    expected: str,
    detail: str,
) -> CheckResult:
    return CheckResult(
        project=project,
        check=name,
        status="pass" if bool(condition) else "fail",
        observed=observed,
        expected=expected,
        detail=detail,
    )


def vocational_acceptance_checks(
    outputs: VocationalTrainingOutputs,
) -> list[CheckResult]:
    results: list[CheckResult] = []
    results.append(
        check(
            "vocational_training",
            "validation_has_no_failures",
            not (outputs.microdata_validation["status"] == "fail").any(),
            int((outputs.microdata_validation["status"] == "fail").sum()),
            "0",
            "All non-null and range rules must pass after source coercion.",
        )
    )
    maximum_identity_gap = float(
        outputs.fp_quarterly_panel["population_identity_gap"].abs().max()
    )
    results.append(
        check(
            "vocational_training",
            "weighted_population_identity",
            maximum_identity_gap < 1e-8,
            maximum_identity_gap,
            "< 1e-8",
            "Employed + unemployed + inactive equals the weighted population.",
        )
    )
    maximum_share_gap = float(
        outputs.activity_share_checks["absolute_gap_from_100"].max()
    )
    results.append(
        check(
            "vocational_training",
            "activity_shares_sum_to_100",
            maximum_share_gap < 1e-8,
            maximum_share_gap,
            "< 1e-8",
            "Activity shares use one unrepeated employed denominator.",
        )
    )
    accepted_matches = float(
        outputs.territorial_match_audit["accepted"].mean()
    )
    results.append(
        check(
            "vocational_training",
            "territorial_matches_reviewed",
            accepted_matches == 1.0,
            accepted_matches,
            "1.0",
            "Every unique reported region has an accepted auditable match.",
        )
    )
    results.append(
        check(
            "vocational_training",
            "lagged_linkage_nonempty",
            len(outputs.lagged_green_linkage) > 0,
            len(outputs.lagged_green_linkage),
            "> 0",
            "PRTR years have both t and t+2 synthetic labour outcomes.",
        )
    )
    causal_flag = bool(
        outputs.linkage_diagnostics["causal_design"].iloc[0]
    )
    results.append(
        check(
            "vocational_training",
            "descriptive_design_labelled",
            not causal_flag,
            causal_flag,
            "False",
            "Regional correlations are not advertised as causal effects.",
        )
    )
    return results


def deterministic_output_check(
    *,
    seed: int,
    profile: str,
) -> CheckResult:
    """Confirm that the same seed reproduces the policy evidence exactly."""

    first = VocationalTrainingEvaluation(
        seed=seed,
        profile=profile,
    ).run()
    second = VocationalTrainingEvaluation(
        seed=seed,
        profile=profile,
    ).run()
    first_payload = first.kpi_status.sort_values("kpi_id").to_csv(index=False)
    second_payload = second.kpi_status.sort_values("kpi_id").to_csv(index=False)
    first_hash = hashlib.sha256(first_payload.encode("utf-8")).hexdigest()
    second_hash = hashlib.sha256(second_payload.encode("utf-8")).hexdigest()
    return check(
        "vocational_training_prtr",
        "deterministic_seed",
        first_hash == second_hash,
        first_hash,
        second_hash,
        "Repeated runs create identical KPI evidence.",
    )


def project_acceptance_checks(
    outputs: VocationalTrainingOutputs,
    *,
    seed: int,
    profile: str,
) -> pd.DataFrame:
    results = [
        *vocational_acceptance_checks(outputs),
        deterministic_output_check(seed=seed, profile=profile),
    ]
    return pd.DataFrame(asdict(result) for result in results)


def build_project_report(
    outputs: VocationalTrainingOutputs,
    checks: pd.DataFrame,
) -> str:
    achieved = int(outputs.kpi_status["achieved"].sum())
    latest = (
        outputs.fp_quarterly_panel.loc[
            outputs.fp_quarterly_panel["fp_group"].eq(1)
            & outputs.fp_quarterly_panel["unemployment_rate_4q"].notna()
        ]
        .sort_values("quarter_period")
        .tail(17)
    )
    lines = [
        "# Vocational Training and PRTR Evaluation",
        "",
        "**Author: Jose Camas Garrdiow**",
        "",
        "This report is generated from synthetic EPA-style microdata and "
        "synthetic project records. It is not an official evaluation.",
        "",
        "## Project scale",
        "",
        f"- FP region-quarter cells: {len(outputs.fp_quarterly_panel):,}",
        f"- Complete activity cells: {len(outputs.activity_panel):,}",
        f"- PRTR region-year observations: {len(outputs.prtr_region_year):,}",
        f"- Linked t-to-t+2 observations: "
        f"{len(outputs.lagged_green_linkage):,}",
        f"- Synthetic KPIs achieved: {achieved}/{len(outputs.kpi_status)}",
        "",
        "## KPI status",
        "",
        markdown_table(
            outputs.kpi_status[
                ["kpi_id", "name", "actual", "target", "achieved"]
            ]
        ),
        "",
        "## Latest FP labour-market indicators",
        "",
        markdown_table(
            latest[
                [
                    "ccaa_name",
                    "period",
                    "unemployment_rate_4q",
                    "employment_population_rate_4q",
                ]
            ].round(2)
        ),
        "",
        "## Acceptance checks",
        "",
        markdown_table(checks),
        "",
        "## Identification boundary",
        "",
        "The regional relationship between PRTR places in year t and "
        "green-linked employment in t+2 is descriptive. Allocation is not "
        "random, a counterfactual is not established and no causal effect is "
        "claimed.",
    ]
    return "\n".join(lines) + "\n"


def build_project_dashboard(
    outputs: VocationalTrainingOutputs,
    checks: pd.DataFrame,
) -> str:
    kpis = outputs.kpi_status[
        ["kpi_id", "name", "actual", "target", "achieved"]
    ].to_html(index=False)
    matches = outputs.territorial_match_audit.to_html(index=False)
    check_table = checks.to_html(index=False)
    latest = (
        outputs.fp_quarterly_panel.loc[
            outputs.fp_quarterly_panel["fp_group"].eq(1)
            & outputs.fp_quarterly_panel["unemployment_rate_4q"].notna()
        ][
            [
                "ccaa_name",
                "period",
                "unemployment_rate_4q",
                "employment_population_rate_4q",
            ]
        ]
        .sort_values(["period", "ccaa_name"])
        .tail(34)
        .round(2)
        .to_html(index=False)
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Vocational Training and PRTR Evaluation</title>
  <style>
    body {{
      margin: 0 auto;
      max-width: 1100px;
      padding: 32px;
      color: #1d2939;
      background: #f8fafc;
      font-family: Arial, sans-serif;
      line-height: 1.45;
    }}
    .card {{
      background: white;
      border: 1px solid #d0d5dd;
      border-radius: 10px;
      margin: 18px 0;
      padding: 20px;
    }}
    .warning {{
      border-left: 5px solid #f79009;
      background: #fffaeb;
      padding: 12px 16px;
    }}
    table {{ width: 100%; border-collapse: collapse; font-size: 12px; }}
    th, td {{ border-bottom: 1px solid #e4e7ec; padding: 7px; }}
    th {{ background: #eef4ff; text-align: left; }}
  </style>
</head>
<body>
  <h1>Vocational Training and PRTR Evaluation</h1>
  <p>Jose Camas Garrdiow · independent synthetic research project.</p>
  <div class="warning"><strong>Interpretation:</strong> simulated values only.
  The t-to-t+2 regional exercise is descriptive and not causal.</div>
  <section class="card"><h2>KPI status</h2>{kpis}</section>
  <section class="card"><h2>Latest FP indicators</h2>{latest}</section>
  <section class="card"><h2>Territorial matching audit</h2>{matches}</section>
  <section class="card"><h2>Acceptance checks</h2>{check_table}</section>
</body>
</html>
"""


def artifact_manifest(root: str | Path) -> pd.DataFrame:
    root_path = Path(root)
    rows: list[dict[str, Any]] = []
    for path in sorted(root_path.rglob("*")):
        if not path.is_file():
            continue
        if "__pycache__" in path.parts or "outputs" not in path.parts:
            continue
        rows.append(
            {
                "path": str(path.relative_to(root_path)),
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )
    return pd.DataFrame(rows)


def run_independent_project(
    root: str | Path = ".",
    *,
    seed: int = 2029,
    profile: str = "ci",
) -> tuple[VocationalTrainingOutputs, pd.DataFrame]:
    root_path = Path(root).resolve()
    output_path = ensure_dir(root_path / "outputs")
    outputs = run_vocational_training_case(
        root_path,
        seed=seed,
        profile=profile,
    )
    checks = project_acceptance_checks(
        outputs,
        seed=seed,
        profile=profile,
    )
    checks.to_csv(output_path / "acceptance_checks.csv", index=False)
    (output_path / "project_report.md").write_text(
        build_project_report(outputs, checks),
        encoding="utf-8",
    )
    (output_path / "dashboard.html").write_text(
        build_project_dashboard(outputs, checks),
        encoding="utf-8",
    )
    manifest = artifact_manifest(root_path)
    manifest.to_csv(output_path / "artifact_manifest.csv", index=False)
    return outputs, checks


def _parse_arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the independent synthetic FP and PRTR evaluation project."
        )
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Project root in which outputs are created.",
    )
    parser.add_argument(
        "--profile",
        choices=["ci", "demo", "full"],
        default="ci",
    )
    parser.add_argument("--seed", type=int, default=2029)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_arguments(argv)
    outputs, checks = run_independent_project(
        arguments.root,
        seed=arguments.seed,
        profile=arguments.profile,
    )
    failures = int((checks["status"] != "pass").sum())
    print(
        json.dumps(
            {
                "profile": arguments.profile,
                "fp_panel_rows": len(outputs.fp_quarterly_panel),
                "activity_panel_rows": len(outputs.activity_panel),
                "lagged_linkage_rows": len(outputs.lagged_green_linkage),
                "checks": len(checks),
                "failures": failures,
            },
            indent=2,
        )
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
