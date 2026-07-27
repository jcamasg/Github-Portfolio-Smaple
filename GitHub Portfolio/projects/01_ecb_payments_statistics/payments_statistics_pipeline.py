
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence
import argparse
import hashlib
import io
import json
import math
import sqlite3
import urllib.parse
import urllib.request

import numpy as np
import pandas as pd

"""
Synthetic payments-statistics production system.

The module recreates, with generated data, the work of maintaining
research-ready administrative panels, reconciling submissions from several
institutions and building reproducible production controls. It is an independent
ECB-facing project and does not import code from the other portfolio projects.
It does not contain ECB or national central-bank data. Every observation is
generated locally from a documented random seed.

The design deliberately resembles a small official-statistics system:

* source adapters isolate file and API details from statistical transformations;
* data contracts make business definitions explicit and machine-testable;
* a deterministic pipeline resolves revisions and creates an audit trail;
* country and instrument aggregates support analyst review;
* a SQLite warehouse demonstrates relational loading and SQL validation;
* a shadow-production comparator supports migration acceptance testing; and
* vintage statistics quantify how flash estimates change before final release.

The code uses only Python's standard library, NumPy and pandas for the core
system.  Excel export is optional and uses openpyxl when it is available.
"""

EU_COUNTRIES = ["AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE","GR","HU","IE","IT","LV","LT","LU","MT","NL","PL","PT","RO","SK","SI","ES","SE"]
PAYMENT_INSTRUMENTS = ["card_payments","credit_transfers","direct_debits","instant_payments","e_money","cash_withdrawals","cheques","mobile_wallets","open_banking_initiations"]
PAYMENT_CHANNELS = ["pos","ecommerce","mobile_app","online_banking","branch","atm","api","batch_file"]
CUSTOMER_SEGMENTS = ["households","smes","large_corporates","public_sector","non_resident"]
MCC_SECTORS = ["food_retail","transport","accommodation","restaurants","utilities","health","education","professional_services","public_admin","digital_goods","financial_services","recreation","fuel","construction","wholesale","manufacturing","real_estate","telecommunications","other_services"]
DATA_SOURCES = ["psp_portal","legacy_csv","regulatory_xml","migration_shadow","manual_revision"]
COUNTRY_ALIASES = {"Spain":"ES","Espana":"ES","Deutschland":"DE","Germany":"DE","Holland":"NL","Netherlands":"NL","Italia":"IT","Belgium":"BE","Belgique":"BE"}


def ensure_dir(path: str | Path) -> Path:
    out = Path(path)
    out.mkdir(parents=True, exist_ok=True)
    return out


def robust_zscore(series: pd.Series) -> pd.Series:
    values = pd.to_numeric(series, errors="coerce")
    if values.notna().sum() == 0:
        return pd.Series(np.nan, index=series.index, dtype=float)
    med = values.median(skipna=True)
    mad = (values - med).abs().median(skipna=True)
    if pd.isna(mad) or mad == 0:
        return pd.Series(np.nan, index=series.index)
    return 0.6745 * (values - med) / mad


def winsorize(series: pd.Series, lower: float = 0.01, upper: float = 0.99) -> pd.Series:
    values = pd.to_numeric(series, errors="coerce")
    if values.notna().sum() == 0:
        return pd.Series(np.nan, index=series.index, dtype=float)
    return values.clip(values.quantile(lower), values.quantile(upper))


def unit_to_eur_mn(unit: str) -> float:
    unit = str(unit).strip().lower()
    if unit in {"eur", "euro", "euros"}:
        return 1 / 1_000_000
    if unit in {"eur cents", "cents"}:
        return 1 / 100 / 1_000_000
    if unit in {"thousand eur", "k eur"}:
        return 1 / 1_000
    return 1.0


def quarter_end(q: str) -> pd.Timestamp:
    return pd.Period(q, freq="Q").to_timestamp(how="end")


@dataclass
class SourceBundle:
    country_metadata: pd.DataFrame
    psp_registry: pd.DataFrame
    merchant_registry: pd.DataFrame
    quarterly_payments: pd.DataFrame
    fraud_reports: pd.DataFrame
    terminal_inventory: pd.DataFrame
    card_inventory: pd.DataFrame
    revision_vintages: pd.DataFrame
    macro_panel: pd.DataFrame
    operational_incidents: pd.DataFrame


@dataclass
class ProductionArtifacts:
    cleaned_payments: pd.DataFrame
    country_quarter: pd.DataFrame
    instrument_quarter: pd.DataFrame
    review_pack: pd.DataFrame
    data_quality_summary: pd.DataFrame
    audit_trail: pd.DataFrame
    dashboard_table: pd.DataFrame
    migration_comparison: pd.DataFrame


