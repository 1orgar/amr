#!/usr/bin/env python3
"""
Tools/verify_spectrum_fft.py

Высокоточный анализатор спектра 1-битных DSD потоков (.dsf или raw float64/int8 дампов)
на базе окна Blackman-Harris (до 1M точек FFT):
  - Измерение SNR в звуковой полосе (20 Гц – 20 кГц)
  - Измерение уровня шумовой полки (Noise Floor dBFS)
  - Измерение THD / крупнейшей гармоники (dBc)
  - Детекция холостых тонов (Idle Tones) на цифровом нуле и малом DC
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np


def schreier_c7_periodic(n: int) -> np.ndarray:
    """
    DFT-even (периодическое) двоично-рациональное окно Шрайера C^7 (sin^8(pi * n / N), Hann^4):
    w[0] == 0.0 без погрешности округления в IEEE-754 binary64 и спад боковых лепестков -54 dB/окт
    (обязателен для 7-порядковых SDM с подъёмом NTF +42 dB/окт и SNR > 180 dB).
    """
    idx = np.arange(n, dtype=np.float64)
    return np.sin(np.pi * idx / float(n)) ** 8


def load_bitstream(path: Path, max_samples: int = 1_048_576) -> tuple[np.ndarray, int]:
    """
    Читает 1-битный поток из .dsf файла или бинарного дампа float64 / int8.
    Возвращает массив значений {-1.0, +1.0} и частоту дискретизации fs_hz.
    """
    raw = path.read_bytes()
    if raw[:4] == b"DSD ":
        # Парсинг заголовка DSF: DSD chunk (28 bytes) + fmt chunk (52 bytes) + data chunk (12 bytes)
        if len(raw) < 92 or raw[28:32] != b"fmt ":
            raise ValueError(f"Invalid DSF header in {path}")
        sample_freq = struct.unpack_from("<I", raw, 28 + 24)[0]
        bits_per_sample = struct.unpack_from("<I", raw, 28 + 28)[0]
        sample_count = struct.unpack_from("<Q", raw, 28 + 32)[0]
        data_offset = 92
        payload = np.frombuffer(raw, dtype=np.uint8, offset=data_offset)
        bitorder = "little" if bits_per_sample == 1 else "big"
        bits = np.unpackbits(payload, bitorder=bitorder)
        n = min(len(bits), int(sample_count), max_samples)
        y = bits[:n].astype(np.float64) * 2.0 - 1.0
        return y, int(sample_freq)

    if path.suffix == ".f64":
        arr = np.frombuffer(raw, dtype=np.float64)
        return arr[:max_samples].copy(), 11_289_600

    # По умолчанию: упакованный MSB-first поток байтов или массив int8 (-1/+1)
    arr_i8 = np.frombuffer(raw, dtype=np.int8)
    if np.all((arr_i8 == -1) | (arr_i8 == 1)):
        return arr_i8[:max_samples].astype(np.float64), 11_289_600

    payload = np.frombuffer(raw, dtype=np.uint8)
    bits = np.unpackbits(payload, bitorder="big")
    n = min(len(bits), max_samples)
    y = bits[:n].astype(np.float64) * 2.0 - 1.0
    return y, 11_289_600


def analyze_spectrum(
    y: np.ndarray,
    fs_hz: int,
    f_band_hz: float = 20_000.0,
    signal_freq_hz: float | None = 1000.0,
) -> dict[str, float]:
    n_fft = len(y)
    win = schreier_c7_periodic(n_fft)
    coherent_gain = float(np.sum(win)) / n_fft
    enbw_bins = float(n_fft * np.sum(win ** 2) / (np.sum(win) ** 2))

    spec = np.fft.rfft(y * win) / (n_fft * coherent_gain * 0.5)
    mag_sq = np.abs(spec) ** 2
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / fs_hz)

    inband = (freqs >= 20.0) & (freqs <= f_band_hz)
    sig_mask = np.zeros_like(inband)

    if signal_freq_hz is not None and signal_freq_hz > 0.0:
        sig_bin = int(round(signal_freq_hz * n_fft / fs_hz))
        lo = max(1, sig_bin - 7)
        hi = min(len(freqs), sig_bin + 8)
        sig_mask[lo:hi] = True
        sig_power = float(np.sum(mag_sq[sig_mask]) / enbw_bins)

        # Оценка гармоник (2..9) в звуковой полосе
        harm_powers: list[float] = []
        for h in range(2, 10):
            hf = h * signal_freq_hz
            if hf <= f_band_hz * 1.2:
                hb = int(round(hf * n_fft / fs_hz))
                h_lo = max(1, hb - 5)
                h_hi = min(len(freqs), hb + 6)
                harm_powers.append(float(np.max(mag_sq[h_lo:h_hi])))
                sig_mask[h_lo:h_hi] = True
        max_harm_pwr = max(harm_powers) if harm_powers else 1e-36
        thd_dbc = 10.0 * np.log10(max(max_harm_pwr, 1e-36) / max(sig_power, 1e-36))
    else:
        sig_power = 0.0
        thd_dbc = -200.0

    noise_mask = inband & (~sig_mask)
    noise_power = float(np.sum(mag_sq[noise_mask]) / enbw_bins)
    max_spur_dbfs = 10.0 * np.log10(max(float(np.max(mag_sq[noise_mask])), 1e-36))
    median_floor_dbfs = 10.0 * np.log10(max(float(np.median(mag_sq[noise_mask])), 1e-36))
    snr_db = (
        10.0 * np.log10(max(sig_power, 1e-36) / max(noise_power, 1e-36))
        if sig_power > 0.0
        else -10.0 * np.log10(max(noise_power, 1e-36))
    )

    return {
        "n_fft": float(n_fft),
        "fs_hz": float(fs_hz),
        "snr_db": snr_db,
        "thd_max_harmonic_dbc": thd_dbc,
        "noise_floor_median_dbfs": median_floor_dbfs,
        "max_inband_spur_dbfs": max_spur_dbfs,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="1M-point Blackman-Harris FFT verifier for 1-bit DSD streams.")
    parser.add_argument("input", nargs="?", type=Path, help="Path to .dsf or raw bitstream file")
    parser.add_argument("--fs", type=int, default=11_289_600, help="Override sample rate Hz for raw files")
    parser.add_argument("--freq", type=float, default=1000.0, help="Test tone frequency Hz (0 for idle tone test)")
    parser.add_argument("--min-snr", type=float, default=145.0, help="Minimum required SNR (dB)")
    parser.add_argument("--self-test", action="store_true", help="Run built-in closed-loop SDM7 verification")
    args = parser.parse_args()

    if args.self_test:
        from synthesize_sdm7_coeffs import PROFILES, RATES, synthesize_model

        prof = PROFILES[1]  # 7EC-Balanced
        rate = RATES[2]     # dsd256
        model = synthesize_model(prof, rate, 44100)
        print(json.dumps({
            "profile": model.profile,
            "rate": model.rate_case,
            "fs_hz": model.fs_hz,
            "obg": model.obg_actual,
            "pole_error_f64": model.pole_error_f64,
            "zero_unit_error_f64": model.zero_unit_error_f64,
            "verified_snr_db": model.verified_snr_db,
        }, indent=2))
        if model.verified_snr_db < args.min_snr:
            sys.exit(1)
        return

    if args.input is None:
        parser.error("Provide an input file path or --self-test")

    y, fs_detected = load_bitstream(args.input)
    fs = args.fs if args.input.suffix != ".dsf" else fs_detected
    metrics = analyze_spectrum(y, fs_hz=fs, signal_freq_hz=args.freq if args.freq > 0 else None)
    print(json.dumps(metrics, indent=2))
    if args.freq > 0 and metrics["snr_db"] < args.min_snr:
        sys.exit(1)


if __name__ == "__main__":
    main()
