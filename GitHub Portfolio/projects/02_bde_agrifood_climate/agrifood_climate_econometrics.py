
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence
import argparse
import json
import math

import numpy as np
import pandas as pd

"""
Applied econometrics for synthetic agri-food, climate and payments data.

The agri-food case study mirrors the analytical workflow described in the
author's Banco de España experience: harmonising producer, wholesale, retail,
input-cost, FAO-style commodity and NOAA-style climate series; testing their
time-series properties; estimating error-correction pass-through; analysing
asymmetries; and tracing ENSO shocks with VARs and local projections.

The second, smaller section contains payments nowcasting examples used by the
ECB-facing part of the portfolio.  All inputs are synthetic and every result is
reproducible from a fixed seed.  The module therefore demonstrates methods and
engineering decisions without disclosing institutional data or unpublished
research results.
"""


def _as_2d(x) -> np.ndarray:
    arr = np.asarray(x, dtype=float)
    if arr.ndim == 1:
        arr = arr.reshape(-1, 1)
    return arr


def add_constant(x: pd.DataFrame | np.ndarray) -> np.ndarray:
    arr = _as_2d(x)
    return np.column_stack([np.ones(arr.shape[0]), arr])


def ols_fit(y, x) -> dict:
    y_arr = np.asarray(y, dtype=float).reshape(-1, 1)
    x_arr = _as_2d(x)
    mask = np.isfinite(y_arr.ravel()) & np.isfinite(x_arr).all(axis=1)
    y_arr = y_arr[mask]
    x_arr = x_arr[mask]
    beta = np.linalg.pinv(x_arr.T @ x_arr) @ x_arr.T @ y_arr
    resid = y_arr - x_arr @ beta
    n, k = x_arr.shape
    sigma2 = float(
        ((resid.T @ resid) / max(n - k, 1)).item()
    )
    vcov = sigma2 * np.linalg.pinv(x_arr.T @ x_arr)
    fitted = x_arr @ beta
    tss = float(((y_arr - y_arr.mean()) ** 2).sum())
    rss = float((resid ** 2).sum())
    return {"beta": beta.ravel(), "resid": resid.ravel(), "fitted": fitted.ravel(), "vcov": vcov, "r2": 1 - rss / tss if tss else np.nan, "nobs": int(n), "k": int(k)}


def hac_covariance(x, resid, max_lag: int = 4) -> np.ndarray:
    x_arr = _as_2d(x)
    u = np.asarray(resid, dtype=float).reshape(-1, 1)
    n = x_arr.shape[0]
    bread = np.linalg.pinv(x_arr.T @ x_arr / n)
    meat = (x_arr * u).T @ (x_arr * u) / n
    for lag in range(1, max_lag + 1):
        weight = 1 - lag / (max_lag + 1)
        gamma = (x_arr[lag:] * u[lag:]).T @ (x_arr[:-lag] * u[:-lag]) / n
        meat += weight * (gamma + gamma.T)
    return bread @ meat @ bread / n


def within_transform(df: pd.DataFrame, cols: list[str], fe_cols: list[str]) -> pd.DataFrame:
    out = df[cols].astype(float).copy()
    for fe in fe_cols:
        work = pd.concat([df[[fe]].reset_index(drop=True), out.reset_index(drop=True)], axis=1)
        means = work.groupby(fe)[cols].transform("mean")
        out = out.reset_index(drop=True) - means
        out.index = df.index
    return out

def pca_first_factor(frame: pd.DataFrame) -> pd.Series:
    x = frame.astype(float)
    z = (x - x.mean()) / x.std(ddof=0).replace(0, np.nan)
    z = z.fillna(0)
    u, s, _ = np.linalg.svd(z.to_numpy(), full_matrices=False)
    factor = u[:, 0] * s[0]
    if np.corrcoef(factor, z.iloc[:, 0])[0, 1] < 0:
        factor = -factor
    return pd.Series(factor, index=frame.index, name="payments_factor")


@dataclass
class ModelResult:
    table: pd.DataFrame
    fitted: pd.Series
    residuals: pd.Series
    diagnostics: dict