@dataclass
class PaymentDataFactory:
    seed: int = 2026
    start: str = "2017Q1"
    end: str = "2026Q2"
    countries: list[str] = field(default_factory=lambda: EU_COUNTRIES.copy())
    n_psp: int = 70
    n_merchants: int = 1200

    def __post_init__(self) -> None:
        self.rng = np.random.default_rng(self.seed)
        self.quarters = pd.period_range(self.start, self.end, freq="Q")

    def simulate_country_metadata(self) -> pd.DataFrame:
        rows = []
        for i, c in enumerate(self.countries):
            rows.append({
                "country": c,
                "country_reported_name": {"ES": "Spain", "DE": "Deutschland", "NL": "Holland"}.get(c, c),
                "population": int(self.rng.integers(500_000, 84_000_000)),
                "gdp_per_capita_eur": float(self.rng.uniform(25_000, 68_000)),
                "banking_density": float(self.rng.uniform(0.4, 3.0)),
                "digital_readiness_index": float(self.rng.uniform(40, 95)),
                "euro_area_member": c not in {"BG","CZ","DK","HU","PL","RO","SE"},
                "ncb_code": f"NCB_{c}",
                "reporting_language": ["en","es","de","fr","it","nl"][i % 6],
            })
        return pd.DataFrame(rows)

    def simulate_psp_registry(self, n_psp: int = 70) -> pd.DataFrame:
        rows = []
        for i in range(n_psp):
            c = str(self.rng.choice(self.countries))
            rows.append({
                "psp_id": f"PSP{i:05d}",
                "country": c,
                "legal_name": f"Synthetic Payment Institution {i:05d} {c}",
                "license_type": str(self.rng.choice(["credit_institution","payment_institution","e_money_institution","branch"], p=[0.52,0.25,0.17,0.06])),
                "ownership": str(self.rng.choice(["domestic","euro_area_cross_border","non_eu_parent"], p=[0.58,0.32,0.10])),
                "go_live_quarter": str(self.rng.choice(self.quarters[:24])),
                "reporting_system": str(self.rng.choice(DATA_SOURCES, p=[0.40,0.17,0.18,0.20,0.05])),
                "lei": f"LEI{c}{i:015d}",
                "active": bool(self.rng.random() > 0.035),
                "migration_wave": int(self.rng.integers(1, 5)),
            })
        return pd.DataFrame(rows)

    def simulate_merchant_registry(self, n_merchants: int = 1200) -> pd.DataFrame:
        rows = []
        for i in range(n_merchants):
            c = str(self.rng.choice(self.countries))
            rows.append({
                "merchant_id": f"M{i:07d}",
                "country": c,
                "mcc_sector": str(self.rng.choice(MCC_SECTORS)),
                "region_code": f"{c}-{int(self.rng.integers(1, 35)):02d}",
                "merchant_size": str(self.rng.choice(["micro","small","medium","large"], p=[0.42,0.35,0.17,0.06])),
                "online_share": float(self.rng.beta(2, 5)),
                "tourism_exposure": float(self.rng.beta(1.5, 4)),
                "risk_tier": str(self.rng.choice(["low","medium","high"], p=[0.72,0.23,0.05])),
            })
        return pd.DataFrame(rows)

    def simulate_quarterly_payments(self, psp: pd.DataFrame, meta: pd.DataFrame) -> pd.DataFrame:
        rows = []
        meta_idx = meta.set_index("country")
        for _, bank in psp.loc[psp["active"]].iterrows():
            c = bank["country"]
            pop_scale = float(meta_idx.loc[c, "population"]) / 1_000_000
            digital = float(meta_idx.loc[c, "digital_readiness_index"]) / 100
            psp_scale = float(self.rng.lognormal(0.0, 0.65))
            start = pd.Period(bank["go_live_quarter"], freq="Q")
            for q in self.quarters:
                if q < start:
                    continue
                t = q.ordinal - self.quarters[0].ordinal
                season = 1 + 0.08 * np.sin(2 * np.pi * (q.quarter - 1) / 4)
                trend = (1 + 0.011 + 0.010 * digital) ** t
                for instrument in PAYMENT_INSTRUMENTS:
                    inst_factor = {"card_payments":1.0,"credit_transfers":0.72,"direct_debits":0.42,"instant_payments":0.10+0.024*t,"e_money":0.10+0.006*t,"cash_withdrawals":max(0.15,0.62-0.012*t),"cheques":max(0.03,0.20-0.006*t),"mobile_wallets":0.06+0.016*t,"open_banking_initiations":0.01+0.010*t}[instrument]
                    for channel in PAYMENT_CHANNELS:
                        if instrument == "cash_withdrawals" and channel not in {"atm","branch"}:
                            continue
                        if instrument == "cheques" and channel in {"mobile_app","api"}:
                            continue
                        channel_factor = {"pos":0.85,"ecommerce":0.55,"mobile_app":0.32,"online_banking":0.42,"branch":0.16,"atm":0.20,"api":0.22,"batch_file":0.18}[channel]
                        value_eur_mn = 18.0 * pop_scale * psp_scale * trend * season * inst_factor * channel_factor * self.rng.lognormal(0, 0.20)
                        count_thousand = value_eur_mn * self.rng.uniform(80, 280)
                        unit = str(self.rng.choice(["EUR","EUR cents","thousand EUR","million EUR"], p=[0.77,0.03,0.12,0.08]))
                        rows.append({
                            "report_id": f"{bank.psp_id}-{q}-{instrument}-{channel}",
                            "psp_id": bank.psp_id,
                            "country": c,
                            "country_reported": c,
                            "quarter": str(q),
                            "instrument": instrument,
                            "channel": channel,
                            "customer_segment": str(self.rng.choice(CUSTOMER_SEGMENTS)),
                            "source_system": bank.reporting_system,
                            "amount_reported": value_eur_mn / unit_to_eur_mn(unit),
                            "amount_unit": unit,
                            "transaction_count_reported": count_thousand,
                            "domestic_share": float(self.rng.beta(7, 2)),
                            "remote_share": float(self.rng.beta(2, 4)),
                            "merchant_sector": str(self.rng.choice(MCC_SECTORS)),
                            "submission_timestamp": quarter_end(str(q)) + pd.Timedelta(days=int(self.rng.integers(4, 40))),
                            "is_revision": False,
                            "migration_wave": int(bank.migration_wave),
                        })
        out = pd.DataFrame(rows)
        return self.inject_reporting_errors(out)

    def inject_reporting_errors(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        dupes = out.sample(frac=0.006, random_state=self.seed + 1).copy()
        dupes["source_system"] = "manual_revision"
        dupes["amount_reported"] *= self.rng.lognormal(0, 0.025, len(dupes))
        out = pd.concat([out, dupes], ignore_index=True)
        out.loc[out.sample(frac=0.003, random_state=self.seed + 2).index, "amount_reported"] = np.nan
        neg_idx = out.sample(frac=0.002, random_state=self.seed + 3).index
        out.loc[neg_idx, "amount_reported"] = -out.loc[neg_idx, "amount_reported"].abs()
        alias_idx = out.sample(frac=0.004, random_state=self.seed + 4).index
        out.loc[alias_idx, "country_reported"] = out.loc[alias_idx, "country"].map({"ES":"Spain","DE":"Deutschland","NL":"Holland"}).fillna(out.loc[alias_idx, "country"])
        shock_idx = out.sample(frac=0.004, random_state=self.seed + 5).index
        out.loc[shock_idx, "amount_reported"] *= self.rng.choice([0.08, 4.5, 9.0], size=len(shock_idx))
        late_idx = out.sample(frac=0.006, random_state=self.seed + 6).index
        out.loc[late_idx, "submission_timestamp"] = pd.to_datetime(out.loc[late_idx, "submission_timestamp"]) + pd.to_timedelta(80, unit="D")
        return out

    def simulate_fraud_reports(self, payments: pd.DataFrame) -> pd.DataFrame:
        sample = payments.sample(frac=0.36, random_state=self.seed)
        rows = []
        for _, row in sample.iterrows():
            rate = 0.0002 + 0.0018 * (row["channel"] in {"ecommerce","mobile_app","api"})
            count = max(0.0, row["transaction_count_reported"] * self.rng.lognormal(np.log(rate), 0.45))
            amount = count * max(float(row["amount_reported"]) if pd.notna(row["amount_reported"]) else 1, 1) * unit_to_eur_mn(row["amount_unit"]) * self.rng.uniform(0.00001, 0.00008)
            rows.append({"psp_id": row["psp_id"], "country": row["country"], "quarter": row["quarter"], "instrument": row["instrument"], "channel": row["channel"], "fraud_type": str(self.rng.choice(["lost_card","card_not_present","credit_transfer_scam","account_takeover","merchant_fraud"])), "fraud_count": count, "fraud_amount_eur_mn": amount, "reimbursed_amount_eur_mn": amount * self.rng.uniform(0.15, 0.80), "sca_exempt_share": float(self.rng.beta(2, 8))})
        return pd.DataFrame(rows)

    def simulate_auxiliary_panel(self, psp: pd.DataFrame, kind: str) -> pd.DataFrame:
        rows = []
        for _, row in psp.iterrows():
            for q in self.quarters:
                base = float(self.rng.lognormal(8.0, 0.9))
                if kind == "terminal":
                    rows.append({"psp_id": row.psp_id, "country": row.country, "quarter": str(q), "pos_terminals": int(base), "contactless_enabled_share": float(np.clip(0.35 + 0.015 * (q.ordinal - self.quarters[0].ordinal) + self.rng.normal(0,0.06), 0, 1)), "atm_count": int(base * self.rng.uniform(0.03, 0.12)), "softpos_merchants": int(base * self.rng.uniform(0.01, 0.08))})
                else:
                    cards = int(self.rng.lognormal(11.5, 0.9))
                    rows.append({"psp_id": row.psp_id, "country": row.country, "quarter": str(q), "cards_issued": cards, "debit_share": float(self.rng.beta(5,2)), "credit_share": float(self.rng.beta(2,5)), "tokenised_cards_share": float(np.clip(0.05 + 0.02 * (q.ordinal - self.quarters[0].ordinal) + self.rng.normal(0,0.04), 0, 1)), "inactive_cards_share": float(self.rng.beta(2,8))})
        return pd.DataFrame(rows)

    def simulate_revision_vintages(self, payments: pd.DataFrame) -> pd.DataFrame:
        base = payments.sample(frac=0.08, random_state=self.seed + 7)
        out = []
        for vintage, noise in [("flash",0.06),("first_release",0.035),("final",0.012)]:
            temp = base.copy()
            temp["vintage"] = vintage
            temp["amount_reported_vintage"] = temp["amount_reported"] * self.rng.lognormal(0, noise, len(temp))
            temp["transaction_count_reported_vintage"] = temp["transaction_count_reported"] * self.rng.lognormal(0, noise, len(temp))
            out.append(temp[["report_id","psp_id","country","quarter","instrument","channel","vintage","amount_reported_vintage","transaction_count_reported_vintage"]])
        return pd.concat(out, ignore_index=True)

    def simulate_macro_panel(self, meta: pd.DataFrame) -> pd.DataFrame:
        rows = []
        for _, c in meta.iterrows():
            cycle = self.rng.normal(0, 0.2)
            inflation = self.rng.uniform(0.005, 0.045)
            for q in self.quarters:
                t = q.ordinal - self.quarters[0].ordinal
                cycle = 0.75 * cycle + self.rng.normal(0, 0.45)
                rows.append({"country": c.country, "quarter": str(q), "real_gdp_growth_qoq": 0.003 + 0.002 * cycle + self.rng.normal(0,0.004), "hicp_inflation_yoy": inflation + 0.002 * np.sin(t / 3) + self.rng.normal(0,0.003), "unemployment_rate": float(np.clip(0.07 - 0.01 * cycle + self.rng.normal(0,0.008), 0.025, 0.23)), "policy_rate": 0.01 + 0.004 * t / len(self.quarters) + self.rng.normal(0,0.002), "retail_sales_growth_yoy": 0.015 + 0.006 * cycle + self.rng.normal(0,0.012), "internet_penetration": float(np.clip(c.digital_readiness_index / 100 + 0.002 * t + self.rng.normal(0,0.01), 0, 1))})
        return pd.DataFrame(rows)

    def simulate_operational_incidents(self, psp: pd.DataFrame) -> pd.DataFrame:
        rows = []
        for _, row in psp.sample(frac=0.42, random_state=self.seed).iterrows():
            for q in self.rng.choice(self.quarters, size=int(self.rng.integers(1, 5)), replace=False):
                rows.append({"psp_id": row.psp_id, "country": row.country, "quarter": str(q), "incident_type": str(self.rng.choice(["outage","late_submission","schema_error","migration_mapping","cyber_event"])), "duration_hours": float(self.rng.lognormal(1.1,0.8)), "transactions_affected_thousand": float(self.rng.lognormal(5.3,1.0)), "materiality_score": float(self.rng.uniform(1,10))})
        return pd.DataFrame(rows)

    def build_bundle(self) -> SourceBundle:
        country_metadata = self.simulate_country_metadata()
        psp_registry = self.simulate_psp_registry(self.n_psp)
        merchant_registry = self.simulate_merchant_registry(self.n_merchants)
        payments = self.simulate_quarterly_payments(psp_registry, country_metadata)
        return SourceBundle(
            country_metadata=country_metadata,
            psp_registry=psp_registry,
            merchant_registry=merchant_registry,
            quarterly_payments=payments,
            fraud_reports=self.simulate_fraud_reports(payments),
            terminal_inventory=self.simulate_auxiliary_panel(psp_registry, "terminal"),
            card_inventory=self.simulate_auxiliary_panel(psp_registry, "card"),
            revision_vintages=self.simulate_revision_vintages(payments),
            macro_panel=self.simulate_macro_panel(country_metadata),
            operational_incidents=self.simulate_operational_incidents(psp_registry),
        )


class PaymentProductionEngine:
    def __init__(self) -> None:
        self.audit_records: list[dict[str, Any]] = []

    def audit(self, step: str, frame: pd.DataFrame, message: str) -> None:
        self.audit_records.append({"step": step, "rows": int(len(frame)), "columns": int(len(frame.columns)), "message": message})

    def standardise(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        out.columns = [c.strip().lower() for c in out.columns]
        for col in ["psp_id","country","country_reported","quarter","instrument","channel","customer_segment","source_system","merchant_sector","amount_unit"]:
            out[col] = out[col].astype(str).str.strip()
        out["country"] = out["country"].replace(COUNTRY_ALIASES)
        out["country_reported"] = out["country_reported"].replace(COUNTRY_ALIASES)
        out["country_final"] = out["country"].where(out["country"].isin(EU_COUNTRIES), out["country_reported"])
        out["instrument"] = out["instrument"].str.lower().str.replace(" ", "_")
        out["channel"] = out["channel"].str.lower().str.replace(" ", "_")
        out["quarter_period"] = pd.PeriodIndex(out["quarter"], freq="Q")
        out["quarter_end"] = out["quarter_period"].dt.to_timestamp(how="end")
        self.audit("standardise", out, "normalised identifiers, aliases and quarter fields")
        return out

    def normalise_units(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        for col in ["amount_reported","transaction_count_reported","domestic_share","remote_share"]:
            out[col] = pd.to_numeric(out[col], errors="coerce")
        out["unit_multiplier_to_eur_mn"] = out["amount_unit"].map(unit_to_eur_mn)
        out["amount_eur_mn_raw"] = out["amount_reported"] * out["unit_multiplier_to_eur_mn"]
        out["transaction_count_thousand_raw"] = out["transaction_count_reported"]
        out["submission_timestamp"] = pd.to_datetime(out["submission_timestamp"], errors="coerce")
        self.audit("normalise_units", out, "converted amount units to EUR millions")
        return out

    def resolve_duplicates(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        key = ["psp_id","country_final","quarter","instrument","channel"]
        out["source_priority"] = out["source_system"].map({"manual_revision":0,"regulatory_xml":1,"psp_portal":2,"migration_shadow":3,"legacy_csv":4}).fillna(9)
        out = out.sort_values(key + ["source_priority","submission_timestamp"])
        out["duplicate_sequence"] = out.groupby(key).cumcount()
        resolved = out.groupby(key, as_index=False).agg(
            report_id=("report_id","last"),
            amount_eur_mn_raw=("amount_eur_mn_raw","last"),
            transaction_count_thousand_raw=("transaction_count_thousand_raw","last"),
            customer_segment=("customer_segment","last"),
            source_system=("source_system","last"),
            domestic_share=("domestic_share","mean"),
            remote_share=("remote_share","mean"),
            merchant_sector=("merchant_sector","last"),
            submission_timestamp=("submission_timestamp","max"),
            is_revision=("is_revision","max"),
            migration_wave=("migration_wave","max"),
            duplicate_count=("duplicate_sequence","max"),
            quarter_period=("quarter_period","last"),
            quarter_end=("quarter_end","last"),
        )
        self.audit("resolve_duplicates", resolved, "deduplicated reporting cells using source priority")
        return resolved

    def clean_values(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        out["flag_missing_amount"] = out["amount_eur_mn_raw"].isna()
        out["flag_negative_amount"] = out["amount_eur_mn_raw"] < 0
        out["amount_eur_mn_clean"] = out["amount_eur_mn_raw"].abs()
        out["transaction_count_thousand_clean"] = out["transaction_count_thousand_raw"].abs()
        out = out.sort_values(["country_final","instrument","channel","quarter_period"])
        out["amount_eur_mn_clean"] = out.groupby(["country_final","instrument","channel"])["amount_eur_mn_clean"].transform(lambda s: s.interpolate(limit_direction="both"))
        out["transaction_count_thousand_clean"] = out.groupby(["country_final","instrument","channel"])["transaction_count_thousand_clean"].transform(lambda s: s.interpolate(limit_direction="both"))
        out["amount_eur_mn_winsor"] = out.groupby(["country_final","instrument"])["amount_eur_mn_clean"].transform(winsorize)
        out["ticket_eur_clean"] = out["amount_eur_mn_winsor"] * 1_000_000 / (out["transaction_count_thousand_clean"] * 1_000).replace(0, np.nan)
        out["ticket_robust_z"] = out.groupby(["instrument","channel"])["ticket_eur_clean"].transform(robust_zscore)
        out["flag_extreme_ticket"] = out["ticket_robust_z"].abs() > 5
        self.audit("clean_values", out, "imputed, sign-corrected and winsorised source values")
        return out

    def integrate_sources(self, df: pd.DataFrame, bundle: SourceBundle) -> pd.DataFrame:
        out = df.copy()
        fraud = bundle.fraud_reports.groupby(["psp_id","country","quarter","instrument","channel"], as_index=False).agg(fraud_count=("fraud_count","sum"), fraud_amount_eur_mn=("fraud_amount_eur_mn","sum"), reimbursed_amount_eur_mn=("reimbursed_amount_eur_mn","sum"), sca_exempt_share=("sca_exempt_share","mean"))
        out = out.merge(fraud, left_on=["psp_id","country_final","quarter","instrument","channel"], right_on=["psp_id","country","quarter","instrument","channel"], how="left", suffixes=("","_fraud"))
        out = out.drop(columns=[c for c in ["country_fraud"] if c in out.columns])
        terminals = bundle.terminal_inventory.groupby(["psp_id","country","quarter"], as_index=False).sum(numeric_only=True)
        cards = bundle.card_inventory.groupby(["psp_id","country","quarter"], as_index=False).mean(numeric_only=True)
        incidents = bundle.operational_incidents.groupby(["psp_id","country","quarter"], as_index=False).agg(incident_count=("incident_type","size"), incident_materiality=("materiality_score","sum"), outage_hours=("duration_hours","sum"))
        macro = bundle.macro_panel.copy()
        out = out.merge(terminals, left_on=["psp_id","country_final","quarter"], right_on=["psp_id","country","quarter"], how="left", suffixes=("","_term"))
        out = out.merge(cards, left_on=["psp_id","country_final","quarter"], right_on=["psp_id","country","quarter"], how="left", suffixes=("","_card"))
        out = out.merge(incidents, left_on=["psp_id","country_final","quarter"], right_on=["psp_id","country","quarter"], how="left", suffixes=("","_incident"))
        out = out.merge(macro, left_on=["country_final","quarter"], right_on=["country","quarter"], how="left", suffixes=("","_macro"))
        for col in ["fraud_count","fraud_amount_eur_mn","reimbursed_amount_eur_mn","incident_count","incident_materiality","outage_hours"]:
            if col in out:
                out[col] = out[col].fillna(0)
        self.audit("integrate_sources", out, "joined fraud, terminal, card, macro and incident datasets")
        return out

    def feature_engineer(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        out["fraud_value_rate"] = out["fraud_amount_eur_mn"] / out["amount_eur_mn_winsor"].replace(0, np.nan)
        out["fraud_count_rate"] = out["fraud_count"] / out["transaction_count_thousand_clean"].replace(0, np.nan) / 1000
        out["reimbursement_ratio"] = out["reimbursed_amount_eur_mn"] / out["fraud_amount_eur_mn"].replace(0, np.nan)
        out["late_submission_days"] = (out["submission_timestamp"] - out["quarter_end"]).dt.days
        out["flag_late_submission"] = out["late_submission_days"] > 60
        out["digital_payment_flag"] = out["instrument"].isin(["instant_payments","mobile_wallets","open_banking_initiations","e_money"])
        out["amount_per_terminal"] = out["amount_eur_mn_winsor"] / out["pos_terminals"].replace(0, np.nan)
        out["amount_per_card"] = out["amount_eur_mn_winsor"] / out["cards_issued"].replace(0, np.nan)
        out["remote_domestic_interaction"] = out["remote_share"].fillna(0) * out["domestic_share"].fillna(0)
        self.audit("feature_engineer", out, "created fraud, timing, terminal, card and digitalisation indicators")
        return out

    def instrument_table(self, df: pd.DataFrame) -> pd.DataFrame:
        out = df.groupby(["country_final","quarter","quarter_period","instrument"], as_index=False).agg(amount_eur_mn=("amount_eur_mn_winsor","sum"), transactions_thousand=("transaction_count_thousand_clean","sum"), fraud_amount_eur_mn=("fraud_amount_eur_mn","sum"), fraud_count=("fraud_count","sum"), remote_share=("remote_share","mean"), domestic_share=("domestic_share","mean"), late_submission_rate=("flag_late_submission","mean"))
        totals = out.groupby(["country_final","quarter"], as_index=False)["amount_eur_mn"].sum().rename(columns={"amount_eur_mn":"country_total_amount_eur_mn"})
        out = out.merge(totals, on=["country_final","quarter"], how="left")
        out["instrument_share"] = out["amount_eur_mn"] / out["country_total_amount_eur_mn"].replace(0, np.nan)
        out = out.sort_values(["country_final","instrument","quarter_period"])
        out["instrument_yoy_growth"] = out.groupby(["country_final","instrument"])["amount_eur_mn"].pct_change(4)
        out["instrument_peer_z"] = out.groupby(["quarter","instrument"])["instrument_yoy_growth"].transform(robust_zscore)
        self.audit("instrument_table", out, "created country-instrument-quarter table")
        return out

    def country_table(self, df: pd.DataFrame, instrument: pd.DataFrame) -> pd.DataFrame:
        out = df.groupby(["country_final","quarter","quarter_period"], as_index=False).agg(total_amount_eur_mn=("amount_eur_mn_winsor","sum"), total_transactions_thousand=("transaction_count_thousand_clean","sum"), fraud_amount_eur_mn=("fraud_amount_eur_mn","sum"), fraud_count=("fraud_count","sum"), late_submission_rate=("flag_late_submission","mean"), negative_reports=("flag_negative_amount","sum"), missing_reports=("flag_missing_amount","sum"), duplicate_reports=("duplicate_count","sum"), incident_materiality=("incident_materiality","sum"), outage_hours=("outage_hours","sum"), real_gdp_growth_qoq=("real_gdp_growth_qoq","mean"), hicp_inflation_yoy=("hicp_inflation_yoy","mean"), unemployment_rate=("unemployment_rate","mean"), policy_rate=("policy_rate","mean"), internet_penetration=("internet_penetration","mean"))
        out = out.sort_values(["country_final","quarter_period"])
        out["avg_ticket_eur"] = out["total_amount_eur_mn"] * 1_000_000 / (out["total_transactions_thousand"] * 1_000).replace(0, np.nan)
        out["fraud_value_rate"] = out["fraud_amount_eur_mn"] / out["total_amount_eur_mn"].replace(0, np.nan)
        out["qoq_amount_growth"] = out.groupby("country_final")["total_amount_eur_mn"].pct_change()
        out["yoy_amount_growth"] = out.groupby("country_final")["total_amount_eur_mn"].pct_change(4)
        out["peer_z_yoy_amount"] = out.groupby("quarter")["yoy_amount_growth"].transform(robust_zscore)
        components = instrument.groupby(["country_final","quarter"], as_index=False)["amount_eur_mn"].sum().rename(columns={"amount_eur_mn":"instrument_component_sum"})
        out = out.merge(components, on=["country_final","quarter"], how="left")
        out["component_to_total_ratio"] = out["instrument_component_sum"] / out["total_amount_eur_mn"].replace(0, np.nan)
        out["flag_component_gap"] = (out["component_to_total_ratio"] - 1).abs() > 0.025
        self.audit("country_table", out, "collapsed micro cells to country-quarter production table")
        return out

    def review_pack(self, df: pd.DataFrame, country: pd.DataFrame) -> pd.DataFrame:
        out = df.copy()
        out["cell_outlier_z"] = out.groupby(["country_final","instrument","channel"])["amount_eur_mn_winsor"].transform(robust_zscore)
        out["flag_cell_outlier"] = out["cell_outlier_z"].abs() > 5
        out["severity"] = 5*out["flag_missing_amount"].astype(int) + 5*out["flag_negative_amount"].astype(int) + 4*out["flag_cell_outlier"].fillna(False).astype(int) + 3*out["flag_late_submission"].fillna(False).astype(int) + 2*out["flag_extreme_ticket"].fillna(False).astype(int) + 2*(out["incident_materiality"].fillna(0) > 8).astype(int)
        issues = out.loc[out["severity"] > 0, ["psp_id","country_final","quarter","instrument","channel","amount_eur_mn_raw","amount_eur_mn_winsor","transaction_count_thousand_clean","severity","flag_missing_amount","flag_negative_amount","flag_cell_outlier","flag_late_submission","flag_extreme_ticket","source_system","migration_wave","late_submission_days","cell_outlier_z"]].copy()
        if not issues.empty:
            flags = ["flag_missing_amount","flag_negative_amount","flag_cell_outlier","flag_late_submission","flag_extreme_ticket"]
            issues["review_note"] = issues.apply(lambda r: "; ".join([f.replace("flag_","") for f in flags if bool(r.get(f, False))]), axis=1)
        gaps = country.loc[country["flag_component_gap"], ["country_final","quarter","component_to_total_ratio"]].copy()
        if not gaps.empty:
            gaps["psp_id"] = "ALL"
            gaps["instrument"] = "all_instruments"
            gaps["channel"] = "all_channels"
            gaps["severity"] = 4
            gaps["review_note"] = "component-total reconciliation gap"
            issues = pd.concat([issues, gaps[["psp_id","country_final","quarter","instrument","channel","severity","review_note"]]], ignore_index=True, sort=False)
        self.audit("review_pack", issues, "built severity-ranked analyst review queue")
        return issues.sort_values(["severity","country_final","quarter"], ascending=[False, True, True]) if not issues.empty else issues

    def quality_summary(self, df: pd.DataFrame, review: pd.DataFrame) -> pd.DataFrame:
        out = df.groupby(["country_final","quarter"], as_index=False).agg(reporting_cells=("report_id","count"), missing_rate=("flag_missing_amount","mean"), negative_rate=("flag_negative_amount","mean"), late_rate=("flag_late_submission","mean"), duplicate_cells=("duplicate_count","sum"), mean_ticket=("ticket_eur_clean","mean"), incident_materiality=("incident_materiality","sum"))
        counts = review.groupby(["country_final","quarter"], as_index=False).agg(review_issues=("severity","size"), max_severity=("severity","max")) if not review.empty else pd.DataFrame(columns=["country_final","quarter","review_issues","max_severity"])
        out = out.merge(counts, on=["country_final","quarter"], how="left")
        out[["review_issues","max_severity"]] = out[["review_issues","max_severity"]].fillna(0)
        out["quality_score"] = (100 - 120*out["missing_rate"] - 100*out["negative_rate"] - 25*out["late_rate"] - 2*out["review_issues"] - 0.5*out["incident_materiality"]).clip(0, 100)
        self.audit("quality_summary", out, "computed data-quality score")
        return out

    def dashboard(self, country: pd.DataFrame, instrument: pd.DataFrame, quality: pd.DataFrame) -> pd.DataFrame:
        wide = instrument.pivot_table(index=["country_final","quarter"], columns="instrument", values="instrument_share", aggfunc="mean").reset_index()
        wide.columns = [str(c) for c in wide.columns]
        out = country.merge(quality, on=["country_final","quarter"], how="left", suffixes=("","_quality")).merge(wide, on=["country_final","quarter"], how="left")
        out["alert_level"] = pd.cut(out["quality_score"], bins=[-1,60,80,92,101], labels=["critical","watch","normal","strong"])
        self.audit("dashboard", out, "created dashboard-ready monitoring table")
        return out

    def migration_compare(self, df: pd.DataFrame) -> pd.DataFrame:
        legacy = df.groupby(["country_final","quarter"], as_index=False)["amount_eur_mn_raw"].sum().rename(columns={"amount_eur_mn_raw":"legacy_total"})
        new = df.groupby(["country_final","quarter"], as_index=False)["amount_eur_mn_winsor"].sum().rename(columns={"amount_eur_mn_winsor":"new_total"})
        out = legacy.merge(new, on=["country_final","quarter"], how="outer")
        out["absolute_difference"] = out["new_total"] - out["legacy_total"]
        out["relative_difference"] = out["absolute_difference"] / out["legacy_total"].replace(0, np.nan)
        out["migration_status"] = np.select([out["relative_difference"].abs() <= 0.005, out["relative_difference"].abs() <= 0.02], ["pass","review"], default="fail")
        self.audit("migration_compare", out, "compared legacy and cleaned production aggregates")
        return out

    def produce(self, bundle: SourceBundle) -> ProductionArtifacts:
        df = self.standardise(bundle.quarterly_payments)
        df = self.normalise_units(df)
        df = self.resolve_duplicates(df)
        df = self.clean_values(df)
        df = self.integrate_sources(df, bundle)
        df = self.feature_engineer(df)
        instrument = self.instrument_table(df)
        country = self.country_table(df, instrument)
        review = self.review_pack(df, country)
        quality = self.quality_summary(df, review)
        dashboard = self.dashboard(country, instrument, quality)
        migration = self.migration_compare(df)
        return ProductionArtifacts(df, country, instrument, review, quality, pd.DataFrame(self.audit_records), dashboard, migration)


def save_bundle(bundle: SourceBundle, root: str | Path) -> dict[str, Path]:
    raw = ensure_dir(Path(root) / "data" / "raw")
    paths = {}
    for name, frame in bundle.__dict__.items():
        path = raw / f"{name}.csv"
        frame.to_csv(path, index=False)
        paths[name] = path
    return paths


def save_artifacts(artifacts: ProductionArtifacts, root: str | Path) -> dict[str, Path]:
    out = ensure_dir(Path(root) / "outputs")
    paths = {}
    for name, frame in artifacts.__dict__.items():
        path = out / f"{name}.csv"
        frame.to_csv(path, index=False)
        paths[name] = path
    try:
        with pd.ExcelWriter(out / "payments_statistics_review_pack.xlsx") as writer:
            for name, frame in artifacts.__dict__.items():
                frame.head(5000).to_excel(writer, sheet_name=name[:31], index=False)
    except Exception:
        pass
    return paths


def run_production_cycle(
    root: str | Path = ".",
    seed: int = 2026,
    *,
    profile: str = "ci",
) -> ProductionArtifacts:
    settings = production_profile(profile)
    factory = PaymentDataFactory(seed=seed, **settings)
    bundle = factory.build_bundle()
    save_bundle(bundle, root)
    engine = PaymentProductionEngine()
    artifacts = engine.produce(bundle)
    save_artifacts(artifacts, root)
    return artifacts


# ---------------------------------------------------------------------------
# Reproducible execution profiles
# ---------------------------------------------------------------------------


def production_profile(name: str) -> dict[str, Any]:
    """Return a transparent scale profile for local, CI or full demonstrations."""

    profiles: dict[str, dict[str, Any]] = {
        "ci": {
            "start": "2020Q1",
            "end": "2024Q4",
            "countries": ["ES", "DE", "FR", "IT", "NL"],
            "n_psp": 12,
            "n_merchants": 120,
        },
        "demo": {
            "start": "2018Q1",
            "end": "2025Q4",
            "countries": [
                "ES",
                "DE",
                "FR",
                "IT",
                "NL",
                "BE",
                "PT",
                "AT",
                "IE",
                "FI",
            ],
            "n_psp": 28,
            "n_merchants": 400,
        },
        "full": {
            "start": "2017Q1",
            "end": "2026Q2",
            "countries": EU_COUNTRIES.copy(),
            "n_psp": 70,
            "n_merchants": 1200,
        },
    }
    if name not in profiles:
        choices = ", ".join(sorted(profiles))
        raise ValueError(f"Unknown profile {name!r}; choose one of: {choices}")
    return profiles[name].copy()


# ---------------------------------------------------------------------------
# Explicit business definitions and data contracts
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class FieldSpec:
    """Machine-readable definition of one statistical variable."""

    name: str
    dtype: str
    nullable: bool
    description: str
    unit: str = ""
    allowed: tuple[str, ...] = ()
    minimum: float | None = None
    maximum: float | None = None


@dataclass(frozen=True)
class TableContract:
    """Schema and key expectations for one source or statistical output."""

    name: str
    grain: str
    primary_key: tuple[str, ...]
    fields: tuple[FieldSpec, ...]
    owner: str
    frequency: str
    confidentiality: str

    @property
    def required_columns(self) -> tuple[str, ...]:
        return tuple(field.name for field in self.fields)

    def field(self, name: str) -> FieldSpec:
        matches = [field for field in self.fields if field.name == name]
        if not matches:
            raise KeyError(f"{name!r} is not defined in contract {self.name!r}")
        return matches[0]


PAYMENTS_SOURCE_CONTRACT = TableContract(
    name="quarterly_payments",
    grain="one PSP, country, quarter, instrument and channel submission",
    primary_key=(
        "psp_id",
        "country",
        "quarter",
        "instrument",
        "channel",
    ),
    owner="payments_statistics",
    frequency="quarterly",
    confidentiality="synthetic portfolio data",
    fields=(
        FieldSpec(
            name="report_id",
            dtype="string",
            nullable=False,
            description="Source-system report identifier.",
        ),
        FieldSpec(
            name="psp_id",
            dtype="string",
            nullable=False,
            description="Synthetic payment service provider identifier.",
        ),
        FieldSpec(
            name="country",
            dtype="string",
            nullable=False,
            description="ISO-like reporting country code.",
            allowed=tuple(EU_COUNTRIES),
        ),
        FieldSpec(
            name="country_reported",
            dtype="string",
            nullable=False,
            description="Country value as delivered by the source.",
        ),
        FieldSpec(
            name="quarter",
            dtype="period[Q]",
            nullable=False,
            description="Reference quarter of the reported flow.",
        ),
        FieldSpec(
            name="instrument",
            dtype="category",
            nullable=False,
            description="Payment instrument used by the customer.",
            allowed=tuple(PAYMENT_INSTRUMENTS),
        ),
        FieldSpec(
            name="channel",
            dtype="category",
            nullable=False,
            description="Initiation or acceptance channel.",
            allowed=tuple(PAYMENT_CHANNELS),
        ),
        FieldSpec(
            name="customer_segment",
            dtype="category",
            nullable=False,
            description="Institutional customer segment.",
            allowed=tuple(CUSTOMER_SEGMENTS),
        ),
        FieldSpec(
            name="source_system",
            dtype="category",
            nullable=False,
            description="System from which the observation originated.",
            allowed=tuple(DATA_SOURCES),
        ),
        FieldSpec(
            name="amount_reported",
            dtype="float64",
            nullable=True,
            description="Nominal submitted payment amount before conversion.",
        ),
        FieldSpec(
            name="amount_unit",
            dtype="category",
            nullable=False,
            description="Unit attached to the reported amount.",
            allowed=("EUR", "EUR cents", "thousand EUR", "million EUR"),
        ),
        FieldSpec(
            name="transaction_count_reported",
            dtype="float64",
            nullable=True,
            description="Reported transaction count in thousands.",
            unit="thousand transactions",
            minimum=0,
        ),
        FieldSpec(
            name="domestic_share",
            dtype="float64",
            nullable=True,
            description="Share of activity classified as domestic.",
            unit="ratio",
            minimum=0,
            maximum=1,
        ),
        FieldSpec(
            name="remote_share",
            dtype="float64",
            nullable=True,
            description="Share initiated without physical presence.",
            unit="ratio",
            minimum=0,
            maximum=1,
        ),
        FieldSpec(
            name="merchant_sector",
            dtype="category",
            nullable=True,
            description="Merchant activity classification.",
            allowed=tuple(MCC_SECTORS),
        ),
        FieldSpec(
            name="submission_timestamp",
            dtype="datetime64[ns]",
            nullable=False,
            description="Timestamp of the submission used for timeliness checks.",
        ),
        FieldSpec(
            name="is_revision",
            dtype="bool",
            nullable=False,
            description="Whether the row replaces an earlier transmission.",
        ),
        FieldSpec(
            name="migration_wave",
            dtype="int64",
            nullable=False,
            description="Reporting-system migration cohort.",
            minimum=1,
            maximum=4,
        ),
    ),
)


COUNTRY_OUTPUT_CONTRACT = TableContract(
    name="country_quarter",
    grain="one reporting country and reference quarter",
    primary_key=("country_final", "quarter"),
    owner="payments_statistics",
    frequency="quarterly",
    confidentiality="publishable synthetic aggregate",
    fields=(
        FieldSpec(
            name="country_final",
            dtype="string",
            nullable=False,
            description="Harmonised reporting country.",
            allowed=tuple(EU_COUNTRIES),
        ),
        FieldSpec(
            name="quarter",
            dtype="period[Q]",
            nullable=False,
            description="Reference quarter.",
        ),
        FieldSpec(
            name="quarter_period",
            dtype="period[Q]",
            nullable=False,
            description="Pandas period used for sorting and lags.",
        ),
        FieldSpec(
            name="total_amount_eur_mn",
            dtype="float64",
            nullable=False,
            description="Quality-adjusted payments value.",
            unit="EUR millions",
            minimum=0,
        ),
        FieldSpec(
            name="total_transactions_thousand",
            dtype="float64",
            nullable=False,
            description="Quality-adjusted transaction count.",
            unit="thousand transactions",
            minimum=0,
        ),
        FieldSpec(
            name="fraud_amount_eur_mn",
            dtype="float64",
            nullable=True,
            description="Reported fraudulent value.",
            unit="EUR millions",
            minimum=0,
        ),
        FieldSpec(
            name="fraud_count",
            dtype="float64",
            nullable=True,
            description="Reported fraudulent transactions.",
            unit="transactions",
            minimum=0,
        ),
        FieldSpec(
            name="late_submission_rate",
            dtype="float64",
            nullable=True,
            description="Share of late reporting cells.",
            unit="ratio",
            minimum=0,
            maximum=1,
        ),
        FieldSpec(
            name="negative_reports",
            dtype="int64",
            nullable=False,
            description="Rows rejected because reported amounts were negative.",
            minimum=0,
        ),
        FieldSpec(
            name="missing_reports",
            dtype="int64",
            nullable=False,
            description="Rows with missing reported amounts.",
            minimum=0,
        ),
        FieldSpec(
            name="duplicate_reports",
            dtype="int64",
            nullable=False,
            description="Source submissions resolved under revision precedence.",
            minimum=0,
        ),
        FieldSpec(
            name="incident_materiality",
            dtype="float64",
            nullable=True,
            description="Sum of linked incident materiality scores.",
            minimum=0,
        ),
        FieldSpec(
            name="outage_hours",
            dtype="float64",
            nullable=True,
            description="Hours of service outage reported in the quarter.",
            unit="hours",
            minimum=0,
        ),
        FieldSpec(
            name="real_gdp_growth_qoq",
            dtype="float64",
            nullable=True,
            description="Synthetic quarterly macroeconomic benchmark.",
            unit="rate",
        ),
        FieldSpec(
            name="hicp_inflation_yoy",
            dtype="float64",
            nullable=True,
            description="Synthetic annual inflation benchmark.",
            unit="rate",
        ),
        FieldSpec(
            name="unemployment_rate",
            dtype="float64",
            nullable=True,
            description="Synthetic labour-market benchmark.",
            unit="ratio",
            minimum=0,
            maximum=1,
        ),
        FieldSpec(
            name="policy_rate",
            dtype="float64",
            nullable=True,
            description="Synthetic monetary-policy rate.",
            unit="rate",
        ),
        FieldSpec(
            name="internet_penetration",
            dtype="float64",
            nullable=True,
            description="Synthetic share of population with internet access.",
            unit="ratio",
            minimum=0,
            maximum=1,
        ),
        FieldSpec(
            name="avg_ticket_eur",
            dtype="float64",
            nullable=True,
            description="Average payment value.",
            unit="EUR per transaction",
            minimum=0,
        ),
        FieldSpec(
            name="fraud_value_rate",
            dtype="float64",
            nullable=True,
            description="Fraud value divided by payment value.",
            unit="ratio",
            minimum=0,
        ),
        FieldSpec(
            name="qoq_amount_growth",
            dtype="float64",
            nullable=True,
            description="Quarter-on-quarter payments growth.",
            unit="rate",
        ),
        FieldSpec(
            name="yoy_amount_growth",
            dtype="float64",
            nullable=True,
            description="Year-on-year payments growth.",
            unit="rate",
        ),
        FieldSpec(
            name="peer_z_yoy_amount",
            dtype="float64",
            nullable=True,
            description="Robust peer z-score of annual growth.",
        ),
        FieldSpec(
            name="instrument_component_sum",
            dtype="float64",
            nullable=False,
            description="Sum of instrument components.",
            unit="EUR millions",
            minimum=0,
        ),
        FieldSpec(
            name="component_to_total_ratio",
            dtype="float64",
            nullable=True,
            description="Instrument sum divided by the independently aggregated total.",
            unit="ratio",
        ),
        FieldSpec(
            name="flag_component_gap",
            dtype="bool",
            nullable=False,
            description="Whether component reconciliation exceeds tolerance.",
        ),
    ),
)


CONTRACTS: dict[str, TableContract] = {
    PAYMENTS_SOURCE_CONTRACT.name: PAYMENTS_SOURCE_CONTRACT,
    COUNTRY_OUTPUT_CONTRACT.name: COUNTRY_OUTPUT_CONTRACT,
}


@dataclass(frozen=True)
class ValidationIssue:
    table: str
    rule: str
    severity: str
    column: str
    failures: int
    observations: int
    failure_rate: float
    detail: str


class ContractValidator:
    """Validate structure, domains, ranges and primary-key uniqueness."""

    def __init__(self, contract: TableContract):
        self.contract = contract

    def validate(self, frame: pd.DataFrame) -> pd.DataFrame:
        issues: list[ValidationIssue] = []
        issues.extend(self._missing_columns(frame))
        if any(issue.rule == "required_column" for issue in issues):
            return pd.DataFrame(asdict(issue) for issue in issues)
        issues.extend(self._nullability(frame))
        issues.extend(self._allowed_values(frame))
        issues.extend(self._numeric_bounds(frame))
        issues.extend(self._primary_key(frame))
        return pd.DataFrame(asdict(issue) for issue in issues)

    def _issue(
        self,
        rule: str,
        severity: str,
        column: str,
        failures: int,
        observations: int,
        detail: str,
    ) -> ValidationIssue:
        rate = failures / observations if observations else 0.0
        return ValidationIssue(
            table=self.contract.name,
            rule=rule,
            severity=severity,
            column=column,
            failures=int(failures),
            observations=int(observations),
            failure_rate=float(rate),
            detail=detail,
        )

    def _missing_columns(self, frame: pd.DataFrame) -> list[ValidationIssue]:
        output: list[ValidationIssue] = []
        for column in self.contract.required_columns:
            if column not in frame:
                output.append(
                    self._issue(
                        rule="required_column",
                        severity="error",
                        column=column,
                        failures=1,
                        observations=1,
                        detail="Column declared in the contract is absent.",
                    )
                )
        return output

    def _nullability(self, frame: pd.DataFrame) -> list[ValidationIssue]:
        output: list[ValidationIssue] = []
        for spec in self.contract.fields:
            if spec.nullable:
                continue
            failures = int(frame[spec.name].isna().sum())
            if failures:
                output.append(
                    self._issue(
                        rule="not_null",
                        severity="error",
                        column=spec.name,
                        failures=failures,
                        observations=len(frame),
                        detail="A non-nullable business field contains missing values.",
                    )
                )
        return output

    def _allowed_values(self, frame: pd.DataFrame) -> list[ValidationIssue]:
        output: list[ValidationIssue] = []
        for spec in self.contract.fields:
            if not spec.allowed:
                continue
            values = frame[spec.name].dropna().astype(str)
            invalid = ~values.isin(spec.allowed)
            failures = int(invalid.sum())
            if failures:
                examples = sorted(values.loc[invalid].unique())[:5]
                output.append(
                    self._issue(
                        rule="allowed_values",
                        severity="error",
                        column=spec.name,
                        failures=failures,
                        observations=len(values),
                        detail=f"Unexpected values include {examples}.",
                    )
                )
        return output

    def _numeric_bounds(self, frame: pd.DataFrame) -> list[ValidationIssue]:
        output: list[ValidationIssue] = []
        for spec in self.contract.fields:
            if spec.minimum is None and spec.maximum is None:
                continue
            values = pd.to_numeric(frame[spec.name], errors="coerce")
            invalid = pd.Series(False, index=values.index)
            if spec.minimum is not None:
                invalid |= values < spec.minimum
            if spec.maximum is not None:
                invalid |= values > spec.maximum
            failures = int(invalid.fillna(False).sum())
            if failures:
                output.append(
                    self._issue(
                        rule="numeric_bounds",
                        severity="error",
                        column=spec.name,
                        failures=failures,
                        observations=int(values.notna().sum()),
                        detail=(
                            f"Expected range [{spec.minimum}, {spec.maximum}]."
                        ),
                    )
                )
        return output

    def _primary_key(self, frame: pd.DataFrame) -> list[ValidationIssue]:
        duplicated = frame.duplicated(list(self.contract.primary_key), keep=False)
        failures = int(duplicated.sum())
        if not failures:
            return []
        return [
            self._issue(
                rule="primary_key",
                severity="error",
                column="|".join(self.contract.primary_key),
                failures=failures,
                observations=len(frame),
                detail="Multiple rows share the declared statistical grain.",
            )
        ]


# ---------------------------------------------------------------------------
# Revision analysis and shadow-production acceptance
# ---------------------------------------------------------------------------


VINTAGE_ORDER = {
    "flash": 0,
    "first_release": 1,
    "final": 2,
}


def prepare_revision_panel(vintages: pd.DataFrame) -> pd.DataFrame:
    """Place flash, first and final observations on one comparable row."""

    required = {
        "report_id",
        "country",
        "quarter",
        "instrument",
        "channel",
        "vintage",
        "amount_reported_vintage",
    }
    missing = required.difference(vintages.columns)
    if missing:
        raise ValueError(f"Revision input misses columns: {sorted(missing)}")
    index = [
        "report_id",
        "country",
        "quarter",
        "instrument",
        "channel",
    ]
    panel = vintages.pivot_table(
        index=index,
        columns="vintage",
        values="amount_reported_vintage",
        aggfunc="last",
    ).reset_index()
    panel.columns.name = None
    for vintage in VINTAGE_ORDER:
        if vintage not in panel:
            panel[vintage] = np.nan
    panel["flash_revision"] = panel["final"] - panel["flash"]
    panel["first_release_revision"] = panel["final"] - panel["first_release"]
    panel["flash_revision_rate"] = (
        panel["flash_revision"] / panel["final"].replace(0, np.nan)
    )
    panel["first_release_revision_rate"] = (
        panel["first_release_revision"] / panel["final"].replace(0, np.nan)
    )
    return panel


def revision_diagnostics(vintages: pd.DataFrame) -> pd.DataFrame:
    """Calculate bias and revision dispersion by instrument."""

    panel = prepare_revision_panel(vintages)
    rows: list[dict[str, Any]] = []
    for instrument, part in panel.groupby("instrument"):
        for release, column in (
            ("flash", "flash_revision_rate"),
            ("first_release", "first_release_revision_rate"),
        ):
            values = part[column].replace([np.inf, -np.inf], np.nan).dropna()
            rows.append(
                {
                    "instrument": instrument,
                    "release": release,
                    "observations": int(len(values)),
                    "mean_revision_rate": float(values.mean()),
                    "median_revision_rate": float(values.median()),
                    "mean_absolute_revision": float(values.abs().mean()),
                    "revision_rmse": float(np.sqrt(np.mean(np.square(values)))),
                    "positive_revision_share": float((values > 0).mean()),
                    "large_revision_share": float((values.abs() > 0.05).mean()),
                }
            )
    return pd.DataFrame(rows)


@dataclass(frozen=True)
class MigrationTolerance:
    absolute_eur_mn: float = 1.0
    relative: float = 0.005
    missing_keys: int = 0
    duplicate_keys: int = 0


class ShadowProductionComparator:
    """Compare a legacy extract with a candidate production implementation."""

    def __init__(
        self,
        keys: Sequence[str],
        measures: Sequence[str],
        tolerance: MigrationTolerance | None = None,
    ):
        self.keys = list(keys)
        self.measures = list(measures)
        self.tolerance = tolerance or MigrationTolerance()

    def compare(
        self,
        legacy: pd.DataFrame,
        candidate: pd.DataFrame,
    ) -> tuple[pd.DataFrame, pd.DataFrame]:
        self._assert_columns(legacy, "legacy")
        self._assert_columns(candidate, "candidate")
        merged = legacy[self.keys + self.measures].merge(
            candidate[self.keys + self.measures],
            on=self.keys,
            how="outer",
            suffixes=("_legacy", "_candidate"),
            indicator=True,
        )
        results: list[pd.DataFrame] = []
        for measure in self.measures:
            block = merged[self.keys + ["_merge"]].copy()
            block["measure"] = measure
            block["legacy_value"] = pd.to_numeric(
                merged[f"{measure}_legacy"],
                errors="coerce",
            )
            block["candidate_value"] = pd.to_numeric(
                merged[f"{measure}_candidate"],
                errors="coerce",
            )
            block["absolute_difference"] = (
                block["candidate_value"] - block["legacy_value"]
            )
            block["relative_difference"] = (
                block["absolute_difference"]
                / block["legacy_value"].replace(0, np.nan)
            )
            block["within_absolute_tolerance"] = (
                block["absolute_difference"].abs()
                <= self.tolerance.absolute_eur_mn
            )
            block["within_relative_tolerance"] = (
                block["relative_difference"].abs() <= self.tolerance.relative
            )
            block["cell_status"] = np.select(
                [
                    block["_merge"] != "both",
                    (
                        block["within_absolute_tolerance"]
                        | block["within_relative_tolerance"]
                    ),
                ],
                ["missing_key", "pass"],
                default="fail",
            )
            results.append(block)
        cells = pd.concat(results, ignore_index=True)
        summary = (
            cells.groupby(["measure", "cell_status"], as_index=False)
            .size()
            .pivot(index="measure", columns="cell_status", values="size")
            .fillna(0)
            .reset_index()
        )
        summary.columns.name = None
        for status in ("pass", "fail", "missing_key"):
            if status not in summary:
                summary[status] = 0
        summary["acceptance_status"] = np.where(
            (summary["fail"] == 0)
            & (summary["missing_key"] <= self.tolerance.missing_keys),
            "pass",
            "fail",
        )
        return cells, summary

    def _assert_columns(self, frame: pd.DataFrame, label: str) -> None:
        expected = set(self.keys + self.measures)
        missing = expected.difference(frame.columns)
        if missing:
            raise ValueError(f"{label} frame misses {sorted(missing)}")
        duplicates = int(frame.duplicated(self.keys).sum())
        if duplicates > self.tolerance.duplicate_keys:
            raise ValueError(
                f"{label} has {duplicates} duplicated keys; "
                f"tolerance is {self.tolerance.duplicate_keys}"
            )


# ---------------------------------------------------------------------------
# Source adapters and ECB Data Portal interface
# ---------------------------------------------------------------------------


class SourceAdapter:
    """Small interface shared by local files and API responses."""

    def read(self) -> pd.DataFrame:
        raise NotImplementedError


@dataclass
class CsvSource(SourceAdapter):
    path: Path
    separator: str = ","
    encoding: str = "utf-8"

    def read(self) -> pd.DataFrame:
        return pd.read_csv(
            self.path,
            sep=self.separator,
            encoding=self.encoding,
            low_memory=False,
        )


@dataclass
class JsonRecordsSource(SourceAdapter):
    path: Path

    def read(self) -> pd.DataFrame:
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        if isinstance(payload, dict) and "data" in payload:
            payload = payload["data"]
        if not isinstance(payload, list):
            raise ValueError("JSON source must contain a list of records")
        return pd.DataFrame(payload)


@dataclass
class ExcelSource(SourceAdapter):
    path: Path
    sheet_name: str | int = 0

    def read(self) -> pd.DataFrame:
        return pd.read_excel(self.path, sheet_name=self.sheet_name)


@dataclass(frozen=True)
class SdmxQuery:
    dataflow: str
    key: str = ""
    start_period: str | None = None
    end_period: str | None = None
    updated_after: str | None = None
    first_n_observations: int | None = None

    def parameters(self) -> dict[str, str]:
        params: dict[str, str] = {"format": "csvdata"}
        if self.start_period:
            params["startPeriod"] = self.start_period
        if self.end_period:
            params["endPeriod"] = self.end_period
        if self.updated_after:
            params["updatedAfter"] = self.updated_after
        if self.first_n_observations is not None:
            params["firstNObservations"] = str(self.first_n_observations)
        return params


class EcbDataPortalClient:
    """Minimal, auditable reader for the ECB Data Portal SDMX 2.1 endpoint."""

    def __init__(
        self,
        base_url: str = "https://data-api.ecb.europa.eu/service/data",
        timeout_seconds: int = 30,
        user_agent: str = "synthetic-payments-portfolio/1.0",
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.user_agent = user_agent

    def build_url(self, query: SdmxQuery) -> str:
        path = "/".join(
            component.strip("/")
            for component in (self.base_url, query.dataflow, query.key)
            if component != ""
        )
        return f"{path}?{urllib.parse.urlencode(query.parameters())}"

    def fetch_csv(self, query: SdmxQuery) -> pd.DataFrame:
        request = urllib.request.Request(
            self.build_url(query),
            headers={
                "Accept": "text/csv",
                "User-Agent": self.user_agent,
            },
        )
        with urllib.request.urlopen(
            request,
            timeout=self.timeout_seconds,
        ) as response:
            body = response.read().decode("utf-8")
        frame = pd.read_csv(io.StringIO(body))
        frame.columns = [str(column).strip() for column in frame.columns]
        return frame

    def fetch_or_fallback(
        self,
        query: SdmxQuery,
        fallback: Callable[[], pd.DataFrame],
        *,
        allow_network: bool = False,
    ) -> tuple[pd.DataFrame, dict[str, Any]]:
        if not allow_network:
            frame = fallback()
            return frame, {
                "source": "synthetic_fallback",
                "url": self.build_url(query),
                "reason": "network access disabled by default",
            }
        try:
            frame = self.fetch_csv(query)
            return frame, {
                "source": "ecb_data_portal",
                "url": self.build_url(query),
                "reason": "",
            }
        except Exception as exc:
            frame = fallback()
            return frame, {
                "source": "synthetic_fallback",
                "url": self.build_url(query),
                "reason": f"{type(exc).__name__}: {exc}",
            }


# ---------------------------------------------------------------------------
# Relational warehouse and SQL controls
# ---------------------------------------------------------------------------


class PaymentsWarehouse:
    """SQLite implementation of a dimensional payments-statistics store."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path)
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    def initialise(self) -> None:
        with self.connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS dim_country (
                    country_code TEXT PRIMARY KEY,
                    population INTEGER NOT NULL,
                    gdp_per_capita_eur REAL NOT NULL,
                    euro_area_member INTEGER NOT NULL,
                    ncb_code TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS dim_psp (
                    psp_id TEXT PRIMARY KEY,
                    country_code TEXT NOT NULL,
                    legal_name TEXT NOT NULL,
                    license_type TEXT NOT NULL,
                    ownership TEXT NOT NULL,
                    active INTEGER NOT NULL,
                    migration_wave INTEGER NOT NULL,
                    FOREIGN KEY (country_code)
                        REFERENCES dim_country(country_code)
                );

                CREATE TABLE IF NOT EXISTS fact_payment (
                    psp_id TEXT NOT NULL,
                    country_code TEXT NOT NULL,
                    reference_quarter TEXT NOT NULL,
                    instrument TEXT NOT NULL,
                    channel TEXT NOT NULL,
                    amount_eur_mn REAL,
                    transactions_thousand REAL,
                    fraud_amount_eur_mn REAL,
                    late_submission INTEGER NOT NULL,
                    quality_flags INTEGER NOT NULL,
                    source_system TEXT NOT NULL,
                    load_timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (
                        psp_id,
                        country_code,
                        reference_quarter,
                        instrument,
                        channel
                    ),
                    FOREIGN KEY (psp_id) REFERENCES dim_psp(psp_id),
                    FOREIGN KEY (country_code)
                        REFERENCES dim_country(country_code)
                );

                CREATE TABLE IF NOT EXISTS production_run (
                    run_id TEXT PRIMARY KEY,
                    started_at TEXT NOT NULL,
                    finished_at TEXT,
                    profile TEXT NOT NULL,
                    source_rows INTEGER NOT NULL,
                    accepted_rows INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    source_checksum TEXT NOT NULL
                );

                CREATE VIEW IF NOT EXISTS vw_country_quarter AS
                SELECT
                    country_code,
                    reference_quarter,
                    SUM(amount_eur_mn) AS amount_eur_mn,
                    SUM(transactions_thousand) AS transactions_thousand,
                    SUM(fraud_amount_eur_mn) AS fraud_amount_eur_mn,
                    AVG(late_submission) AS late_submission_rate,
                    SUM(quality_flags) AS quality_flags
                FROM fact_payment
                GROUP BY country_code, reference_quarter;

                CREATE VIEW IF NOT EXISTS vw_instrument_share AS
                SELECT
                    country_code,
                    reference_quarter,
                    instrument,
                    SUM(amount_eur_mn) AS instrument_amount_eur_mn,
                    SUM(amount_eur_mn)
                        / NULLIF(
                            SUM(SUM(amount_eur_mn)) OVER (
                                PARTITION BY country_code, reference_quarter
                            ),
                            0
                        ) AS instrument_share
                FROM fact_payment
                GROUP BY country_code, reference_quarter, instrument;
                """
            )

    def load_dimensions(self, bundle: SourceBundle) -> None:
        countries = bundle.country_metadata.rename(
            columns={"country": "country_code"}
        )[
            [
                "country_code",
                "population",
                "gdp_per_capita_eur",
                "euro_area_member",
                "ncb_code",
            ]
        ].copy()
        countries["euro_area_member"] = countries["euro_area_member"].astype(int)
        psps = bundle.psp_registry.rename(
            columns={"country": "country_code"}
        )[
            [
                "psp_id",
                "country_code",
                "legal_name",
                "license_type",
                "ownership",
                "active",
                "migration_wave",
            ]
        ].copy()
        psps["active"] = psps["active"].astype(int)
        with self.connect() as connection:
            countries.to_sql(
                "dim_country",
                connection,
                if_exists="replace",
                index=False,
            )
            psps.to_sql(
                "dim_psp",
                connection,
                if_exists="replace",
                index=False,
            )

    def load_fact(self, cleaned: pd.DataFrame) -> int:
        frame = cleaned.copy()
        quality_columns = [
            "flag_missing_amount",
            "flag_negative_amount",
            "flag_extreme_ticket",
            "flag_late_submission",
        ]
        frame["quality_flags"] = (
            frame[quality_columns].fillna(False).astype(int).sum(axis=1)
        )
        fact = pd.DataFrame(
            {
                "psp_id": frame["psp_id"],
                "country_code": frame["country_final"],
                "reference_quarter": frame["quarter"].astype(str),
                "instrument": frame["instrument"],
                "channel": frame["channel"],
                "amount_eur_mn": frame["amount_eur_mn_winsor"],
                "transactions_thousand": frame[
                    "transaction_count_thousand_clean"
                ],
                "fraud_amount_eur_mn": frame["fraud_amount_eur_mn"],
                "late_submission": frame["flag_late_submission"]
                .fillna(False)
                .astype(int),
                "quality_flags": frame["quality_flags"],
                "source_system": frame["source_system"],
            }
        )
        with self.connect() as connection:
            fact.to_sql(
                "fact_payment",
                connection,
                if_exists="replace",
                index=False,
            )
        return len(fact)

    def query(self, sql: str, parameters: Sequence[Any] = ()) -> pd.DataFrame:
        statement = sql.strip().lower()
        if not statement.startswith(("select", "with", "pragma")):
            raise ValueError("Only read-only SQL is accepted by query()")
        with self.connect() as connection:
            return pd.read_sql_query(sql, connection, params=parameters)

    def run_controls(self) -> pd.DataFrame:
        controls: list[dict[str, Any]] = []
        queries = {
            "orphan_psp": """
                SELECT COUNT(*) AS failures
                FROM fact_payment f
                LEFT JOIN dim_psp p ON f.psp_id = p.psp_id
                WHERE p.psp_id IS NULL
            """,
            "negative_amount": """
                SELECT COUNT(*) AS failures
                FROM fact_payment
                WHERE amount_eur_mn < 0
            """,
            "invalid_quarter": """
                SELECT COUNT(*) AS failures
                FROM fact_payment
                WHERE reference_quarter NOT GLOB '[0-9][0-9][0-9][0-9]Q[1-4]'
            """,
            "duplicate_grain": """
                SELECT COUNT(*) AS failures
                FROM (
                    SELECT
                        psp_id,
                        country_code,
                        reference_quarter,
                        instrument,
                        channel,
                        COUNT(*) AS n
                    FROM fact_payment
                    GROUP BY
                        psp_id,
                        country_code,
                        reference_quarter,
                        instrument,
                        channel
                    HAVING COUNT(*) > 1
                )
            """,
            "instrument_share_outside_unit_interval": """
                SELECT COUNT(*) AS failures
                FROM vw_instrument_share
                WHERE instrument_share < 0 OR instrument_share > 1.000001
            """,
        }
        for name, sql in queries.items():
            result = self.query(sql)
            failures = int(result.iloc[0]["failures"])
            controls.append(
                {
                    "control": name,
                    "failures": failures,
                    "status": "pass" if failures == 0 else "fail",
                }
            )
        return pd.DataFrame(controls)


# ---------------------------------------------------------------------------
# Incremental loads, lineage and operational orchestration
# ---------------------------------------------------------------------------


def dataframe_checksum(frame: pd.DataFrame) -> str:
    """Stable SHA-256 checksum independent of the existing row index."""

    ordered_columns = sorted(str(column) for column in frame.columns)
    canonical = frame[ordered_columns].copy()
    canonical = canonical.sort_values(ordered_columns).reset_index(drop=True)
    payload = canonical.to_csv(index=False, date_format="%Y-%m-%dT%H:%M:%S")
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass
class LoadManifest:
    dataset: str
    rows: int
    columns: int
    checksum: str
    minimum_period: str
    maximum_period: str
    seed: int
    profile: str

    def to_json(self, path: str | Path) -> None:
        Path(path).write_text(
            json.dumps(asdict(self), indent=2, sort_keys=True),
            encoding="utf-8",
        )


def build_manifest(
    frame: pd.DataFrame,
    *,
    dataset: str,
    period_column: str,
    seed: int,
    profile: str,
) -> LoadManifest:
    periods = frame[period_column].astype(str)
    return LoadManifest(
        dataset=dataset,
        rows=len(frame),
        columns=len(frame.columns),
        checksum=dataframe_checksum(frame),
        minimum_period=str(periods.min()),
        maximum_period=str(periods.max()),
        seed=seed,
        profile=profile,
    )


def changed_business_keys(
    previous: pd.DataFrame,
    current: pd.DataFrame,
    *,
    keys: Sequence[str],
    measures: Sequence[str],
) -> pd.DataFrame:
    """Identify inserted, deleted and revised statistical observations."""

    left = previous[list(keys) + list(measures)].copy()
    right = current[list(keys) + list(measures)].copy()
    merged = left.merge(
        right,
        on=list(keys),
        how="outer",
        suffixes=("_previous", "_current"),
        indicator=True,
    )
    changed = merged["_merge"] != "both"
    for measure in measures:
        before = pd.to_numeric(merged[f"{measure}_previous"], errors="coerce")
        after = pd.to_numeric(merged[f"{measure}_current"], errors="coerce")
        unequal = ~np.isclose(
            before,
            after,
            equal_nan=True,
            rtol=1e-10,
            atol=1e-12,
        )
        changed |= unequal
    output = merged.loc[changed].copy()
    output["change_type"] = output["_merge"].map(
        {
            "left_only": "deleted",
            "right_only": "inserted",
            "both": "revised",
        }
    )
    return output.drop(columns="_merge")


@dataclass
class OperationalRun:
    bundle: SourceBundle
    artifacts: ProductionArtifacts
    source_validation: pd.DataFrame
    output_validation: pd.DataFrame
    revision_summary: pd.DataFrame
    warehouse_controls: pd.DataFrame
    manifest: LoadManifest


def execute_operational_run(
    root: str | Path,
    *,
    seed: int = 2026,
    profile: str = "ci",
    persist_raw: bool = False,
) -> OperationalRun:
    """Run the complete synthetic payments production and warehouse workflow."""

    root_path = Path(root).resolve()
    output_path = ensure_dir(root_path / "outputs")
    settings = production_profile(profile)
    factory = PaymentDataFactory(seed=seed, **settings)
    bundle = factory.build_bundle()
    source_validation = ContractValidator(
        PAYMENTS_SOURCE_CONTRACT
    ).validate(bundle.quarterly_payments)
    engine = PaymentProductionEngine()
    artifacts = engine.produce(bundle)
    output_validation = ContractValidator(
        COUNTRY_OUTPUT_CONTRACT
    ).validate(artifacts.country_quarter)
    revision_summary = revision_diagnostics(bundle.revision_vintages)
    if persist_raw:
        save_bundle(bundle, root_path)
    save_artifacts(artifacts, root_path)
    revision_summary.to_csv(
        output_path / "revision_diagnostics.csv",
        index=False,
    )
    source_validation.to_csv(
        output_path / "source_contract_issues.csv",
        index=False,
    )
    output_validation.to_csv(
        output_path / "output_contract_issues.csv",
        index=False,
    )

    warehouse = PaymentsWarehouse(output_path / "payments_statistics.sqlite")
    warehouse.initialise()
    warehouse.load_dimensions(bundle)
    warehouse.load_fact(artifacts.cleaned_payments)
    warehouse_controls = warehouse.run_controls()
    warehouse_controls.to_csv(
        output_path / "warehouse_controls.csv",
        index=False,
    )

    manifest = build_manifest(
        artifacts.cleaned_payments,
        dataset="cleaned_payments",
        period_column="quarter",
        seed=seed,
        profile=profile,
    )
    manifest.to_json(output_path / "production_manifest.json")
    return OperationalRun(
        bundle=bundle,
        artifacts=artifacts,
        source_validation=source_validation,
        output_validation=output_validation,
        revision_summary=revision_summary,
        warehouse_controls=warehouse_controls,
        manifest=manifest,
    )


def export_contracts(path: str | Path) -> Path:
    """Write the contractual data dictionary used by the production system."""

    rows: list[dict[str, Any]] = []
    for contract in CONTRACTS.values():
        for field_spec in contract.fields:
            rows.append(
                {
                    "table": contract.name,
                    "grain": contract.grain,
                    "primary_key": "|".join(contract.primary_key),
                    "owner": contract.owner,
                    "frequency": contract.frequency,
                    "confidentiality": contract.confidentiality,
                    **asdict(field_spec),
                }
            )
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(destination, index=False)
    return destination


def payments_acceptance_checks(run: OperationalRun) -> pd.DataFrame:
    """Project-local release checks with no dependency on another case study."""

    artifacts = run.artifacts
    grain = [
        "psp_id",
        "country_final",
        "quarter",
        "instrument",
        "channel",
    ]
    rows = [
        {
            "check": "cleaned_cells_nonempty",
            "status": len(artifacts.cleaned_payments) > 0,
            "observed": len(artifacts.cleaned_payments),
            "expected": "> 0",
        },
        {
            "check": "production_grain_unique",
            "status": not artifacts.cleaned_payments.duplicated(grain).any(),
            "observed": int(
                artifacts.cleaned_payments.duplicated(grain).sum()
            ),
            "expected": "0",
        },
        {
            "check": "warehouse_controls",
            "status": (run.warehouse_controls["status"] == "pass").all(),
            "observed": int(
                (run.warehouse_controls["status"] != "pass").sum()
            ),
            "expected": "0 failures",
        },
        {
            "check": "source_contract_available",
            "status": isinstance(run.source_validation, pd.DataFrame),
            "observed": len(run.source_validation),
            "expected": "validation table produced",
        },
        {
            "check": "output_contract_available",
            "status": isinstance(run.output_validation, pd.DataFrame),
            "observed": len(run.output_validation),
            "expected": "validation table produced",
        },
        {
            "check": "revision_diagnostics_nonempty",
            "status": len(run.revision_summary) > 0,
            "observed": len(run.revision_summary),
            "expected": "> 0",
        },
        {
            "check": "sha256_manifest",
            "status": len(run.manifest.checksum) == 64,
            "observed": len(run.manifest.checksum),
            "expected": "64 characters",
        },
    ]
    checks = pd.DataFrame(rows)
    checks["status"] = np.where(checks["status"], "pass", "fail")
    return checks


def write_project_summary(
    run: OperationalRun,
    checks: pd.DataFrame,
    root: str | Path,
) -> Path:
    """Write a concise standalone summary for the payments project."""

    output = ensure_dir(Path(root) / "outputs")
    failed = int((checks["status"] != "pass").sum())
    lines = [
        "# Payments Statistics Production Report",
        "",
        "**Author: Jose Camas Garrdiow**",
        "",
        "All values in this report are generated synthetic observations. "
        "They are not ECB or national central-bank statistics.",
        "",
        "## Production scale",
        "",
        f"- Cleaned reporting cells: {len(run.artifacts.cleaned_payments):,}",
        f"- Country-quarter rows: {len(run.artifacts.country_quarter):,}",
        f"- Instrument-quarter rows: {len(run.artifacts.instrument_quarter):,}",
        f"- Analyst review issues: {len(run.artifacts.review_pack):,}",
        f"- Failed acceptance checks: {failed}",
        "",
        "## Main production controls",
        "",
        "```text",
        checks.to_string(index=False),
        "```",
        "",
        "## Interpretation",
        "",
        "The project demonstrates statistical production, validation, revision "
        "analysis, migration testing and SQL delivery. Synthetic values should "
        "not be interpreted as empirical findings.",
    ]
    destination = output / "project_report.md"
    text = "\n".join(lines) + "\n"
    destination.write_text(text, encoding="utf-8")
    return destination


def _parse_arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run the synthetic payments-statistics production system."
    )
    parser.add_argument(
        "command",
        choices=["produce", "contracts", "all"],
        nargs="?",
        default="all",
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Repository root in which data and outputs are created.",
    )
    parser.add_argument(
        "--profile",
        choices=["ci", "demo", "full"],
        default="ci",
    )
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument(
        "--persist-raw",
        action="store_true",
        help="Write generated source extracts under data/raw.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_arguments(argv)
    root = Path(arguments.root).resolve()
    if arguments.command in {"contracts", "all"}:
        export_contracts(root / "outputs" / "data_contracts.csv")
    if arguments.command in {"produce", "all"}:
        run = execute_operational_run(
            root,
            seed=arguments.seed,
            profile=arguments.profile,
            persist_raw=arguments.persist_raw,
        )
        failing_warehouse_checks = int(
            (run.warehouse_controls["status"] != "pass").sum()
        )
        checks = payments_acceptance_checks(run)
        checks.to_csv(root / "outputs" / "acceptance_checks.csv", index=False)
        write_project_summary(run, checks, root)
        failures = int((checks["status"] != "pass").sum())
        print(
            json.dumps(
                {
                    "profile": arguments.profile,
                    "cleaned_rows": len(run.artifacts.cleaned_payments),
                    "country_quarters": len(run.artifacts.country_quarter),
                    "warehouse_failures": failing_warehouse_checks,
                    "acceptance_failures": failures,
                    "checksum": run.manifest.checksum,
                },
                indent=2,
            )
        )
        return 1 if failures else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
