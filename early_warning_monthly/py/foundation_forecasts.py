"""
Zero-shot-Prognosen mit Zeitreihen-Foundation-Modellen für das Frühwarnsystem.

Modelle (alle vortrainiert, KEIN Training auf unseren Daten = "zero-shot"):
  * TimesFM 3.0   (Google Research)   google/timesfm-3.0-pytorch
  * Chronos-2     (Amazon)            amazon/chronos-2
  * Moirai-2      (Salesforce)        Salesforce/moirai-2.0-R-small

Eingabe  (von R geschrieben): data/processed/fm_series.csv
         Spalten: target, iso3c, month (YYYY-MM-01), value, threshold_delta
         - conflict: value = log1p(Tote der letzten 3 Monate); Krise wenn value(t+3) >= log1p(25)
         - fx:       value = log(Wechselkurs);   Krise wenn value(t+3) - value(t) >= log(1.15)
Ausgabe: data/processed/fm_forecasts.csv
         Spalten: model, target, iso3c, month (= Prognoseursprung t), p (Krisenwahrscheinlichkeit), median

Für jeden Ursprungsmonat t wird nur die Reihe bis einschliesslich t verwendet (keine Zukunftsinformation).
Die Wahrscheinlichkeit P(Wert(t+3) über Schwelle) wird aus den vorhergesagten Quantilen interpoliert.

Aufruf:  python py/foundation_forecasts.py [--models timesfm3,chronos2,moirai2] [--start 2018-01-01]
"""
from __future__ import annotations

import argparse
import os
import sys
import time

import numpy as np
import pandas as pd

HORIZON = 3
MAX_CONTEXT = 192  # Monate
BATCH = 256


def exceed_prob(q_levels: np.ndarray, q_values: np.ndarray, thr: np.ndarray) -> np.ndarray:
    """P(X >= thr) aus Quantilen (pro Zeile).

    Innerhalb der vorhergesagten Quantile: lineare Interpolation der Verteilungsfunktion.
    Ausserhalb: exponentiell abfallende Ränder, skaliert mit der Streuung der Prognose. So bleibt
    auch weit jenseits der Quantile eine feine Rangordnung erhalten (statt fester 5 % / 95 %).
    """
    q_values = np.sort(q_values, axis=1)
    l_lo, l_hi = q_levels[0], q_levels[-1]
    out = np.empty(len(thr))
    for i in range(len(thr)):
        v = q_values[i]
        med = np.interp(0.5, q_levels, v)
        s_hi = max(v[-1] - med, 0.05)                 # Skala des oberen Randes
        s_lo = max(med - v[0], 0.05)
        if thr[i] > v[-1]:
            out[i] = (1 - l_hi) * np.exp(-(thr[i] - v[-1]) / s_hi)
        elif thr[i] < v[0]:
            out[i] = 1 - l_lo * np.exp(-(v[0] - thr[i]) / s_lo)
        else:
            out[i] = 1 - np.interp(thr[i], v, q_levels)
    return np.clip(out, 1e-5, 1 - 1e-5)


# ---------------------------------------------------------------- Modell-Adapter
class TimesFM3:
    name = "timesfm3"

    def __init__(self):
        from timesfm3 import TimesFM3Forecaster
        self.m = TimesFM3Forecaster.from_pretrained("google/timesfm-3.0-pytorch", device="cpu")

    def quantiles(self, contexts):
        outs = list(self.m.predict_batch(contexts=contexts, horizon=HORIZON, return_quantiles=True))
        q = np.stack([o.quantiles for o in outs])          # (n, horizon, n_q) - Spalte 0 = Mittelwert
        q = q.reshape(len(outs), HORIZON, -1)
        q = q[:, -1, 1:] if q.shape[-1] == 10 else q[:, -1, :]
        levels = np.linspace(0.1, 0.9, q.shape[1])
        return levels, q


class Chronos2:
    name = "chronos2"

    def __init__(self):
        import torch
        from chronos import Chronos2Pipeline
        self.torch = torch
        self.m = Chronos2Pipeline.from_pretrained("amazon/chronos-2", device_map="cpu")
        self.levels = [0.01, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99]

    def quantiles(self, contexts):
        inputs = [self.torch.tensor(c, dtype=self.torch.float32).reshape(1, -1) for c in contexts]
        q, _ = self.m.predict_quantiles(inputs, prediction_length=HORIZON, quantile_levels=self.levels,
                                        batch_size=BATCH)
        q = np.stack([x[0, -1, :].numpy() for x in q])    # letzte Horizontstufe (t+3)
        return np.array(self.levels), q