class PaymentsEconometricsLab:
    def __init__(self, country_quarter: pd.DataFrame, instrument_quarter: pd.DataFrame):
        self.country_quarter = country_quarter.copy()
        self.instrument_quarter = instrument_quarter.copy()

    def build_factor_dataset(self) -> pd.DataFrame:
        wide = self.instrument_quarter.pivot_table(index=["country_final","quarter","quarter_period"], columns="instrument", values="amount_eur_mn", aggfunc="sum").reset_index()
        for col in [c for c in wide.columns if c not in {"country_final","quarter","quarter_period"}]:
            wide[f"log_{col}"] = np.log(pd.to_numeric(wide[col], errors="coerce").where(lambda s: s > 0))
            wide[f"yoy_{col}"] = wide.groupby("country_final")[f"log_{col}"].diff(4)
        factor_cols = [c for c in wide.columns if c.startswith("yoy_")]
        wide["payments_factor"] = wide.groupby("quarter")[factor_cols].transform(lambda x: x).pipe(lambda _: np.nan)
        frames = []
        for country, part in wide.groupby("country_final"):
            usable = part[factor_cols].dropna(axis=1, how="all")
            if usable.shape[1] >= 2:
                f = pca_first_factor(usable.fillna(usable.mean()))
                temp = part.copy()
                temp.loc[f.index, "payments_factor"] = f
                frames.append(temp)
        return pd.concat(frames, ignore_index=True) if frames else wide

    def estimate_bridge_nowcast(self, target_col: str = "real_gdp_growth_qoq") -> ModelResult:
        factors = self.build_factor_dataset()
        panel = self.country_quarter.merge(factors[["country_final","quarter","payments_factor"]], on=["country_final","quarter"], how="left")
        panel = panel.sort_values(["country_final","quarter_period"])
        panel["payments_factor_l1"] = panel.groupby("country_final")["payments_factor"].shift(1)
        cols = ["payments_factor","payments_factor_l1","hicp_inflation_yoy","unemployment_rate"]
        model = panel.dropna(subset=[target_col] + cols)
        x = add_constant(model[cols])
        res = ols_fit(model[target_col], x)
        vcov_hac = hac_covariance(x, res["resid"], max_lag=4)
        se = np.sqrt(np.diag(vcov_hac))
        table = pd.DataFrame({"term": ["const"] + cols, "coef": res["beta"], "hac_se": se, "t_stat": res["beta"] / se})
        return ModelResult(table, pd.Series(res["fitted"], index=model.index), pd.Series(res["resid"], index=model.index), {"r2": res["r2"], "nobs": res["nobs"]})

    def recursive_nowcast_backtest(self, min_train: int = 32) -> pd.DataFrame:
        factors = self.build_factor_dataset()
        panel = self.country_quarter.merge(factors[["country_final","quarter","payments_factor"]], on=["country_final","quarter"], how="left")
        panel = panel.sort_values(["quarter_period","country_final"]).dropna(subset=["real_gdp_growth_qoq","payments_factor","hicp_inflation_yoy","unemployment_rate"])
        rows = []
        cols = ["payments_factor","hicp_inflation_yoy","unemployment_rate"]
        dates = sorted(panel["quarter_period"].unique())
        for i in range(min_train, len(dates)):
            train = panel.loc[panel["quarter_period"].isin(dates[:i])]
            test = panel.loc[panel["quarter_period"] == dates[i]]
            if len(train) < min_train or test.empty:
                continue
            x_train = add_constant(train[cols])
            res = ols_fit(train["real_gdp_growth_qoq"], x_train)
            x_test = add_constant(test[cols])
            pred = x_test @ res["beta"]
            for (_, r), p in zip(test.iterrows(), pred):
                rows.append({"country_final": r.country_final, "quarter": r.quarter, "actual": r.real_gdp_growth_qoq, "forecast": float(p), "error": float(r.real_gdp_growth_qoq - p), "abs_error": abs(float(r.real_gdp_growth_qoq - p))})
        return pd.DataFrame(rows)

    def local_projections(self, response: str = "total_amount_eur_mn", shock: str = "policy_rate", horizons: range = range(0, 9)) -> pd.DataFrame:
        panel = self.country_quarter.sort_values(["country_final","quarter_period"]).copy()
        panel[f"log_{response}"] = np.log(panel[response].where(panel[response] > 0))
        panel[f"dlog_{response}"] = panel.groupby("country_final")[f"log_{response}"].diff()
        panel["shock_change"] = panel.groupby("country_final")[shock].diff()
        rows = []
        controls = ["hicp_inflation_yoy","unemployment_rate","internet_penetration"]
        for h in horizons:
            temp = panel.copy()
            temp["future_response"] = temp.groupby("country_final")[f"dlog_{response}"].shift(-h)
            temp = temp.dropna(subset=["future_response","shock_change"] + controls)
            y = temp["future_response"]
            x = add_constant(temp[["shock_change"] + controls])
            res = ols_fit(y, x)
            vcov = hac_covariance(x, res["resid"], max_lag=max(1, h + 1))
            se = math.sqrt(max(vcov[1, 1], 0))
            rows.append({"horizon": h, "coef": res["beta"][1], "hac_se": se, "lower_95": res["beta"][1] - 1.96 * se, "upper_95": res["beta"][1] + 1.96 * se, "nobs": res["nobs"]})
        return pd.DataFrame(rows)

    def fixed_effects_panel(self, outcome: str = "fraud_value_rate") -> ModelResult:
        panel = self.country_quarter.sort_values(["country_final","quarter_period"]).copy()
        panel["digital_intensity"] = panel["internet_penetration"] * panel["total_transactions_thousand"]
        cols = [outcome, "digital_intensity", "unemployment_rate", "hicp_inflation_yoy"]
        temp = panel.dropna(subset=cols).copy()
        y = within_transform(temp, [outcome], ["country_final","quarter"]).iloc[:, 0]
        x = within_transform(temp, ["digital_intensity","unemployment_rate","hicp_inflation_yoy"], ["country_final","quarter"])
        res = ols_fit(y, x.to_numpy())
        se = np.sqrt(np.diag(hac_covariance(x.to_numpy(), res["resid"], 4)))
        table = pd.DataFrame({"term": x.columns, "coef": res["beta"], "hac_se": se, "t_stat": res["beta"] / se})
        return ModelResult(table, pd.Series(res["fitted"], index=temp.index), pd.Series(res["resid"], index=temp.index), {"r2_within": res["r2"], "nobs": res["nobs"]})

    def event_study_did(self, adoption_instrument: str = "instant_payments") -> pd.DataFrame:
        instr = self.instrument_quarter.loc[self.instrument_quarter["instrument"] == adoption_instrument].copy()
        instr = instr.sort_values(["country_final","quarter_period"])
        instr["adopted"] = instr["instrument_share"] > instr.groupby("country_final")["instrument_share"].transform("median")
        first = instr.loc[instr["adopted"]].groupby("country_final")["quarter_period"].min().rename("first_adoption")
        panel = self.country_quarter.merge(first, on="country_final", how="left")
        panel["event_time"] = panel["quarter_period"].astype("int64") - panel["first_adoption"].astype("int64")
        panel["treated"] = panel["first_adoption"].notna()
        rows = []
        for event_time in range(-8, 9):
            if event_time == -1:
                continue
            temp = panel.copy()
            temp["event_dummy"] = ((temp["event_time"] == event_time) & temp["treated"]).astype(float)
            temp = temp.dropna(subset=["yoy_amount_growth","event_dummy","unemployment_rate","hicp_inflation_yoy"])
            y = within_transform(temp, ["yoy_amount_growth"], ["country_final","quarter"]).iloc[:, 0]
            x = within_transform(temp, ["event_dummy","unemployment_rate","hicp_inflation_yoy"], ["country_final","quarter"])
            res = ols_fit(y, x.to_numpy())
            se = np.sqrt(np.diag(hac_covariance(x.to_numpy(), res["resid"], 4)))[0]
            rows.append({"event_time": event_time, "coef": res["beta"][0], "hac_se": se, "nobs": res["nobs"]})
        return pd.DataFrame(rows)

    def two_stage_least_squares(self, outcome: str = "fraud_value_rate", endogenous: str = "internet_penetration", instrument: str = "policy_rate") -> ModelResult:
        panel = self.country_quarter.dropna(subset=[outcome,endogenous,instrument,"unemployment_rate","hicp_inflation_yoy"]).copy()
        z_cols = [instrument,"unemployment_rate","hicp_inflation_yoy"]
        first = ols_fit(panel[endogenous], add_constant(panel[z_cols]))
        panel["endogenous_hat"] = first["fitted"]
        x_cols = ["endogenous_hat","unemployment_rate","hicp_inflation_yoy"]
        second = ols_fit(panel[outcome], add_constant(panel[x_cols]))
        se = np.sqrt(np.diag(hac_covariance(add_constant(panel[x_cols]), second["resid"], 4)))
        table = pd.DataFrame({"term": ["const"] + x_cols, "coef": second["beta"], "hac_se": se, "t_stat": second["beta"] / se})
        return ModelResult(table, pd.Series(second["fitted"], index=panel.index), pd.Series(second["resid"], index=panel.index), {"first_stage_r2": first["r2"], "second_stage_r2": second["r2"], "nobs": second["nobs"]})


def run_econometric_suite(country_quarter: pd.DataFrame, instrument_quarter: pd.DataFrame) -> dict[str, pd.DataFrame]:
    lab = PaymentsEconometricsLab(country_quarter, instrument_quarter)
    bridge = lab.estimate_bridge_nowcast()
    fe = lab.fixed_effects_panel()
    return {
        "bridge_nowcast_coefficients": bridge.table,
        "recursive_nowcast_backtest": lab.recursive_nowcast_backtest(),
        "local_projection_irfs": lab.local_projections(),
        "fixed_effects_panel": fe.table,
    }


# ---------------------------------------------------------------------------
# General estimation utilities
# ---------------------------------------------------------------------------


def normal_cdf(value: float) -> float:
    """Standard-normal CDF implemented with the error function."""

    return 0.5 * (1.0 + math.erf(value / math.sqrt(2.0)))


def two_sided_normal_pvalue(t_statistic: float) -> float:
    """Large-sample two-sided p-value without a SciPy dependency."""

    if not np.isfinite(t_statistic):
        return np.nan
    return 2.0 * (1.0 - normal_cdf(abs(float(t_statistic))))


def regression_table(
    terms: Sequence[str],
    coefficients: np.ndarray,
    covariance: np.ndarray,
) -> pd.DataFrame:
    """Create a stable coefficient table used by all estimators."""

    coefficients = np.asarray(coefficients, dtype=float)
    variance = np.clip(np.diag(covariance), 0, None)
    standard_errors = np.sqrt(variance)
    t_statistics = np.divide(
        coefficients,
        standard_errors,
        out=np.full_like(coefficients, np.nan),
        where=standard_errors > 0,
    )
    p_values = [
        two_sided_normal_pvalue(statistic) for statistic in t_statistics
    ]
    return pd.DataFrame(
        {
            "term": list(terms),
            "coefficient": coefficients,
            "standard_error": standard_errors,
            "t_statistic": t_statistics,
            "p_value": p_values,
            "lower_95": coefficients - 1.96 * standard_errors,
            "upper_95": coefficients + 1.96 * standard_errors,
        }
    )


def information_criteria(
    residuals: np.ndarray,
    parameters: int,
) -> dict[str, float]:
    """Gaussian AIC, BIC and HQIC from model residuals."""

    values = np.asarray(residuals, dtype=float)
    values = values[np.isfinite(values)]
    observations = len(values)
    if not observations:
        return {"aic": np.nan, "bic": np.nan, "hqic": np.nan}
    variance = max(float(np.mean(np.square(values))), np.finfo(float).eps)
    log_likelihood_component = observations * math.log(variance)
    return {
        "aic": log_likelihood_component + 2 * parameters,
        "bic": log_likelihood_component
        + parameters * math.log(observations),
        "hqic": log_likelihood_component
        + 2 * parameters * math.log(math.log(max(observations, 3))),
    }


def durbin_watson(residuals: Sequence[float]) -> float:
    """Durbin-Watson statistic for an ordered residual series."""

    values = np.asarray(residuals, dtype=float)
    values = values[np.isfinite(values)]
    denominator = float(np.sum(np.square(values)))
    if denominator == 0:
        return np.nan
    return float(np.sum(np.square(np.diff(values))) / denominator)


def condition_number(design: np.ndarray) -> float:
    """Condition number after column scaling, excluding zero-variance columns."""

    matrix = _as_2d(design).astype(float)
    scale = np.std(matrix, axis=0, ddof=0)
    keep = scale > 1e-12
    if not keep.any():
        return np.nan
    scaled = matrix[:, keep] / scale[keep]
    return float(np.linalg.cond(scaled))


