"""Pitch tracking and note segmentation, the same method the app uses (McLeod pitch method), in numpy."""
import numpy as np


def midi(f):
    return 69 + 12 * np.log2(f / 440.0)


def track(x, sr, hop=0.01, w=1024, fmin=60.0, fmax=1400.0, batch=512):
    """Return (times, midi or nan, clarity, rms) for every hop.

    Frames are processed in batches: autocorrelation via FFT, then the normalized
    square difference function and the first key maximum above 0.9 of the best one.
    """
    h = max(1, int(sr * hop))
    n = max(0, (len(x) - w) // h)
    times = (np.arange(n) * h + w / 2) / sr
    out_m = np.full(n, np.nan)
    out_c = np.zeros(n)
    out_r = np.zeros(n)
    max_lag = min(w - 2, int(sr / fmin))
    min_lag = max(2, int(sr / fmax))
    for b0 in range(0, n, batch):
        idx = np.arange(b0, min(n, b0 + batch))
        frames = np.stack([x[i * h:i * h + w] for i in idx]).astype(np.float64)
        sq = frames ** 2
        rms = np.sqrt(sq.mean(axis=1))
        out_r[idx] = rms
        spec = np.fft.rfft(frames, 2 * w, axis=1)
        r = np.fft.irfft(np.abs(spec) ** 2, axis=1)[:, :max_lag + 2]
        cs = np.cumsum(sq, axis=1)
        tau = np.arange(max_lag + 2)
        total = cs[:, -1:]
        left = cs[:, w - 1 - tau]                                   # sum x_j^2, j < w - tau
        right = total - np.where(tau > 0, cs[:, np.maximum(tau - 1, 0)], 0)  # sum x_j^2, j >= tau
        m = left + right
        nsdf = np.where(m > 1e-12, 2 * r / np.maximum(m, 1e-12), 0)
        for k, i in enumerate(idx):
            if rms[k] < 0.004:
                continue
            f, c = _pick(nsdf[k], min_lag, max_lag)
            if f > 0:
                out_m[i] = midi(sr / f)
                out_c[i] = c
    return times, out_m, out_c, out_r


def _pick(d, min_lag, max_lag):
    t = 1
    while t < max_lag and d[t] > 0:
        t += 1
    peaks, best = [], 0.0
    while t < max_lag:
        while t < max_lag and d[t] <= 0:
            t += 1
        pv, pt = -1.0, -1
        while t < max_lag and d[t] > 0:
            if d[t] > pv:
                pv, pt = d[t], t
            t += 1
        if pt > 0 and t < max_lag:
            peaks.append(pt)
            best = max(best, pv)
    for p in peaks:
        if p >= min_lag and d[p] >= 0.9 * best:
            a, b, c = d[p - 1], d[p], d[p + 1]
            den = a - 2 * b + c
            sh = (a - c) / (2 * den) if den else 0.0
            return p + sh, b - 0.25 * (a - c) * sh
    return 0.0, 0.0


def notes(times, m, clarity, min_clarity=0.8, min_dur=0.1, tol=0.5):
    """Steady runs of pitch: list of dicts with start, end, midi (median)."""
    out = []
    i, n = 0, len(times)
    ok = (~np.isnan(m)) & (clarity >= min_clarity)
    while i < n:
        if not ok[i]:
            i += 1
            continue
        j = i
        run = [m[i]]
        while j + 1 < n and ok[j + 1] and abs(m[j + 1] - np.median(run[-8:])) < tol:
            j += 1
            run.append(m[j])
        if times[j] - times[i] >= min_dur:
            out.append({"start": float(times[i]), "end": float(times[j]), "midi": float(np.median(run))})
        i = j + 1
    return out