class Moirai2:
    name = "moirai2"

    def __init__(self):
        import torch
        from uni2ts.model.moirai2 import Moirai2Forecast, Moirai2Module
        self.torch = torch
        module = Moirai2Module.from_pretrained("Salesforce/moirai-2.0-R-small")
        self.m = Moirai2Forecast(module=module, prediction_length=HORIZON, context_length=MAX_CONTEXT,
                                 target_dim=1, feat_dynamic_real_dim=0, past_feat_dynamic_real_dim=0)
        self.m.eval()
        self.levels = np.array(module.quantile_levels)

    def quantiles(self, contexts):
        n = len(contexts)
        x = np.zeros((n, MAX_CONTEXT, 1), dtype=np.float32)
        obs = np.zeros((n, MAX_CONTEXT, 1), dtype=bool)
        pad = np.ones((n, MAX_CONTEXT), dtype=bool)
        for i, c in enumerate(contexts):
            c = c[-MAX_CONTEXT:]
            x[i, -len(c):, 0] = np.nan_to_num(c)
            obs[i, -len(c):, 0] = ~np.isnan(c)
            pad[i, -len(c):] = False
        t = self.torch
        with t.no_grad():
            q = self.m(past_target=t.tensor(x), past_observed_target=t.tensor(obs), past_is_pad=t.tensor(pad))
        q = q.numpy()                                       # (n, n_q, horizon[, 1])
        q = q.reshape(n, len(self.levels), HORIZON)[:, :, -1]
        return self.levels, q


MODELS = {"timesfm3": TimesFM3, "chronos2": Chronos2, "moirai2": Moirai2}


# ---------------------------------------------------------------- Hauptprogramm
def build_jobs(series: pd.DataFrame, start: pd.Timestamp):
    """Alle (Ziel, Land, Ursprungsmonat)-Kontexte mit der Reihe bis einschliesslich t."""
    jobs = []
    for (target, iso), g in series.groupby(["target", "iso3c"], sort=False):
        g = g.sort_values("month")
        vals = g["value"].to_numpy(dtype=np.float64)
        months = g["month"].to_numpy()
        for k in np.where(months >= np.datetime64(start))[0]:
            if np.isnan(vals[k]):
                continue
            ctx = vals[max(0, k + 1 - MAX_CONTEXT): k + 1]
            if np.sum(~np.isnan(ctx)) < 24:
                continue
            thr = g["threshold"].iloc[k] if target == "conflict" else vals[k] + g["threshold"].iloc[k]
            jobs.append((target, iso, months[k], ctx, thr, vals[k]))
    return jobs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="timesfm3,chronos2,moirai2")
    ap.add_argument("--start", default="2018-01-01")
    ap.add_argument("--input", default="data/processed/fm_series.csv")
    ap.add_argument("--output", default="data/processed/fm_forecasts.csv")
    a = ap.parse_args()

    series = pd.read_csv(a.input, parse_dates=["month"])
    jobs = build_jobs(series, pd.Timestamp(a.start))
    print(f"[FM] {len(jobs)} Prognosen pro Modell (Ursprung ab {a.start}, Horizont {HORIZON} Monate)", flush=True)

    results = []
    for name in a.models.split(","):
        t0 = time.time()
        try:
            model = MODELS[name]()
        except Exception as e:  # Modell nicht verfügbar -> überspringen, Pipeline läuft weiter
            print(f"[FM] {name}: konnte nicht geladen werden ({type(e).__name__}: {e})", flush=True)
            continue
        ps, meds = [], []
        for b in range(0, len(jobs), BATCH):
            chunk = jobs[b:b + BATCH]
            levels, q = model.quantiles([j[3].astype(np.float32) for j in chunk])
            thr = np.array([j[4] for j in chunk])
            ps.append(exceed_prob(levels, q, thr))
            meds.append(q[:, np.argmin(np.abs(levels - 0.5))])
        p, med = np.concatenate(ps), np.concatenate(meds)
        results.append(pd.DataFrame({
            "model": name, "target": [j[0] for j in jobs], "iso3c": [j[1] for j in jobs],
            "month": [pd.Timestamp(j[2]).strftime("%Y-%m-%d") for j in jobs], "p": p, "median": med}))
        print(f"[FM] {name}: fertig in {time.time() - t0:.0f}s", flush=True)

    if not results:
        sys.exit("[FM] Kein Foundation-Modell lief erfolgreich.")
    out = pd.concat(results)
    os.makedirs(os.path.dirname(a.output), exist_ok=True)
    out.to_csv(a.output, index=False)
    print(f"[FM] geschrieben: {a.output} ({len(out)} Zeilen)", flush=True)


if __name__ == "__main__":
    main()