def newey_west_covariance(
    design: np.ndarray,
    residuals: np.ndarray,
    lags: int,
) -> np.ndarray:
    """Alias with explicit name for the HAC implementation used here."""

    return hac_covariance(design, residuals, max_lag=lags)


def cluster_covariance(
    design: np.ndarray,
    residuals: np.ndarray,
    groups: Sequence[Any],
) -> np.ndarray:
    """One-way cluster-robust sandwich covariance with small-sample correction."""

    x = _as_2d(design)
    u = np.asarray(residuals, dtype=float).ravel()
    group_values = np.asarray(groups)
    if not (len(x) == len(u) == len(group_values)):
        raise ValueError("Design, residuals and groups must have equal length")
    bread = np.linalg.pinv(x.T @ x)
    meat = np.zeros((x.shape[1], x.shape[1]), dtype=float)
    unique_groups = pd.unique(group_values)
    for group in unique_groups:
        selector = group_values == group
        score = x[selector].T @ u[selector]
        meat += np.outer(score, score)
    observations, parameters = x.shape
    clusters = len(unique_groups)
    correction = 1.0
    if clusters > 1 and observations > parameters:
        correction = (
            clusters
            / (clusters - 1)
            * (observations - 1)
            / (observations - parameters)
        )
    return correction * bread @ meat @ bread


def block_bootstrap_indices(
    observations: int,
    block_length: int,
    rng: np.random.Generator,
) -> np.ndarray:
    """Generate a moving-block bootstrap sample for one ordered time series."""

    if observations <= 0:
        return np.array([], dtype=int)
    block_length = max(1, min(block_length, observations))
    starts = np.arange(0, observations - block_length + 1)
    blocks: list[np.ndarray] = []
    while sum(len(block) for block in blocks) < observations:
        start = int(rng.choice(starts))
        blocks.append(np.arange(start, start + block_length))
    return np.concatenate(blocks)[:observations]


def lagged_columns(
    frame: pd.DataFrame,
    columns: Sequence[str],
    lags: Iterable[int],
    *,
    group: str | None = None,
    prefix: str = "L",
) -> pd.DataFrame:
    """Append named lags without mutating the caller's DataFrame."""

    output = frame.copy()
    for column in columns:
        for lag in lags:
            name = f"{prefix}{lag}_{column}"
            if group is None:
                output[name] = output[column].shift(lag)
            else:
                output[name] = output.groupby(group)[column].shift(lag)
    return output


def lead_column(
    frame: pd.DataFrame,
    column: str,
    horizon: int,
    *,
    group: str | None = None,
) -> pd.Series:
    """Return a horizon-specific lead, optionally within a panel unit."""

    if group is None:
        return frame[column].shift(-horizon)
    return frame.groupby(group)[column].shift(-horizon)


def dummy_design(
    frame: pd.DataFrame,
    continuous: Sequence[str],
    fixed_effects: Sequence[str],
    *,
    add_intercept: bool = True,
) -> tuple[np.ndarray, list[str]]:
    """Create a full design with reference-category fixed effects."""

    pieces: list[pd.DataFrame] = []
    terms: list[str] = []
    if add_intercept:
        pieces.append(
            pd.DataFrame({"const": np.ones(len(frame))}, index=frame.index)
        )
        terms.append("const")
    if continuous:
        numeric = frame[list(continuous)].astype(float)
        pieces.append(numeric)
        terms.extend(list(continuous))
    for fixed_effect in fixed_effects:
        dummies = pd.get_dummies(
            frame[fixed_effect].astype(str),
            prefix=fixed_effect,
            drop_first=True,
            dtype=float,
        )
        pieces.append(dummies)
        terms.extend(dummies.columns.tolist())
    if not pieces:
        raise ValueError("At least one design component is required")
    matrix = pd.concat(pieces, axis=1).to_numpy(dtype=float)
    return matrix, terms


def fit_fixed_effects(
    frame: pd.DataFrame,
    *,
    outcome: str,
    regressors: Sequence[str],
    fixed_effects: Sequence[str],
    cluster: str | None = None,
) -> ModelResult:
    """LSDV fixed-effects estimator with optional cluster-robust inference."""

    needed = [outcome, *regressors, *fixed_effects]
    if cluster:
        needed.append(cluster)
    model = frame.dropna(subset=list(dict.fromkeys(needed))).copy()
    design, terms = dummy_design(model, regressors, fixed_effects)
    fitted = ols_fit(model[outcome], design)
    covariance = (
        cluster_covariance(
            design,
            fitted["resid"],
            model[cluster].to_numpy(),
        )
        if cluster
        else fitted["vcov"]
    )
    table = regression_table(terms, fitted["beta"], covariance)
    diagnostics = {
        "nobs": fitted["nobs"],
        "r_squared": fitted["r2"],
        "fixed_effects": list(fixed_effects),
        "cluster": cluster,
        "durbin_watson": durbin_watson(fitted["resid"]),
        "condition_number": condition_number(design),
    }
    return ModelResult(
        table=table,
        fitted=pd.Series(fitted["fitted"], index=model.index),
        residuals=pd.Series(fitted["resid"], index=model.index),
        diagnostics=diagnostics,
    )


# ---------------------------------------------------------------------------
# Synthetic data: agri-food value chain and climate shocks
# ---------------------------------------------------------------------------


AGRIFOOD_PRODUCTS = [
    "cereals",
    "dairy",
    "meat",
    "fruit",
    "vegetables",
    "oils",
]

VALUE_CHAIN_STAGES = [
    "producer",
    "processor",
    "retail",
]

AGRIFOOD_COUNTRIES = [
    "ES",
    "FR",
    "DE",
    "IT",
    "NL",
    "PT",
    "BE",
    "AT",
]


@dataclass
class AgrifoodSourceBundle:
    price_indices: pd.DataFrame
    input_costs: pd.DataFrame
    commodity_prices: pd.DataFrame
    climate_indices: pd.DataFrame
    food_output: pd.DataFrame
    source_metadata: pd.DataFrame


@dataclass
class AgrifoodDataFactory:
    """Generate linked monthly series with known economic transmission."""

    seed: int = 2028
    start: str = "2010-01"
    end: str = "2025-12"
    countries: list[str] = field(
        default_factory=lambda: AGRIFOOD_COUNTRIES.copy()
    )
    products: list[str] = field(
        default_factory=lambda: AGRIFOOD_PRODUCTS.copy()
    )

    def __post_init__(self) -> None:
        self.rng = np.random.default_rng(self.seed)
        self.months = pd.period_range(self.start, self.end, freq="M")

    def climate_indices(self) -> pd.DataFrame:
        enso = 0.0
        drought = 0.0
        rows: list[dict[str, Any]] = []
        for month_number, period in enumerate(self.months):
            enso = (
                0.82 * enso
                + 0.22 * math.sin(month_number / 7.0)
                + self.rng.normal(0, 0.28)
            )
            global_temperature = (
                0.45
                + 0.0028 * month_number
                + self.rng.normal(0, 0.07)
            )
            for country_number, country in enumerate(self.countries):
                drought = (
                    0.70 * drought
                    + 0.18 * max(enso, 0)
                    + self.rng.normal(0, 0.32)
                )
                precipitation = (
                    100
                    - 6.0 * drought
                    + 5.0 * math.sin(month_number / 6 + country_number)
                    + self.rng.normal(0, 6)
                )
                rows.append(
                    {
                        "country": country,
                        "month": str(period),
                        "month_period": period,
                        "enso_index": enso,
                        "enso_positive": max(enso, 0),
                        "enso_negative": min(enso, 0),
                        "drought_index": drought,
                        "precipitation_index": precipitation,
                        "temperature_anomaly": global_temperature
                        + self.rng.normal(0, 0.10),
                        "source": "synthetic_NOAA_style",
                    }
                )
        return pd.DataFrame(rows)

    def global_commodity_prices(
        self,
        climate: pd.DataFrame,
    ) -> pd.DataFrame:
        global_climate = (
            climate.groupby(["month", "month_period"], as_index=False)
            .agg(
                enso_index=("enso_index", "mean"),
                drought_index=("drought_index", "mean"),
            )
            .sort_values("month_period")
        )
        rows: list[dict[str, Any]] = []
        product_state = {
            product: math.log(100 + 8 * index)
            for index, product in enumerate(self.products)
        }
        sensitivity = {
            "cereals": 0.035,
            "dairy": 0.012,
            "meat": 0.018,
            "fruit": 0.028,
            "vegetables": 0.024,
            "oils": 0.042,
        }
        for climate_row in global_climate.itertuples(index=False):
            for product in self.products:
                shock = (
                    sensitivity[product] * climate_row.enso_index
                    + 0.018 * climate_row.drought_index
                    + self.rng.normal(0, 0.025)
                )
                product_state[product] = (
                    0.985 * product_state[product]
                    + 0.015 * math.log(100)
                    + 0.002
                    + shock
                )
                rows.append(
                    {
                        "product": product,
                        "month": climate_row.month,
                        "month_period": climate_row.month_period,
                        "commodity_price_index": math.exp(
                            product_state[product]
                        ),
                        "enso_index": climate_row.enso_index,
                        "global_drought_index": climate_row.drought_index,
                        "source": "synthetic_FAO_style",
                    }
                )
        return pd.DataFrame(rows)

    def input_cost_panel(
        self,
        climate: pd.DataFrame,
    ) -> pd.DataFrame:
        rows: list[dict[str, Any]] = []
        energy_state = math.log(100.0)
        fertiliser_state = math.log(100.0)
        wage_state = math.log(100.0)
        for month_number, period in enumerate(self.months):
            energy_state += (
                0.0015
                + 0.025 * math.sin(month_number / 13)
                + self.rng.normal(0, 0.025)
            )
            fertiliser_state += (
                0.001
                + 0.20 * (energy_state - math.log(100)) / (month_number + 12)
                + self.rng.normal(0, 0.022)
            )
            wage_state += 0.0018 + self.rng.normal(0, 0.003)
            for country_number, country in enumerate(self.countries):
                electricity_wedge = 1 + 0.02 * math.sin(
                    country_number + month_number / 8
                )
                rows.append(
                    {
                        "country": country,
                        "month": str(period),
                        "month_period": period,
                        "energy_cost_index": math.exp(energy_state)
                        * electricity_wedge,
                        "fertiliser_cost_index": math.exp(fertiliser_state)
                        * self.rng.lognormal(0, 0.015),
                        "agricultural_wage_index": math.exp(wage_state)
                        * self.rng.lognormal(0, 0.008),
                        "transport_cost_index": math.exp(
                            0.72 * energy_state
                            + 0.28 * math.log(100)
                        )
                        * self.rng.lognormal(0, 0.014),
                        "source": "synthetic_administrative_costs",
                    }
                )
        return pd.DataFrame(rows)

    def price_panel(
        self,
        commodity: pd.DataFrame,
        costs: pd.DataFrame,
    ) -> pd.DataFrame:
        commodity_index = commodity.set_index(
            ["product", "month_period"]
        )["commodity_price_index"]
        cost_index = costs.set_index(
            ["country", "month_period"]
        )
        rows: list[dict[str, Any]] = []
        producer_state: dict[tuple[str, str], float] = {}
        processor_state: dict[tuple[str, str], float] = {}
        retail_state: dict[tuple[str, str], float] = {}
        for country_number, country in enumerate(self.countries):
            for product_number, product in enumerate(self.products):
                baseline = math.log(100 + country_number + product_number)
                key = (country, product)
                producer_state[key] = baseline
                processor_state[key] = baseline
                retail_state[key] = baseline
                for month_number, period in enumerate(self.months):
                    commodity_log = math.log(
                        float(commodity_index.loc[(product, period)])
                    )
                    country_cost = cost_index.loc[(country, period)]
                    energy_log = math.log(country_cost.energy_cost_index)
                    wage_log = math.log(country_cost.agricultural_wage_index)
                    seasonal = 0.012 * math.sin(
                        2 * math.pi * period.month / 12
                        + product_number
                    )
                    producer_equilibrium = (
                        0.60 * commodity_log
                        + 0.22 * energy_log
                        + 0.18 * wage_log
                    )
                    producer_change = (
                        0.24
                        * (
                            producer_equilibrium
                            - producer_state[key]
                        )
                        + seasonal
                        + self.rng.normal(0, 0.010)
                    )
                    producer_state[key] += producer_change
                    processor_equilibrium = (
                        0.72 * producer_state[key]
                        + 0.18 * energy_log
                        + 0.10 * wage_log
                    )
                    processor_change = (
                        0.15
                        * (
                            processor_equilibrium
                            - processor_state[key]
                        )
                        + 0.20 * max(producer_change, 0)
                        + 0.10 * min(producer_change, 0)
                        + self.rng.normal(0, 0.008)
                    )
                    processor_state[key] += processor_change
                    retail_equilibrium = (
                        0.78 * processor_state[key]
                        + 0.12 * energy_log
                        + 0.10 * wage_log
                    )
                    retail_change = (
                        0.09
                        * (retail_equilibrium - retail_state[key])
                        + 0.18 * max(processor_change, 0)
                        + 0.08 * min(processor_change, 0)
                        + self.rng.normal(0, 0.006)
                    )
                    retail_state[key] += retail_change
                    values = {
                        "producer": math.exp(producer_state[key]),
                        "processor": math.exp(processor_state[key]),
                        "retail": math.exp(retail_state[key]),
                    }
                    for stage, value in values.items():
                        rows.append(
                            {
                                "country": country,
                                "product": product,
                                "stage": stage,
                                "month": str(period),
                                "month_period": period,
                                "price_index": value,
                                "source": {
                                    "producer": "synthetic_PPI",
                                    "processor": "synthetic_industry_survey",
                                    "retail": "synthetic_HICP",
                                }[stage],
                            }
                        )
        return pd.DataFrame(rows)

    def food_output_panel(
        self,
        climate: pd.DataFrame,
    ) -> pd.DataFrame:
        rows: list[dict[str, Any]] = []
        climate_index = climate.set_index(["country", "month_period"])
        for country_number, country in enumerate(self.countries):
            for product_number, product in enumerate(self.products):
                log_output = math.log(
                    95 + 4 * country_number + 2 * product_number
                )
                enso_sensitivity = {
                    "cereals": -0.022,
                    "dairy": -0.006,
                    "meat": -0.008,
                    "fruit": -0.025,
                    "vegetables": -0.020,
                    "oils": -0.018,
                }[product]
                for month_number, period in enumerate(self.months):
                    climate_row = climate_index.loc[(country, period)]
                    seasonal = 0.035 * math.sin(
                        2 * math.pi * period.month / 12 + product_number
                    )
                    growth = (
                        0.001
                        + enso_sensitivity * max(climate_row.enso_index, 0)
                        - 0.012 * max(climate_row.drought_index, 0)
                        + seasonal
                        + self.rng.normal(0, 0.018)
                    )
                    log_output = 0.995 * log_output + 0.005 * math.log(100)
                    log_output += growth
                    rows.append(
                        {
                            "country": country,
                            "product": product,
                            "month": str(period),
                            "month_period": period,
                            "food_output_index": math.exp(log_output),
                            "cultivated_area_index": float(
                                100
                                + 0.03 * month_number
                                + self.rng.normal(0, 1.2)
                            ),
                            "source": "synthetic_FAO_output",
                        }
                    )
        return pd.DataFrame(rows)

    def metadata(self) -> pd.DataFrame:
        return pd.DataFrame(
            [
                {
                    "dataset": "price_indices",
                    "frequency": "monthly",
                    "grain": "country-product-stage-month",
                    "source_analogue": "producer prices, surveys and HICP",
                    "confidentiality": "synthetic",
                },
                {
                    "dataset": "input_costs",
                    "frequency": "monthly",
                    "grain": "country-month",
                    "source_analogue": "administrative input-cost series",
                    "confidentiality": "synthetic",
                },
                {
                    "dataset": "commodity_prices",
                    "frequency": "monthly",
                    "grain": "product-month",
                    "source_analogue": "FAO commodity prices",
                    "confidentiality": "synthetic",
                },
                {
                    "dataset": "climate_indices",
                    "frequency": "monthly",
                    "grain": "country-month",
                    "source_analogue": "NOAA ENSO and climate indicators",
                    "confidentiality": "synthetic",
                },
                {
                    "dataset": "food_output",
                    "frequency": "monthly",
                    "grain": "country-product-month",
                    "source_analogue": "FAO food output",
                    "confidentiality": "synthetic",
                },
            ]
        )

    def build_bundle(self) -> AgrifoodSourceBundle:
        climate = self.climate_indices()
        commodity = self.global_commodity_prices(climate)
        costs = self.input_cost_panel(climate)
        prices = self.price_panel(commodity, costs)
        output = self.food_output_panel(climate)
        return AgrifoodSourceBundle(
            price_indices=prices,
            input_costs=costs,
            commodity_prices=commodity,
            climate_indices=climate,
            food_output=output,
            source_metadata=self.metadata(),
        )


# ---------------------------------------------------------------------------
# Harmonisation and research-ready panels
# ---------------------------------------------------------------------------


class AgrifoodDataBuilder:
    """Reconcile source frequency, keys, units and publication concepts."""

    def __init__(self, bundle: AgrifoodSourceBundle):
        self.bundle = bundle

    def validate_source_keys(self) -> pd.DataFrame:
        specifications = {
            "price_indices": (
                self.bundle.price_indices,
                ["country", "product", "stage", "month"],
            ),
            "input_costs": (
                self.bundle.input_costs,
                ["country", "month"],
            ),
            "commodity_prices": (
                self.bundle.commodity_prices,
                ["product", "month"],
            ),
            "climate_indices": (
                self.bundle.climate_indices,
                ["country", "month"],
            ),
            "food_output": (
                self.bundle.food_output,
                ["country", "product", "month"],
            ),
        }
        rows: list[dict[str, Any]] = []
        for dataset, (frame, key) in specifications.items():
            rows.append(
                {
                    "dataset": dataset,
                    "rows": len(frame),
                    "duplicate_keys": int(frame.duplicated(key).sum()),
                    "missing_key_rows": int(frame[key].isna().any(axis=1).sum()),
                    "minimum_month": str(frame["month"].min()),
                    "maximum_month": str(frame["month"].max()),
                    "status": (
                        "pass"
                        if not frame.duplicated(key).any()
                        and not frame[key].isna().any(axis=1).any()
                        else "fail"
                    ),
                }
            )
        return pd.DataFrame(rows)

    def wide_price_panel(self) -> pd.DataFrame:
        prices = self.bundle.price_indices.pivot_table(
            index=["country", "product", "month", "month_period"],
            columns="stage",
            values="price_index",
            aggfunc="last",
        ).reset_index()
        prices.columns.name = None
        return prices

    def merged_monthly_panel(self) -> pd.DataFrame:
        panel = self.wide_price_panel()
        panel = panel.merge(
            self.bundle.input_costs.drop(columns=["source"]),
            on=["country", "month", "month_period"],
            how="left",
            validate="many_to_one",
        )
        panel = panel.merge(
            self.bundle.commodity_prices.drop(columns=["source"]),
            on=["product", "month", "month_period"],
            how="left",
            validate="many_to_one",
            suffixes=("", "_commodity"),
        )
        panel = panel.merge(
            self.bundle.climate_indices.drop(columns=["source"]),
            on=["country", "month", "month_period"],
            how="left",
            validate="many_to_one",
            suffixes=("", "_climate"),
        )
        panel = panel.merge(
            self.bundle.food_output.drop(columns=["source"]),
            on=["country", "product", "month", "month_period"],
            how="left",
            validate="one_to_one",
        )
        return self.add_transformations(panel)

    def add_transformations(self, panel: pd.DataFrame) -> pd.DataFrame:
        output = panel.sort_values(
            ["country", "product", "month_period"]
        ).copy()
        level_columns = [
            "producer",
            "processor",
            "retail",
            "commodity_price_index",
            "energy_cost_index",
            "fertiliser_cost_index",
            "agricultural_wage_index",
            "transport_cost_index",
            "food_output_index",
        ]
        group = ["country", "product"]
        country_group = ["country"]
        for column in level_columns:
            output[f"log_{column}"] = np.log(
                pd.to_numeric(output[column], errors="coerce").where(
                    lambda values: values > 0
                )
            )
            difference_group = (
                country_group
                if column
                in {
                    "energy_cost_index",
                    "fertiliser_cost_index",
                    "agricultural_wage_index",
                    "transport_cost_index",
                }
                else group
            )
            output[f"dlog_{column}"] = output.groupby(difference_group)[
                f"log_{column}"
            ].diff()
            output[f"yoy_{column}"] = output.groupby(difference_group)[
                f"log_{column}"
            ].diff(12)
        output["producer_increase"] = output[
            "dlog_producer"
        ].clip(lower=0)
        output["producer_decrease"] = output[
            "dlog_producer"
        ].clip(upper=0)
        output["processor_increase"] = output[
            "dlog_processor"
        ].clip(lower=0)
        output["processor_decrease"] = output[
            "dlog_processor"
        ].clip(upper=0)
        output["producer_retail_spread"] = (
            output["log_retail"] - output["log_producer"]
        )
        output["processor_retail_spread"] = (
            output["log_retail"] - output["log_processor"]
        )
        output["panel_id"] = (
            output["country"].astype(str)
            + "_"
            + output["product"].astype(str)
        )
        output["calendar_year"] = output["month_period"].map(
            lambda period: period.year
        )
        output["calendar_month"] = output["month_period"].map(
            lambda period: period.month
        )
        return output


# ---------------------------------------------------------------------------
# Time-series estimators
# ---------------------------------------------------------------------------


def augmented_dickey_fuller(
    series: pd.Series,
    lags: int = 12,
    *,
    trend: bool = True,
) -> dict[str, float]:
    """ADF auxiliary regression; p-values are intentionally not approximated."""

    values = pd.to_numeric(series, errors="coerce")
    frame = pd.DataFrame({"level": values})
    frame["difference"] = frame["level"].diff()
    frame["lagged_level"] = frame["level"].shift(1)
    for lag in range(1, lags + 1):
        frame[f"lag_difference_{lag}"] = frame["difference"].shift(lag)
    frame["trend"] = np.arange(len(frame), dtype=float)
    regressors = ["lagged_level"]
    regressors.extend(
        f"lag_difference_{lag}" for lag in range(1, lags + 1)
    )
    if trend:
        regressors.append("trend")
    model = frame.dropna(subset=["difference", *regressors])
    design = add_constant(model[regressors])
    result = ols_fit(model["difference"], design)
    standard_error = math.sqrt(max(result["vcov"][1, 1], 0))
    statistic = (
        result["beta"][1] / standard_error if standard_error > 0 else np.nan
    )
    return {
        "adf_statistic": float(statistic),
        "lagged_level_coefficient": float(result["beta"][1]),
        "standard_error": float(standard_error),
        "lags": int(lags),
        "observations": int(result["nobs"]),
        "r_squared": float(result["r2"]),
    }


def engle_granger_cointegration(
    dependent: pd.Series,
    independent: pd.DataFrame,
    *,
    adf_lags: int = 6,
) -> tuple[pd.Series, pd.DataFrame, dict[str, float]]:
    """Estimate a long-run relation and test persistence of its residual."""

    frame = pd.concat(
        [
            dependent.rename("dependent"),
            independent.copy(),
        ],
        axis=1,
    ).dropna()
    design = add_constant(frame[independent.columns])
    result = ols_fit(frame["dependent"], design)
    covariance = newey_west_covariance(
        design,
        result["resid"],
        lags=adf_lags,
    )
    table = regression_table(
        ["const", *independent.columns],
        result["beta"],
        covariance,
    )
    residual = pd.Series(
        result["resid"],
        index=frame.index,
        name="equilibrium_error",
    )
    adf = augmented_dickey_fuller(
        residual,
        lags=adf_lags,
        trend=False,
    )
    diagnostics = {
        "long_run_r_squared": float(result["r2"]),
        "observations": int(result["nobs"]),
        **{f"residual_{key}": value for key, value in adf.items()},
    }
    return residual, table, diagnostics


def estimate_error_correction_model(
    frame: pd.DataFrame,
    *,
    retail: str,
    upstream: str,
    controls: Sequence[str],
    short_run_lags: int = 3,
    hac_lags: int = 6,
) -> ModelResult:
    """Single-equation ECM with an estimated long-run equilibrium error."""

    work = frame.copy()
    residual, long_run, cointegration = engle_granger_cointegration(
        work[retail],
        work[[upstream, *controls]],
        adf_lags=hac_lags,
    )
    work.loc[residual.index, "equilibrium_error"] = residual
    work["lagged_equilibrium_error"] = work[
        "equilibrium_error"
    ].shift(1)
    work["dependent_change"] = work[retail].diff()
    change_columns: list[str] = []
    for column in [upstream, *controls]:
        change = f"change_{column}"
        work[change] = work[column].diff()
        for lag in range(short_run_lags + 1):
            lag_name = f"L{lag}_{change}"
            work[lag_name] = work[change].shift(lag)
            change_columns.append(lag_name)
    regressors = ["lagged_equilibrium_error", *change_columns]
    model = work.dropna(subset=["dependent_change", *regressors])
    design = add_constant(model[regressors])
    result = ols_fit(model["dependent_change"], design)
    covariance = newey_west_covariance(
        design,
        result["resid"],
        lags=hac_lags,
    )
    table = regression_table(
        ["const", *regressors],
        result["beta"],
        covariance,
    )
    table["component"] = np.where(
        table["term"] == "lagged_equilibrium_error",
        "speed_of_adjustment",
        np.where(
            table["term"].str.contains("change"),
            "short_run_pass_through",
            "intercept",
        ),
    )
    diagnostics = {
        "nobs": result["nobs"],
        "r_squared": result["r2"],
        "durbin_watson": durbin_watson(result["resid"]),
        "condition_number": condition_number(design),
        "long_run_table": long_run.to_dict("records"),
        "cointegration": cointegration,
    }
    return ModelResult(
        table=table,
        fitted=pd.Series(result["fitted"], index=model.index),
        residuals=pd.Series(result["resid"], index=model.index),
        diagnostics=diagnostics,
    )


def estimate_asymmetric_ecm(
    frame: pd.DataFrame,
    *,
    retail_log: str = "log_retail",
    upstream_log: str = "log_producer",
    controls: Sequence[str] = ("log_energy_cost_index",),
    lags: int = 3,
) -> ModelResult:
    """ECM allowing upstream price increases and decreases to differ."""

    work = frame.copy()
    residual, long_run, cointegration = engle_granger_cointegration(
        work[retail_log],
        work[[upstream_log, *controls]],
        adf_lags=max(4, lags),
    )
    work.loc[residual.index, "equilibrium_error"] = residual
    work["lagged_equilibrium_error"] = work[
        "equilibrium_error"
    ].shift(1)
    work["dependent_change"] = work[retail_log].diff()
    upstream_change = work[upstream_log].diff()
    work["upstream_positive"] = upstream_change.clip(lower=0)
    work["upstream_negative"] = upstream_change.clip(upper=0)
    regressors = ["lagged_equilibrium_error"]
    for variable in ("upstream_positive", "upstream_negative"):
        for lag in range(lags + 1):
            name = f"L{lag}_{variable}"
            work[name] = work[variable].shift(lag)
            regressors.append(name)
    for control in controls:
        change = work[control].diff()
        for lag in range(lags + 1):
            name = f"L{lag}_change_{control}"
            work[name] = change.shift(lag)
            regressors.append(name)
    model = work.dropna(subset=["dependent_change", *regressors])
    design = add_constant(model[regressors])
    result = ols_fit(model["dependent_change"], design)
    covariance = newey_west_covariance(
        design,
        result["resid"],
        lags=max(4, lags),
    )
    table = regression_table(
        ["const", *regressors],
        result["beta"],
        covariance,
    )
    positive_rows = table["term"].str.contains("upstream_positive")
    negative_rows = table["term"].str.contains("upstream_negative")
    cumulative_positive = float(
        table.loc[positive_rows, "coefficient"].sum()
    )
    cumulative_negative = float(
        table.loc[negative_rows, "coefficient"].sum()
    )
    table["cumulative_positive_pass_through"] = cumulative_positive
    table["cumulative_negative_pass_through"] = cumulative_negative
    table["asymmetry_gap"] = (
        cumulative_positive - cumulative_negative
    )
    diagnostics = {
        "nobs": result["nobs"],
        "r_squared": result["r2"],
        "long_run_table": long_run.to_dict("records"),
        "cointegration": cointegration,
    }
    return ModelResult(
        table=table,
        fitted=pd.Series(result["fitted"], index=model.index),
        residuals=pd.Series(result["resid"], index=model.index),
        diagnostics=diagnostics,
    )


def select_distributed_lag(
    frame: pd.DataFrame,
    *,
    dependent: str,
    shock: str,
    controls: Sequence[str],
    maximum_lag: int = 12,
) -> pd.DataFrame:
    """Compare lag lengths using common-sample AIC, BIC and HQIC."""

    work = frame.copy()
    for variable in [dependent, shock, *controls]:
        for lag in range(maximum_lag + 1):
            work[f"L{lag}_{variable}"] = work[variable].shift(lag)
    rows: list[dict[str, Any]] = []
    common_columns = [dependent]
    for variable in [shock, *controls]:
        common_columns.extend(
            f"L{lag}_{variable}" for lag in range(maximum_lag + 1)
        )
    common = work.dropna(subset=common_columns)
    for lag_length in range(maximum_lag + 1):
        regressors: list[str] = []
        for variable in [shock, *controls]:
            regressors.extend(
                f"L{lag}_{variable}" for lag in range(lag_length + 1)
            )
        design = add_constant(common[regressors])
        result = ols_fit(common[dependent], design)
        criteria = information_criteria(
            result["resid"],
            parameters=design.shape[1],
        )
        rows.append(
            {
                "lag_length": lag_length,
                "observations": result["nobs"],
                "parameters": design.shape[1],
                "r_squared": result["r2"],
                **criteria,
            }
        )
    output = pd.DataFrame(rows)
    output["bic_preferred"] = output["bic"] == output["bic"].min()
    output["aic_preferred"] = output["aic"] == output["aic"].min()
    return output


@dataclass
class VarResult:
    variables: list[str]
    lags: int
    coefficients: np.ndarray
    residual_covariance: np.ndarray
    companion: np.ndarray
    observations: int


def estimate_var(
    frame: pd.DataFrame,
    variables: Sequence[str],
    lags: int,
) -> VarResult:
    """Estimate a reduced-form VAR by equation-wise least squares."""

    if lags < 1:
        raise ValueError("VAR lag order must be positive")
    work = frame[list(variables)].astype(float).copy()
    for variable in variables:
        for lag in range(1, lags + 1):
            work[f"L{lag}_{variable}"] = work[variable].shift(lag)
    lag_columns = [
        f"L{lag}_{variable}"
        for lag in range(1, lags + 1)
        for variable in variables
    ]
    model = work.dropna()
    design = add_constant(model[lag_columns])
    dependent = model[list(variables)].to_numpy()
    coefficients = (
        np.linalg.pinv(design.T @ design) @ design.T @ dependent
    )
    residuals = dependent - design @ coefficients
    residual_covariance = (
        residuals.T @ residuals
        / max(len(model) - design.shape[1], 1)
    )
    variables_count = len(variables)
    companion = np.zeros(
        (variables_count * lags, variables_count * lags)
    )
    companion[:variables_count, :] = coefficients[1:, :].T
    if lags > 1:
        companion[variables_count:, :-variables_count] = np.eye(
            variables_count * (lags - 1)
        )
    return VarResult(
        variables=list(variables),
        lags=lags,
        coefficients=coefficients,
        residual_covariance=residual_covariance,
        companion=companion,
        observations=len(model),
    )


def var_impulse_responses(
    result: VarResult,
    *,
    shock: str,
    horizons: int = 24,
    scale: float = 1.0,
) -> pd.DataFrame:
    """Orthogonalised impulse responses using a Cholesky identification."""

    variables = result.variables
    shock_index = variables.index(shock)
    impact = np.linalg.cholesky(
        result.residual_covariance
        + np.eye(len(variables)) * 1e-12
    )
    state_impact = np.zeros((len(variables) * result.lags, len(variables)))
    state_impact[: len(variables), :] = impact
    transition = np.eye(result.companion.shape[0])
    rows: list[dict[str, Any]] = []
    for horizon in range(horizons + 1):
        response = (
            transition
            @ state_impact[:, shock_index]
            * scale
        )[: len(variables)]
        for variable, value in zip(variables, response):
            rows.append(
                {
                    "horizon": horizon,
                    "shock": shock,
                    "response": variable,
                    "impulse_response": float(value),
                }
            )
        transition = transition @ result.companion
    return pd.DataFrame(rows)


def local_projection_panel(
    panel: pd.DataFrame,
    *,
    outcome: str,
    shock: str,
    controls: Sequence[str],
    unit: str,
    time: str,
    horizons: Iterable[int] = range(0, 19),
) -> pd.DataFrame:
    """Panel local projections with unit/time effects and unit clustering."""

    work = panel.sort_values([unit, time]).copy()
    work["outcome_change"] = work.groupby(unit)[outcome].diff()
    work["shock_innovation"] = work.groupby(unit)[shock].diff()
    for control in controls:
        work[f"L1_{control}"] = work.groupby(unit)[control].shift(1)
    rows: list[dict[str, Any]] = []
    for horizon in horizons:
        work["future_change"] = lead_column(
            work,
            "outcome_change",
            horizon,
            group=unit,
        )
        regressors = [
            "shock_innovation",
            *[f"L1_{control}" for control in controls],
        ]
        model = work.dropna(
            subset=["future_change", *regressors, unit, time]
        ).copy()
        design, terms = dummy_design(
            model,
            regressors,
            fixed_effects=[unit, time],
        )
        result = ols_fit(model["future_change"], design)
        covariance = cluster_covariance(
            design,
            result["resid"],
            model[unit],
        )
        shock_position = terms.index("shock_innovation")
        coefficient = float(result["beta"][shock_position])
        standard_error = math.sqrt(
            max(covariance[shock_position, shock_position], 0)
        )
        rows.append(
            {
                "horizon": horizon,
                "coefficient": coefficient,
                "cluster_standard_error": standard_error,
                "lower_95": coefficient - 1.96 * standard_error,
                "upper_95": coefficient + 1.96 * standard_error,
                "observations": result["nobs"],
                "clusters": int(model[unit].nunique()),
            }
        )
    return pd.DataFrame(rows)


def rolling_pass_through(
    frame: pd.DataFrame,
    *,
    dependent: str,
    shock: str,
    controls: Sequence[str],
    window: int = 72,
) -> pd.DataFrame:
    """Estimate contemporaneous pass-through in rolling monthly windows."""

    work = frame.sort_values("month_period").copy()
    work["dependent_change"] = work[dependent].diff()
    work["shock_change"] = work[shock].diff()
    for control in controls:
        work[f"change_{control}"] = work[control].diff()
    regressors = ["shock_change", *[f"change_{c}" for c in controls]]
    model = work.dropna(subset=["dependent_change", *regressors])
    rows: list[dict[str, Any]] = []
    for endpoint in range(window, len(model) + 1):
        sample = model.iloc[endpoint - window : endpoint]
        design = add_constant(sample[regressors])
        result = ols_fit(sample["dependent_change"], design)
        covariance = newey_west_covariance(
            design,
            result["resid"],
            lags=6,
        )
        standard_error = math.sqrt(max(covariance[1, 1], 0))
        rows.append(
            {
                "window_start": str(sample["month_period"].iloc[0]),
                "window_end": str(sample["month_period"].iloc[-1]),
                "coefficient": float(result["beta"][1]),
                "hac_standard_error": standard_error,
                "lower_95": float(result["beta"][1] - 1.96 * standard_error),
                "upper_95": float(result["beta"][1] + 1.96 * standard_error),
                "observations": result["nobs"],
            }
        )
    return pd.DataFrame(rows)


def counterfactual_price_path(
    coefficients: pd.DataFrame,
    observed: pd.DataFrame,
    *,
    shock_column: str,
    dependent_column: str,
    shock_reduction: float,
) -> pd.DataFrame:
    """Mechanical scenario, explicitly distinct from a causal forecast."""

    relevant = coefficients[
        coefficients["term"].str.contains(f"change_{shock_column}")
    ].copy()
    cumulative_pass_through = float(relevant["coefficient"].sum())
    output = observed[["month_period", dependent_column, shock_column]].copy()
    output = output.sort_values("month_period")
    output["observed_shock_change"] = output[shock_column].diff()
    output["counterfactual_shock_change"] = (
        output["observed_shock_change"] * (1 - shock_reduction)
    )
    output["change_difference"] = (
        output["counterfactual_shock_change"]
        - output["observed_shock_change"]
    )
    output["counterfactual_dependent"] = (
        output[dependent_column]
        + cumulative_pass_through
        * output["change_difference"].fillna(0).cumsum()
    )
    output["scenario_gap"] = (
        output["counterfactual_dependent"] - output[dependent_column]
    )
    output["scenario_assumption"] = (
        f"{shock_reduction:.0%} smaller observed shock innovations; "
        "historical pass-through held constant"
    )
    return output


# ---------------------------------------------------------------------------
# End-to-end research case
# ---------------------------------------------------------------------------


@dataclass
class AgrifoodResearchOutputs:
    source_checks: pd.DataFrame
    monthly_panel: pd.DataFrame
    unit_root_tests: pd.DataFrame
    lag_selection: pd.DataFrame
    ecm_coefficients: pd.DataFrame
    asymmetric_ecm: pd.DataFrame
    var_irfs: pd.DataFrame
    local_projection_irfs: pd.DataFrame
    rolling_estimates: pd.DataFrame
    panel_fixed_effects: pd.DataFrame
    counterfactual: pd.DataFrame
    model_diagnostics: pd.DataFrame


class AgrifoodResearchCase:
    """Coordinate the empirical workflow and keep analytical choices explicit."""

    def __init__(self, bundle: AgrifoodSourceBundle):
        self.bundle = bundle
        self.builder = AgrifoodDataBuilder(bundle)

    def national_product_series(
        self,
        panel: pd.DataFrame,
        *,
        country: str = "ES",
        product: str = "cereals",
    ) -> pd.DataFrame:
        return (
            panel.loc[
                (panel["country"] == country)
                & (panel["product"] == product)
            ]
            .sort_values("month_period")
            .reset_index(drop=True)
        )

    def unit_root_table(self, series: pd.DataFrame) -> pd.DataFrame:
        variables = [
            "log_producer",
            "log_processor",
            "log_retail",
            "log_commodity_price_index",
            "log_energy_cost_index",
            "log_food_output_index",
        ]
        rows: list[dict[str, Any]] = []
        for variable in variables:
            level = augmented_dickey_fuller(
                series[variable],
                lags=6,
                trend=True,
            )
            difference = augmented_dickey_fuller(
                series[variable].diff(),
                lags=6,
                trend=False,
            )
            rows.append(
                {
                    "variable": variable,
                    "transformation": "level",
                    **level,
                }
            )
            rows.append(
                {
                    "variable": variable,
                    "transformation": "first_difference",
                    **difference,
                }
            )
        return pd.DataFrame(rows)

    def panel_pass_through(self, panel: pd.DataFrame) -> ModelResult:
        work = panel.copy()
        work["dlog_retail"] = work.groupby("panel_id")[
            "log_retail"
        ].diff()
        work["dlog_producer"] = work.groupby("panel_id")[
            "log_producer"
        ].diff()
        work["dlog_energy"] = work.groupby("panel_id")[
            "log_energy_cost_index"
        ].diff()
        work["lagged_spread"] = work.groupby("panel_id")[
            "producer_retail_spread"
        ].shift(1)
        return fit_fixed_effects(
            work,
            outcome="dlog_retail",
            regressors=[
                "dlog_producer",
                "dlog_energy",
                "lagged_spread",
            ],
            fixed_effects=["panel_id", "month"],
            cluster="panel_id",
        )

    def run(
        self,
        *,
        country: str = "ES",
        product: str = "cereals",
    ) -> AgrifoodResearchOutputs:
        source_checks = self.builder.validate_source_keys()
        panel = self.builder.merged_monthly_panel()
        series = self.national_product_series(
            panel,
            country=country,
            product=product,
        )
        unit_roots = self.unit_root_table(series)
        lag_selection = select_distributed_lag(
            series,
            dependent="dlog_retail",
            shock="dlog_producer",
            controls=["dlog_energy_cost_index"],
            maximum_lag=8,
        )
        preferred_lag = int(
            lag_selection.loc[
                lag_selection["bic_preferred"],
                "lag_length",
            ].iloc[0]
        )
        ecm = estimate_error_correction_model(
            series,
            retail="log_retail",
            upstream="log_producer",
            controls=[
                "log_energy_cost_index",
                "log_agricultural_wage_index",
            ],
            short_run_lags=min(preferred_lag, 4),
            hac_lags=6,
        )
        asymmetric = estimate_asymmetric_ecm(
            series,
            retail_log="log_retail",
            upstream_log="log_producer",
            controls=["log_energy_cost_index"],
            lags=min(preferred_lag, 4),
        )
        var_frame = series[
            [
                "enso_index",
                "dlog_commodity_price_index",
                "dlog_food_output_index",
                "dlog_retail",
            ]
        ].dropna()
        var = estimate_var(
            var_frame,
            variables=[
                "enso_index",
                "dlog_commodity_price_index",
                "dlog_food_output_index",
                "dlog_retail",
            ],
            lags=2,
        )
        var_irfs = var_impulse_responses(
            var,
            shock="enso_index",
            horizons=18,
        )
        local_projections = local_projection_panel(
            panel,
            outcome="log_food_output_index",
            shock="enso_index",
            controls=[
                "temperature_anomaly",
                "precipitation_index",
                "log_energy_cost_index",
            ],
            unit="panel_id",
            time="month",
            horizons=range(0, 13),
        )
        rolling = rolling_pass_through(
            series,
            dependent="log_retail",
            shock="log_producer",
            controls=["log_energy_cost_index"],
            window=72,
        )
        panel_model = self.panel_pass_through(panel)
        counterfactual = counterfactual_price_path(
            ecm.table,
            series,
            shock_column="log_energy_cost_index",
            dependent_column="log_retail",
            shock_reduction=0.20,
        )
        diagnostics = pd.DataFrame(
            [
                {
                    "model": "error_correction",
                    "country": country,
                    "product": product,
                    "observations": ecm.diagnostics["nobs"],
                    "r_squared": ecm.diagnostics["r_squared"],
                    "durbin_watson": ecm.diagnostics["durbin_watson"],
                    "condition_number": ecm.diagnostics["condition_number"],
                },
                {
                    "model": "asymmetric_error_correction",
                    "country": country,
                    "product": product,
                    "observations": asymmetric.diagnostics["nobs"],
                    "r_squared": asymmetric.diagnostics["r_squared"],
                    "durbin_watson": durbin_watson(
                        asymmetric.residuals
                    ),
                    "condition_number": np.nan,
                },
                {
                    "model": "panel_fixed_effects",
                    "country": "all",
                    "product": "all",
                    "observations": panel_model.diagnostics["nobs"],
                    "r_squared": panel_model.diagnostics["r_squared"],
                    "durbin_watson": panel_model.diagnostics[
                        "durbin_watson"
                    ],
                    "condition_number": panel_model.diagnostics[
                        "condition_number"
                    ],
                },
                {
                    "model": "reduced_form_var",
                    "country": country,
                    "product": product,
                    "observations": var.observations,
                    "r_squared": np.nan,
                    "durbin_watson": np.nan,
                    "condition_number": np.nan,
                },
            ]
        )
        return AgrifoodResearchOutputs(
            source_checks=source_checks,
            monthly_panel=panel,
            unit_root_tests=unit_roots,
            lag_selection=lag_selection,
            ecm_coefficients=ecm.table,
            asymmetric_ecm=asymmetric.table,
            var_irfs=var_irfs,
            local_projection_irfs=local_projections,
            rolling_estimates=rolling,
            panel_fixed_effects=panel_model.table,
            counterfactual=counterfactual,
            model_diagnostics=diagnostics,
        )


def save_agrifood_outputs(
    outputs: AgrifoodResearchOutputs,
    root: str | Path,
) -> dict[str, Path]:
    destination = Path(root) / "outputs"
    destination.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for name, value in asdict(outputs).items():
        if isinstance(value, pd.DataFrame):
            path = destination / f"{name}.csv"
            value.to_csv(path, index=False)
            paths[name] = path
    return paths


def run_agrifood_case(
    root: str | Path = ".",
    *,
    seed: int = 2028,
    profile: str = "ci",
) -> AgrifoodResearchOutputs:
    settings = {
        "ci": {
            "start": "2014-01",
            "end": "2023-12",
            "countries": ["ES", "FR", "DE", "IT"],
            "products": ["cereals", "dairy", "oils"],
        },
        "demo": {
            "start": "2011-01",
            "end": "2025-12",
            "countries": AGRIFOOD_COUNTRIES.copy(),
            "products": AGRIFOOD_PRODUCTS.copy(),
        },
        "full": {
            "start": "2010-01",
            "end": "2025-12",
            "countries": AGRIFOOD_COUNTRIES.copy(),
            "products": AGRIFOOD_PRODUCTS.copy(),
        },
    }
    if profile not in settings:
        raise ValueError(f"Unknown profile: {profile}")
    bundle = AgrifoodDataFactory(
        seed=seed,
        **settings[profile],
    ).build_bundle()
    outputs = AgrifoodResearchCase(bundle).run()
    save_agrifood_outputs(outputs, root)
    metadata_path = Path(root) / "outputs" / "source_metadata.csv"
    bundle.source_metadata.to_csv(metadata_path, index=False)
    return outputs


def agrifood_acceptance_checks(
    outputs: AgrifoodResearchOutputs,
) -> pd.DataFrame:
    """Checks owned and executed entirely inside this research project."""

    source_failures = int(
        (outputs.source_checks["status"] != "pass").sum()
    )
    horizons = sorted(
        outputs.local_projection_irfs["horizon"].astype(int).unique()
    )
    rows = [
        {
            "check": "source_keys_and_coverage",
            "status": source_failures == 0,
            "observed": source_failures,
            "expected": "0 failures",
        },
        {
            "check": "monthly_panel_nonempty",
            "status": len(outputs.monthly_panel) > 0,
            "observed": len(outputs.monthly_panel),
            "expected": "> 0",
        },
        {
            "check": "ecm_adjustment_term",
            "status": outputs.ecm_coefficients["term"].eq(
                "lagged_equilibrium_error"
            ).any(),
            "observed": int(
                outputs.ecm_coefficients["term"].eq(
                    "lagged_equilibrium_error"
                ).sum()
            ),
            "expected": "1",
        },
        {
            "check": "asymmetric_pass_through_terms",
            "status": (
                outputs.asymmetric_ecm["term"]
                .str.contains("upstream_positive")
                .any()
                and outputs.asymmetric_ecm["term"]
                .str.contains("upstream_negative")
                .any()
            ),
            "observed": len(outputs.asymmetric_ecm),
            "expected": "positive and negative terms",
        },
        {
            "check": "local_projection_horizons",
            "status": horizons == list(range(13)),
            "observed": str(horizons),
            "expected": "0 through 12",
        },
        {
            "check": "panel_coefficients_finite",
            "status": np.isfinite(
                outputs.panel_fixed_effects["coefficient"]
            ).all(),
            "observed": bool(
                np.isfinite(
                    outputs.panel_fixed_effects["coefficient"]
                ).all()
            ),
            "expected": "True",
        },
        {
            "check": "var_responses_nonempty",
            "status": len(outputs.var_irfs) > 0,
            "observed": len(outputs.var_irfs),
            "expected": "> 0",
        },
    ]
    checks = pd.DataFrame(rows)
    checks["status"] = np.where(checks["status"], "pass", "fail")
    return checks


def write_agrifood_project_report(
    outputs: AgrifoodResearchOutputs,
    checks: pd.DataFrame,
    root: str | Path,
) -> Path:
    destination = Path(root) / "outputs" / "project_report.md"
    diagnostics = outputs.model_diagnostics.to_string(index=False)
    check_text = checks.to_string(index=False)
    report = f"""# Agri-food Price Transmission and Climate Risk

**Author: Jose Camas Garrdiow**

This independent project uses generated producer, processor, retail, input-cost,
commodity, output and climate series. It contains no Banco de España, FAO or
NOAA microdata and its coefficients are not institutional results.

## Scale

- Harmonised country-product-month rows: {len(outputs.monthly_panel):,}
- Error-correction terms: {len(outputs.ecm_coefficients):,}
- VAR impulse-response rows: {len(outputs.var_irfs):,}
- Panel local-projection horizons: {len(outputs.local_projection_irfs):,}

## Model diagnostics

```text
{diagnostics}
```

## Acceptance checks

```text
{check_text}
```

## Interpretation

The project demonstrates time-series harmonisation, cointegration,
error-correction, asymmetric pass-through, VARs, local projections and
fixed-effects estimation. Synthetic estimates should not be interpreted as
evidence about observed countries or products.
"""
    destination.write_text(report, encoding="utf-8")
    return destination


def _parse_cli(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the synthetic agri-food econometrics case study."
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Repository root for generated outputs.",
    )
    parser.add_argument(
        "--profile",
        choices=["ci", "demo", "full"],
        default="ci",
    )
    parser.add_argument("--seed", type=int, default=2028)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_cli(argv)
    outputs = run_agrifood_case(
        arguments.root,
        seed=arguments.seed,
        profile=arguments.profile,
    )
    failing_sources = int(
        (outputs.source_checks["status"] != "pass").sum()
    )
    checks = agrifood_acceptance_checks(outputs)
    checks.to_csv(
        Path(arguments.root) / "outputs" / "acceptance_checks.csv",
        index=False,
    )
    write_agrifood_project_report(outputs, checks, arguments.root)
    failures = int((checks["status"] != "pass").sum())
    print(
        json.dumps(
            {
                "monthly_panel_rows": len(outputs.monthly_panel),
                "ecm_terms": len(outputs.ecm_coefficients),
                "local_projection_horizons": len(
                    outputs.local_projection_irfs
                ),
                "source_validation_failures": failing_sources,
                "acceptance_failures": failures,
            },
            indent=2,
        )
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
