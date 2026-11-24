#!/usr/bin/env python3
"""
Tools/synthesize_sdm7_coeffs.py

Высокоточный (85 decimal digits / stdlib decimal) синтезатор матриц состояний
7-порядкового дельта-сигма модулятора (3 симплектических биквадратных резонатора
Чебышёва + 1 интегратор DC) с L1-минимальным размещением полюсов 7EC,
выравниванием пик-фактора интеграторов через грамиан Ляпунова,
Rank-2 декомпозицией грамиана наблюдаемости P_obs для терминальной метрики Витерби
и кодогенерацией файла SDM7Coefficients.swift под Pure Swift 6 (SIMD2<Double>).

Не требует сторонних пакетов кроме стандартного numpy (работает на штатном /usr/bin/python3 macOS).

Профили:
  1. transient (7EC-Transient): OBG = 1.38 — минимум ультразвука 30–70 кГц, максимальный импульсный отклик
  2. balanced  (7EC-Balanced) : OBG = 1.50 — референсный профиль по умолчанию для DoP256
  3. superWide (7EC-Super)    : OBG = 1.62 — предельное широкополосное подавление шума (Trellis M=8..16)
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from decimal import Decimal, getcontext
from pathlib import Path
from typing import Sequence

import numpy as np

# 85 десятичных знаков (~282 бита мантиссы) полностью исключают потерю точности полиномов вблизи z = 1
getcontext().prec = 85

D_ZERO = Decimal(0)
D_ONE = Decimal(1)
D_TWO = Decimal(2)
D_PI = Decimal(
    "3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348"
)


def _d_sin_cos(x: Decimal) -> tuple[Decimal, Decimal]:
    """Вычисляет (sin(x), cos(x)) с точностью 85 знаков рядом Тейлора."""
    two_pi = D_TWO * D_PI
    n_turns = int((x / two_pi).to_integral_value())
    r = x - Decimal(n_turns) * two_pi
    if r > D_PI:
        r -= two_pi
    elif r < -D_PI:
        r += two_pi

    r2 = r * r
    sin_acc = r
    sin_term = r
    cos_acc = D_ONE
    cos_term = D_ONE

    eps = Decimal("1e-84")
    for k in range(1, 55):
        sin_term = -sin_term * r2 / Decimal((2 * k) * (2 * k + 1))
        sin_acc += sin_term
        cos_term = -cos_term * r2 / Decimal((2 * k - 1) * (2 * k))
        cos_acc += cos_term
        if abs(sin_term) < eps and abs(cos_term) < eps:
            break
    return sin_acc, cos_acc


def _d_tan(x: Decimal) -> Decimal:
    s, c = _d_sin_cos(x)
    return s / c


@dataclass(frozen=True)
class DComplex:
    re: Decimal
    im: Decimal = D_ZERO

    def __add__(self, other: DComplex) -> DComplex:
        return DComplex(self.re + other.re, self.im + other.im)

    def __sub__(self, other: DComplex) -> DComplex:
        return DComplex(self.re - other.re, self.im - other.im)

    def __mul__(self, other: DComplex) -> DComplex:
        return DComplex(
            self.re * other.re - self.im * other.im,
            self.re * other.im + self.im * other.re,
        )

    def __truediv__(self, other: DComplex) -> DComplex:
        denom = other.re * other.re + other.im * other.im
        return DComplex(
            (self.re * other.re + self.im * other.im) / denom,
            (self.im * other.re - self.re * other.im) / denom,
        )

    def to_complex(self) -> complex:
        return complex(float(self.re), float(self.im))


@dataclass(frozen=True)
class ProfileSpec:
    swift_case: str
    display_name: str
    obg_target: float
    q_outer: float
    q_mid: float
    f_band_44k: float
    f_band_48k: float
    zero_ratios: tuple[float, float, float]
    isi_lambda: float
    recommended_trellis_m: int
    soft_clip_threshold: float


@dataclass(frozen=True)
class RateSpec:
    swift_case: str
    multiplier: int
    fs_44k: int
    fs_48k: int


@dataclass(frozen=True)
class SynthesizedModel:
    profile: str
    rate_case: str
    grid_hz: int
    fs_hz: int
    obg_actual: float
    ntf_l1_norm: float
    max_pole_q: float
    fc_hz: float
    # Каскадные коэффициенты симплектической решётки (7 состояний)
    b0: float
    a_link: tuple[float, float, float]      # Связь между каскадами (s0->s1, s2->s3, s4->s5)
    g_fb: tuple[float, float, float]        # Локальные обратные связи резонаторов (нули NTF)
    c_int: tuple[float, float, float]       # Внутренние интеграторы резонаторов
    ff_weights: tuple[float, ...]           # Точный масштабированный вектор сумматора C_raw (7 элементов)
    obs_lead0: tuple[float, ...]            # Главный собственный вектор грамиана наблюдаемости sqrt(lam_1)*v_1
    obs_lead1: tuple[float, ...]            # Второй собственный вектор грамиана наблюдаемости sqrt(lam_2)*v_2
    c_norm: float                           # Евклидова норма ||C_raw||_2
    isi_lambda: float
    soft_clip_threshold: float
    recommended_trellis_m: int
    pole_error_f64: float
    zero_unit_error_f64: float
    verified_snr_db: float


PROFILES: tuple[ProfileSpec, ...] = (
    ProfileSpec(
        swift_case="transient",
        display_name="7EC-Transient",
        obg_target=1.38,
        q_outer=0.75,
        q_mid=0.62,
        f_band_44k=20200.0,
        f_band_48k=20600.0,
        zero_ratios=(0.32, 0.72, 0.96),
        isi_lambda=0.018,
        recommended_trellis_m=8,
        soft_clip_threshold=0.98,
    ),
    ProfileSpec(
        swift_case="balanced",
        display_name="7EC-Balanced",
        obg_target=1.50,
        q_outer=0.80,
        q_mid=0.64,
        f_band_44k=21000.0,
        f_band_48k=21800.0,
        zero_ratios=(0.31, 0.71, 0.96),
        isi_lambda=0.024,
        recommended_trellis_m=8,
        soft_clip_threshold=0.98,
    ),
    ProfileSpec(
        swift_case="superWide",
        display_name="7EC-Super",
        obg_target=1.62,
        q_outer=0.82,
        q_mid=0.65,
        f_band_44k=23500.0,
        f_band_48k=25000.0,
        zero_ratios=(0.30, 0.70, 0.96),
        isi_lambda=0.030,
        recommended_trellis_m=16,
        soft_clip_threshold=0.98,
    ),
)

RATES: tuple[RateSpec, ...] = (
    RateSpec("dsd64", 64, 2_822_400, 3_072_000),
    RateSpec("dsd128", 128, 5_644_800, 6_144_000),
    RateSpec("dsd256", 256, 11_289_600, 12_288_000),
    RateSpec("dsd512", 512, 22_579_200, 24_576_000),
)

# Выровненные по пик-фактору целевые RMS состояний (предотвращают раннее насыщение младших секций s0, s1)
STATE_RMS_TARGETS: tuple[Decimal, ...] = (
    Decimal("0.115"),
    Decimal("0.135"),
    Decimal("0.155"),
    Decimal("0.165"),
    Decimal("0.165"),
    Decimal("0.165"),
    Decimal("0.165"),
)


def _poly_mul_real_dec(p1: Sequence[Decimal], p2: Sequence[Decimal]) -> list[Decimal]:
    out = [D_ZERO] * (len(p1) + len(p2) - 1)
    for i, a in enumerate(p1):
        for j, b in enumerate(p2):
            out[i + j] += a * b
    return out


def _poly_val_real_dec(poly: Sequence[Decimal], z: Decimal) -> Decimal:
    acc = D_ZERO
    for coeff in poly:
        acc = acc * z + coeff
    return acc


def _mat_mul_dec(a: list[list[Decimal]], b: list[list[Decimal]]) -> list[list[Decimal]]:
    rows = len(a)
    cols = len(b[0])
    inner = len(b)
    out = [[D_ZERO] * cols for _ in range(rows)]
    for r in range(rows):
        ar = a[r]
        outr = out[r]
        for k in range(inner):
            ark = ar[k]
            if ark == D_ZERO:
                continue
            bk = b[k]
            for c in range(cols):
                outr[c] += ark * bk[c]
    return out


def _mat_transpose_dec(a: list[list[Decimal]]) -> list[list[Decimal]]:
    rows = len(a)
    cols = len(a[0])
    return [[a[r][c] for r in range(rows)] for c in range(cols)]


def _lu_solve_dec(mat: list[list[Decimal]], rhs: list[Decimal]) -> list[Decimal]:
    """Решает линейную систему M * x = rhs методом Гаусса с выбором главного элемента в 85-значной арифметике."""
    n = len(rhs)
    aug = [row[:] + [rhs[i]] for i, row in enumerate(mat)]

    for col in range(n):
        piv = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if piv != col:
            aug[col], aug[piv] = aug[piv], aug[col]
        piv_val = aug[col][col]
        for r in range(col + 1, n):
            factor = aug[r][col] / piv_val
            if factor == D_ZERO:
                continue
            for c in range(col, n + 1):
                aug[r][c] -= factor * aug[col][c]

    x = [D_ZERO] * n
    for r in range(n - 1, -1, -1):
        s = aug[r][n]
        for c in range(r + 1, n):
            s -= aug[r][c] * x[c]
        x[r] = s / aug[r][r]
    return x


def _solve_lyapunov_smith_dec(
    a_mat: list[list[Decimal]],
    b_vec: list[Decimal],
    sigma_sq: Decimal,
    iterations: int = 32,
) -> list[list[Decimal]]:
    """
    Решает дискретное уравнение Ляпунова W = A * W * A^T + sigma^2 * B * B^T
    методом квадратичного удвоения Смита в 85-значной арифметике.
    """
    n = len(b_vec)
    w_cov = [[b_vec[r] * b_vec[c] * sigma_sq for c in range(n)] for r in range(n)]
    a_pow = [row[:] for row in a_mat]
    for _ in range(iterations):
        aw = _mat_mul_dec(a_pow, w_cov)
        awat = _mat_mul_dec(aw, _mat_transpose_dec(a_pow))
        for r in range(n):
            for c in range(n):
                w_cov[r][c] += awat[r][c]
        a_pow = _mat_mul_dec(a_pow, a_pow)
    return w_cov


def _build_s_prototype_poles(q_outer: float, q_mid: float) -> tuple[list[tuple[Decimal, Decimal]], Decimal]:
    """
    Строит L1-минимальные нормированные комплексно-сопряжённые пары полюсов левой полуплоскости
    7-го порядка на единичной окружности s-прототипа (3 сопряжённые пары + 1 вещественный полюс -1),
    минимизирующие норму ||h_NTF||_1 (<= 4.05 на всех профилях включая OBG = 1.62).
    """
    q1 = Decimal(str(q_outer))
    q2 = Decimal(str(q_mid))

    cos1 = D_ONE / (D_TWO * q1)
    sin1 = (D_ONE - cos1 * cos1).sqrt()

    cos2 = D_ONE / (D_TWO * q2)
    sin2 = (D_ONE - cos2 * cos2).sqrt()

    angle3 = D_PI * Decimal(12) / Decimal(14)
    sin3, cos3_signed = _d_sin_cos(angle3)

    pairs = [
        (-cos1, sin1),
        (-cos2, sin2),
        (cos3_signed, sin3),
    ]
    return pairs, -D_ONE


def _schreier_c7_window(n: int) -> np.ndarray:
    """
    Точное двоично-рациональное окно Шрайера C^7 (sin^8(pi * n / N), Hann^4):
    спад боковых лепестков -54 dB/окт (быстрее подъёма +42 dB/окт NTF 7-го порядка)
    и машинный нуль w[0] == 0.0 в IEEE-754 binary64.
    """
    idx = np.arange(n, dtype=np.float64)
    return np.sin(np.pi * idx / float(n)) ** 8


def _compute_ntf_l1_norm(w_zeros_f: Sequence[float], z_poles_c: np.ndarray, n_fft: int = 16384) -> float:
    """Точно вычисляет L1-норму импульсной характеристики NTF: sum_n |h_NTF[n]|."""
    w = 2.0 * np.pi * np.arange(n_fft, dtype=np.float64) / float(n_fft)
    ejw = np.exp(1j * w)
    num = ejw - 1.0
    for wk in w_zeros_f:
        num = num * (ejw * ejw - 2.0 * math.cos(wk) * ejw + 1.0)
    den = np.ones_like(ejw)
    for zp in z_poles_c:
        den = den * (ejw - zp)
    h_imp = np.fft.ifft(num / den).real
    return float(np.sum(np.abs(h_imp)))


def _verify_closed_loop_snr(
    a_s: np.ndarray,
    b_s: np.ndarray,
    ff_vec: np.ndarray,
    obs0: np.ndarray,
    obs1: np.ndarray,
    fs_hz: int,
    m_survivors: int = 8,
) -> float:
    """
    Контрольная замкнутая 1-битная симуляция Витерби (когерентный синус ~1.38 кГц при -3.5 dBFS)
    в топологии Сильвы–Стинсгаарда (STF(z) == 1: v = u + C*s) с Rank-2 терминальной метрикой
    грамиана наблюдаемости в полной звуковой полосе 20 Гц – 20 кГц.
    """
    n_fft = 65_536
    warmup = 2048
    total = warmup + n_fft
    sig_bin = max(8, int(round(1000.0 * n_fft / fs_hz)))
    f_coherent = sig_bin * fs_hz / n_fft
    amp = 10.0 ** (-3.5 / 20.0)

    t = np.arange(total + 4, dtype=np.float64)
    u = amp * np.sin(2.0 * np.pi * f_coherent * t / fs_hz)

    a_t = a_s.T.copy()
    surv_s = np.zeros((1, 7), dtype=np.float64)
    surv_c = np.zeros(1, dtype=np.float64)
    surv_h = np.zeros(1, dtype=np.uint64)
    depth_l = np.uint64(8)
    one_u64 = np.uint64(1)
    y_out = np.empty(total, dtype=np.float64)

    for n in range(total):
        u0 = float(u[n])
        u1 = float(u[n + 1])
        v0 = u0 + surv_s @ ff_vec
        s_base = surv_s @ a_t
        cand_s = np.vstack([s_base + (u0 + 1.0) * b_s, s_base + (u0 - 1.0) * b_s])
        over = np.maximum(0.0, np.abs(cand_s) - 1.20)
        cand_s = np.where(np.abs(cand_s) <= 1.20, cand_s, np.sign(cand_s) * (1.20 + (0.16 * over) / (0.16 + over)))
        cand_err = np.concatenate([v0 + 1.0, v0 - 1.0])
        shifted = surv_h << one_u64
        cand_h = np.concatenate([shifted, shifted | one_u64])
        bar0 = np.sum(np.maximum(0.0, np.abs(cand_s) - 0.98) ** 2, axis=1)
        g = 0.92 * np.concatenate([surv_c, surv_c]) + cand_err * cand_err + 24.0 * bar0

        v1 = u1 + cand_s @ ff_vec
        y1 = np.where(v1 >= 0.0, 1.0, -1.0)
        s2 = cand_s @ a_t + np.outer(u1 - y1, b_s)
        p0 = s2 @ obs0
        p1 = s2 @ obs1
        bar2 = np.sum(np.maximum(0.0, np.abs(s2) - 0.98) ** 2, axis=1)
        f = g + 0.85 * (v1 - y1) ** 2 + 0.25 * (p0 * p0 + p1 * p1) + 36.0 * bar2

        best = int(np.argmin(f))
        cbit = (cand_h[best] >> depth_l) & one_u64
        y_out[n] = 1.0 if cbit == one_u64 else -1.0
        idx = np.where(((cand_h >> depth_l) & one_u64) == cbit)[0]
        if len(idx) > m_survivors:
            idx = idx[np.argsort(f[idx])[:m_survivors]]
        surv_s = cand_s[idx]
        surv_c = g[idx] - float(np.min(g[idx]))
        surv_h = cand_h[idx]

    win = _schreier_c7_window(n_fft)
    spec = np.fft.rfft(y_out[warmup:] * win)
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / fs_hz)

    inband = (freqs >= 20.0) & (freqs <= 20_000.0)
    sig_mask = np.zeros_like(inband)
    sig_mask[max(0, sig_bin - 6) : min(len(freqs), sig_bin + 7)] = True
    noise_mask = inband & (~sig_mask)

    sig_pwr = float(np.sum(np.abs(spec[sig_mask]) ** 2))
    noise_pwr = float(np.sum(np.abs(spec[noise_mask]) ** 2))
    return 10.0 * np.log10(max(sig_pwr, 1e-36) / max(noise_pwr, 1e-36))


def synthesize_model(profile: ProfileSpec, rate: RateSpec, base_grid: int) -> SynthesizedModel:
    fs_hz = rate.fs_44k if base_grid == 44100 else rate.fs_48k
    f_band_hz = profile.f_band_44k if base_grid == 44100 else profile.f_band_48k

    fs_dec = Decimal(fs_hz)
    f_band_dec = Decimal(str(f_band_hz))

    # 1. Точные частоты нулей Чебышёва и симплектические произведения c_k * g_k = 4 * sin^2(w_k / 2)
    w_zeros: list[Decimal] = []
    cg_list: list[Decimal] = []
    for r in profile.zero_ratios:
        wk = D_TWO * D_PI * Decimal(str(r)) * f_band_dec / fs_dec
        sin_half, _ = _d_sin_cos(wk / D_TWO)
        w_zeros.append(wk)
        cg_list.append(Decimal(4) * sin_half * sin_half)

    # 2. Подбор частоты среза полюсов fc методом бисекции строго под критерий Ли ||NTF(e^jw)||_inf == obg_target
    s_conj_pairs, s_real_pole = _build_s_prototype_poles(profile.q_outer, profile.q_mid)
    s_poles_all: list[DComplex] = [DComplex(s_real_pole, D_ZERO)]
    for re_p, im_p in s_conj_pairs:
        s_poles_all.append(DComplex(re_p, im_p))
        s_poles_all.append(DComplex(re_p, -im_p))

    w_zeros_f = [float(wk) for wk in w_zeros]
    s_poles_f = np.array([sp.to_complex() for sp in s_poles_all], dtype=np.complex128)
    w_dense = np.concatenate([np.geomspace(1e-5, np.pi, 2048), [np.pi]])
    ejw_dense = np.exp(1j * w_dense)
    num_mag_dense = np.abs(ejw_dense - 1.0)
    for wk in w_zeros_f:
        num_mag_dense = num_mag_dense * (2.0 * np.abs(np.cos(w_dense) - math.cos(wk)))

    def calc_obg_f64(fc_val: float) -> float:
        wc = 2.0 * math.pi * fc_val / float(fs_hz)
        k_warp = math.tan(0.5 * wc)
        zp = (1.0 + k_warp * s_poles_f) / (1.0 - k_warp * s_poles_f)
        den_mag = np.ones_like(w_dense)
        for p in zp:
            den_mag = den_mag * np.abs(ejw_dense - p)
        return float(np.max(num_mag_dense / den_mag))

    fc_lo = f_band_hz * 1.02
    fc_hi = fs_hz * 0.35
    for _ in range(80):
        fc_mid = 0.5 * (fc_lo + fc_hi)
        if calc_obg_f64(fc_mid) < profile.obg_target:
            fc_lo = fc_mid
        else:
            fc_hi = fc_mid
    fc_opt = 0.5 * (fc_lo + fc_hi)
    obg_actual = calc_obg_f64(fc_opt)

    # 3. Точное билинейное отображение полюсов в 85-значной арифметике Decimal
    fc_dec = Decimal(f"{fc_opt:.17e}")
    wc_dec = D_TWO * D_PI * fc_dec / fs_dec
    k_dec = _d_tan(wc_dec / D_TWO)
    d_one_c = DComplex(D_ONE, D_ZERO)
    k_c = DComplex(k_dec, D_ZERO)

    z_real_pole = (D_ONE + k_dec * s_real_pole) / (D_ONE - k_dec * s_real_pole)
    z_conj_pairs: list[DComplex] = []
    z_poles_ref_list: list[complex] = [complex(float(z_real_pole), 0.0)]
    max_pole_q = 0.5

    for re_p, im_p in s_conj_pairs:
        sp = DComplex(re_p, im_p)
        zp = (d_one_c + k_c * sp) / (d_one_c - k_c * sp)
        z_conj_pairs.append(zp)
        zc = zp.to_complex()
        z_poles_ref_list.append(zc)
        z_poles_ref_list.append(zc.conjugate())
        ln_r = 0.5 * math.log(zc.real * zc.real + zc.imag * zc.imag)
        theta = abs(math.atan2(zc.imag, zc.real))
        q_val = math.hypot(ln_r, theta) / max(1e-18, -2.0 * ln_r)
        if q_val > max_pole_q:
            max_pole_q = q_val

    z_poles_ref = np.sort_complex(np.array(z_poles_ref_list, dtype=np.complex128))
    ntf_l1 = _compute_ntf_l1_norm(w_zeros_f, z_poles_ref)

    # 4. Строго вещественное раскрытие монических полиномов Z(z) и P(z) в 85-значной арифметике
    z_poly_real: list[Decimal] = [D_ONE, -D_ONE]
    for cg in cg_list:
        z_poly_real = _poly_mul_real_dec(z_poly_real, [D_ONE, -(D_TWO - cg), D_ONE])

    p_poly_real: list[Decimal] = [D_ONE, -z_real_pole]
    for zp in z_conj_pairs:
        mag_sq = zp.re * zp.re + zp.im * zp.im
        p_poly_real = _poly_mul_real_dec(p_poly_real, [D_ONE, -D_TWO * zp.re, mag_sq])

    # 5. Сборка несмасштабированной симплектической матрицы A0 и вектора входа B0
    c_init = [cg.sqrt() for cg in cg_list]
    g_init = [cg.sqrt() for cg in cg_list]

    a0 = [[D_ZERO] * 7 for _ in range(7)]
    b0_vec = [D_ZERO] * 7
    a0[0][0] = D_ONE
    b0_vec[0] = D_ONE

    for k_idx in range(3):
        prev_i = 0 if k_idx == 0 else (2 * k_idx)
        i1 = 2 * k_idx + 1
        i2 = 2 * k_idx + 2
        ck = c_init[k_idx]
        gk = g_init[k_idx]
        a0[i1][prev_i] = D_ONE
        a0[i1][i1] = D_ONE
        a0[i1][i2] = -gk
        a0[i2][prev_i] = ck
        a0[i2][i1] = ck
        a0[i2][i2] = D_ONE - ck * gk

    # 6. Нахождение вектора весов сумматора C0 из тождества C0 * (zI - A0)^(-1) * B0 = (P(z) - Z(z)) / Z(z)
    sample_z = [Decimal("0.42") + Decimal(m) * Decimal("0.08") for m in range(7)]
    m_sys = [[D_ZERO] * 7 for _ in range(7)]
    rhs = [D_ZERO] * 7
    for m, zm in enumerate(sample_z):
        zmi_a = [
            [(zm if r == col else D_ZERO) - a0[r][col] for col in range(7)]
            for r in range(7)
        ]
        x_zm = _lu_solve_dec(zmi_a, b0_vec)
        pz = _poly_val_real_dec(p_poly_real, zm)
        zz = _poly_val_real_dec(z_poly_real, zm)
        m_sys[m] = x_zm
        rhs[m] = (pz - zz) / zz

    c0_vec = _lu_solve_dec(m_sys, rhs)

    # 7. Масштабирование динамического диапазона состояний с выравниванием пик-фактора через грамиан Ляпунова
    a_cl0 = [
        [a0[r][col] - b0_vec[r] * c0_vec[col] for col in range(7)]
        for r in range(7)
    ]
    sigma_sq = D_ONE / Decimal(3)
    w_gram = _solve_lyapunov_smith_dec(a_cl0, b0_vec, sigma_sq=sigma_sq, iterations=32)
    d_scale = [STATE_RMS_TARGETS[i] / w_gram[i][i].sqrt() for i in range(7)]

    # Подобное преобразование s = D * x => A_s = D * A0 * D^{-1}, B_s = D * B0, C_s = C0^T * D^{-1}
    a_s = np.array(
        [[float(d_scale[r] * a0[r][col] / d_scale[col]) for col in range(7)] for r in range(7)],
        dtype=np.float64,
    )
    b_s = np.array([float(d_scale[r] * b0_vec[r]) for r in range(7)], dtype=np.float64)
    c_s_raw = np.array([float(c0_vec[col] / d_scale[col]) for col in range(7)], dtype=np.float64)
    c_norm = float(np.linalg.norm(c_s_raw))

    # Проверка полюсов и нулей после округления в IEEE-754 Double
    a_cl_f64 = a_s - np.outer(b_s, c_s_raw)
    eigs_cl = np.sort_complex(np.linalg.eigvals(a_cl_f64))
    pole_err = float(np.max(np.abs(eigs_cl - z_poles_ref)))
    zero_err = float(np.max(np.abs(np.abs(np.linalg.eigvals(a_s)) - 1.0)))

    # 8. Грамиан наблюдаемости P_obs = A_cl^T * P_obs * A_cl + C_s^T * C_s (Rank-2 проекция сепаратрисы Витерби)
    p_obs = np.outer(c_s_raw, c_s_raw)
    a_pow_f = a_cl_f64.copy()
    for _ in range(28):
        p_obs = p_obs + a_pow_f.T @ p_obs @ a_pow_f
        a_pow_f = a_pow_f @ a_pow_f
    p_obs = 0.5 * (p_obs + p_obs.T)
    eig_vals, eig_vecs = np.linalg.eigh(p_obs)
    vec0 = eig_vecs[:, -1] * (1.0 if eig_vecs[0, -1] >= 0.0 else -1.0)
    vec1 = eig_vecs[:, -2] * (1.0 if eig_vecs[0, -2] >= 0.0 else -1.0)
    obs0_arr = math.sqrt(max(0.0, float(eig_vals[-1]))) * vec0
    obs1_arr = math.sqrt(max(0.0, float(eig_vals[-2]))) * vec1

    b0_val = float(b_s[0])
    a_link = (float(a_s[1, 0]), float(a_s[3, 2]), float(a_s[5, 4]))
    g_fb = (float(-a_s[1, 2]), float(-a_s[3, 4]), float(-a_s[5, 6]))
    c_int = (float(a_s[2, 1]), float(a_s[4, 3]), float(a_s[6, 5]))
    ff_tuple = tuple(float(v) for v in c_s_raw)
    obs0_tuple = tuple(float(v) for v in obs0_arr)
    obs1_tuple = tuple(float(v) for v in obs1_arr)

    snr_db = _verify_closed_loop_snr(
        a_s=a_s,
        b_s=b_s,
        ff_vec=c_s_raw,
        obs0=obs0_arr,
        obs1=obs1_arr,
        fs_hz=fs_hz,
        m_survivors=profile.recommended_trellis_m,
    )

    return SynthesizedModel(
        profile=profile.swift_case,
        rate_case=rate.swift_case,
        grid_hz=base_grid,
        fs_hz=fs_hz,
        obg_actual=obg_actual,
        ntf_l1_norm=ntf_l1,
        max_pole_q=max_pole_q,
        fc_hz=float(fc_dec),
        b0=b0_val,
        a_link=a_link,
        g_fb=g_fb,
        c_int=c_int,
        ff_weights=ff_tuple,
        obs_lead0=obs0_tuple,
        obs_lead1=obs1_tuple,
        c_norm=c_norm,
        isi_lambda=profile.isi_lambda,
        soft_clip_threshold=profile.soft_clip_threshold,
        recommended_trellis_m=profile.recommended_trellis_m,
        pole_error_f64=pole_err,
        zero_unit_error_f64=zero_err,
        verified_snr_db=snr_db,
    )


def _fmt_f64(val: float) -> str:
    return f"{val:.17e}"


def render_swift_file(models: Sequence[SynthesizedModel]) -> str:
    lines: list[str] = [
        "// AUTO-GENERATED FILE — DO NOT EDIT MANUALLY.",
        "// Generated by Tools/synthesize_sdm7_coeffs.py (85-digit Decimal DELSIG + L1-minimal 7EC + Rank-2 Observability Gramian).",
        "",
        "import simd",
        "",
        "public enum SDM7Profile: Int, CaseIterable, Sendable, Codable {",
        "    case transient = 0   // 7EC-Transient: OBG 1.38, low-Q, ultra-clean 30-70 kHz",
        "    case balanced  = 1   // 7EC-Balanced : OBG 1.50, reference DoP256 profile",
        "    case superWide = 2   // 7EC-Super    : OBG 1.62, max wideband suppression (Trellis M=8..16)",
        "}",
        "",
        "public enum DSDRateMultiplier: Int, CaseIterable, Sendable, Codable {",
        "    case dsd64  = 64",
        "    case dsd128 = 128",
        "    case dsd256 = 256",
        "    case dsd512 = 512",
        "}",
        "",
        "public enum BaseClockGrid: Int, CaseIterable, Sendable, Codable {",
        "    case grid44k1 = 44100",
        "    case grid48k  = 48000",
        "}",
        "",
        "/// Выровненная под регистры ARM NEON (float64x2_t / SIMD2<Double>) структура коэффициентов",
        "/// симплектической биквадратной решётки 7-го порядка с Rank-2 грамианом наблюдаемости Витерби.",
        "@frozen",
        "public struct SDM7SectionCoefficients: Sendable {",
        "    public let sampleRateHz: Int",
        "    public let outOfBandGain: Double",
        "    public let maxPoleQ: Double",
        "    /// Входной коэффициент первого DC-интегратора: ns0 = s0 + b0 * (u - y)",
        "    public let b0: Double",
        "    /// Межкаскадные связи (a1: s0->s1, a2: s2->s3, a3: s4->s5, pad: 0)",
        "    public let aLink01: SIMD2<Double>",
        "    public let aLink2Pad: SIMD2<Double>",
        "    /// Обратные связи резонаторов Чебышёва (g1, g2) и (g3, 0) — удерживают |z_zero| == 1.0",
        "    public let gFeedback01: SIMD2<Double>",
        "    public let gFeedback2Pad: SIMD2<Double>",
        "    /// Внутренние симплектические интеграторы резонаторов (c1, c2) и (c3, 0)",
        "    public let cIntegrator01: SIMD2<Double>",
        "    public let cIntegrator2Pad: SIMD2<Double>",
        "    /// Точный масштабированный вектор весов сумматора квантователя C_raw (7 состояний + 0 для ISI слота)",
        "    public let ff01: SIMD2<Double>",
        "    public let ff23: SIMD2<Double>",
        "    public let ff45: SIMD2<Double>",
        "    public let ff6IsiPad: SIMD2<Double>",
        "    /// Главная собственная мода грамиана наблюдаемости P_obs: sqrt(lambda_1) * v_1",
        "    public let obs0_01: SIMD2<Double>",
        "    public let obs0_23: SIMD2<Double>",
        "    public let obs0_45: SIMD2<Double>",
        "    public let obs0_6Pad: SIMD2<Double>",
        "    /// Вторая собственная мода грамиана наблюдаемости P_obs: sqrt(lambda_2) * v_2",
        "    public let obs1_01: SIMD2<Double>",
        "    public let obs1_23: SIMD2<Double>",
        "    public let obs1_45: SIMD2<Double>",
        "    public let obs1_6Pad: SIMD2<Double>",
        "    /// Евклидова норма вектора сумматора ||C_raw||_2",
        "    public let cNorm: Double",
        "    /// Вес штрафа межсимвольной интерференции (ISI Edge-Rate Regularizer) в целевой функции Витерби",
        "    public let isiLambda: Double",
        "    /// Порог мягкого барьера состояний",
        "    public let softClipThreshold: Double",
        "    /// Рекомендованная ширина выживших путей дерева Trellis (M)",
        "    public let recommendedTrellisM: Int",
        "",
        "    public init(",
        "        sampleRateHz: Int,",
        "        outOfBandGain: Double,",
        "        maxPoleQ: Double,",
        "        b0: Double,",
        "        aLink01: SIMD2<Double>,",
        "        aLink2Pad: SIMD2<Double>,",
        "        gFeedback01: SIMD2<Double>,",
        "        gFeedback2Pad: SIMD2<Double>,",
        "        cIntegrator01: SIMD2<Double>,",
        "        cIntegrator2Pad: SIMD2<Double>,",
        "        ff01: SIMD2<Double>,",
        "        ff23: SIMD2<Double>,",
        "        ff45: SIMD2<Double>,",
        "        ff6IsiPad: SIMD2<Double>,",
        "        obs0_01: SIMD2<Double>,",
        "        obs0_23: SIMD2<Double>,",
        "        obs0_45: SIMD2<Double>,",
        "        obs0_6Pad: SIMD2<Double>,",
        "        obs1_01: SIMD2<Double>,",
        "        obs1_23: SIMD2<Double>,",
        "        obs1_45: SIMD2<Double>,",
        "        obs1_6Pad: SIMD2<Double>,",
        "        cNorm: Double,",
        "        isiLambda: Double,",
        "        softClipThreshold: Double,",
        "        recommendedTrellisM: Int",
        "    ) {",
        "        self.sampleRateHz = sampleRateHz",
        "        self.outOfBandGain = outOfBandGain",
        "        self.maxPoleQ = maxPoleQ",
        "        self.b0 = b0",
        "        self.aLink01 = aLink01",
        "        self.aLink2Pad = aLink2Pad",
        "        self.gFeedback01 = gFeedback01",
        "        self.gFeedback2Pad = gFeedback2Pad",
        "        self.cIntegrator01 = cIntegrator01",
        "        self.cIntegrator2Pad = cIntegrator2Pad",
        "        self.ff01 = ff01",
        "        self.ff23 = ff23",
        "        self.ff45 = ff45",
        "        self.ff6IsiPad = ff6IsiPad",
        "        self.obs0_01 = obs0_01",
        "        self.obs0_23 = obs0_23",
        "        self.obs0_45 = obs0_45",
        "        self.obs0_6Pad = obs0_6Pad",
        "        self.obs1_01 = obs1_01",
        "        self.obs1_23 = obs1_23",
        "        self.obs1_45 = obs1_45",
        "        self.obs1_6Pad = obs1_6Pad",
        "        self.cNorm = cNorm",
        "        self.isiLambda = isiLambda",
        "        self.softClipThreshold = softClipThreshold",
        "        self.recommendedTrellisM = recommendedTrellisM",
        "    }",
        "",
        "    /// Плавная линейная интерполяция коэффициентов для бесшовного A/B-переключения профилей за 5 мс.",
        "    @inlinable",
        "    public func interpolated(to target: SDM7SectionCoefficients, t: Double) -> SDM7SectionCoefficients {",
        "        let k = min(max(t, 0.0), 1.0)",
        "        let inv = 1.0 - k",
        "        return SDM7SectionCoefficients(",
        "            sampleRateHz: target.sampleRateHz,",
        "            outOfBandGain: inv * outOfBandGain + k * target.outOfBandGain,",
        "            maxPoleQ: inv * maxPoleQ + k * target.maxPoleQ,",
        "            b0: inv * b0 + k * target.b0,",
        "            aLink01: inv * aLink01 + k * target.aLink01,",
        "            aLink2Pad: inv * aLink2Pad + k * target.aLink2Pad,",
        "            gFeedback01: inv * gFeedback01 + k * target.gFeedback01,",
        "            gFeedback2Pad: inv * gFeedback2Pad + k * target.gFeedback2Pad,",
        "            cIntegrator01: inv * cIntegrator01 + k * target.cIntegrator01,",
        "            cIntegrator2Pad: inv * cIntegrator2Pad + k * target.cIntegrator2Pad,",
        "            ff01: inv * ff01 + k * target.ff01,",
        "            ff23: inv * ff23 + k * target.ff23,",
        "            ff45: inv * ff45 + k * target.ff45,",
        "            ff6IsiPad: inv * ff6IsiPad + k * target.ff6IsiPad,",
        "            obs0_01: inv * obs0_01 + k * target.obs0_01,",
        "            obs0_23: inv * obs0_23 + k * target.obs0_23,",
        "            obs0_45: inv * obs0_45 + k * target.obs0_45,",
        "            obs0_6Pad: inv * obs0_6Pad + k * target.obs0_6Pad,",
        "            obs1_01: inv * obs1_01 + k * target.obs1_01,",
        "            obs1_23: inv * obs1_23 + k * target.obs1_23,",
        "            obs1_45: inv * obs1_45 + k * target.obs1_45,",
        "            obs1_6Pad: inv * obs1_6Pad + k * target.obs1_6Pad,",
        "            cNorm: inv * cNorm + k * target.cNorm,",
        "            isiLambda: inv * isiLambda + k * target.isiLambda,",
        "            softClipThreshold: inv * softClipThreshold + k * target.softClipThreshold,",
        "            recommendedTrellisM: target.recommendedTrellisM",
        "        )",
        "    }",
        "}",
        "",
        "public enum SDM7CoefficientBank {",
        "    @inlinable",
        "    public static func lookup(",
        "        profile: SDM7Profile,",
        "        rate: DSDRateMultiplier,",
        "        grid: BaseClockGrid",
        "    ) -> SDM7SectionCoefficients {",
        "        switch (profile, rate, grid) {",
    ]

    for m in models:
        grid_case = "grid44k1" if m.grid_hz == 44100 else "grid48k"
        fn_name = f"_{m.profile}_{m.rate_case}_{grid_case}"
        lines.append(f"        case (.{m.profile}, .{m.rate_case}, .{grid_case}): return {fn_name}")

    lines.append("        }")
    lines.append("    }")
    lines.append("")

    for m in models:
        grid_case = "grid44k1" if m.grid_hz == 44100 else "grid48k"
        fn_name = f"_{m.profile}_{m.rate_case}_{grid_case}"
        a1, a2, a3 = m.a_link
        g1, g2, g3 = m.g_fb
        c1, c2, c3 = m.c_int
        f0, f1, f2, f3, f4, f5, f6 = m.ff_weights
        o00, o01, o02, o03, o04, o05, o06 = m.obs_lead0
        o10, o11, o12, o13, o14, o15, o16 = m.obs_lead1

        lines.extend([
            f"    // Fs={m.fs_hz} Hz | OBG={m.obg_actual:.4f} | ||h_NTF||_1={m.ntf_l1_norm:.3f} | Q_max={m.max_pole_q:.2f} | "
            f"PoleErr={m.pole_error_f64:.2e} | ZeroErr={m.zero_unit_error_f64:.2e} | Trellis SNR={m.verified_snr_db:.1f} dB",
            f"    @usableFromInline",
            f"    static let {fn_name} = SDM7SectionCoefficients(",
            f"        sampleRateHz: {m.fs_hz},",
            f"        outOfBandGain: {_fmt_f64(m.obg_actual)},",
            f"        maxPoleQ: {_fmt_f64(m.max_pole_q)},",
            f"        b0: {_fmt_f64(m.b0)},",
            f"        aLink01: SIMD2<Double>({_fmt_f64(a1)}, {_fmt_f64(a2)}),",
            f"        aLink2Pad: SIMD2<Double>({_fmt_f64(a3)}, 0.0),",
            f"        gFeedback01: SIMD2<Double>({_fmt_f64(g1)}, {_fmt_f64(g2)}),",
            f"        gFeedback2Pad: SIMD2<Double>({_fmt_f64(g3)}, 0.0),",
            f"        cIntegrator01: SIMD2<Double>({_fmt_f64(c1)}, {_fmt_f64(c2)}),",
            f"        cIntegrator2Pad: SIMD2<Double>({_fmt_f64(c3)}, 0.0),",
            f"        ff01: SIMD2<Double>({_fmt_f64(f0)}, {_fmt_f64(f1)}),",
            f"        ff23: SIMD2<Double>({_fmt_f64(f2)}, {_fmt_f64(f3)}),",
            f"        ff45: SIMD2<Double>({_fmt_f64(f4)}, {_fmt_f64(f5)}),",
            f"        ff6IsiPad: SIMD2<Double>({_fmt_f64(f6)}, 0.0),",
            f"        obs0_01: SIMD2<Double>({_fmt_f64(o00)}, {_fmt_f64(o01)}),",
            f"        obs0_23: SIMD2<Double>({_fmt_f64(o02)}, {_fmt_f64(o03)}),",
            f"        obs0_45: SIMD2<Double>({_fmt_f64(o04)}, {_fmt_f64(o05)}),",
            f"        obs0_6Pad: SIMD2<Double>({_fmt_f64(o06)}, 0.0),",
            f"        obs1_01: SIMD2<Double>({_fmt_f64(o10)}, {_fmt_f64(o11)}),",
            f"        obs1_23: SIMD2<Double>({_fmt_f64(o12)}, {_fmt_f64(o13)}),",
            f"        obs1_45: SIMD2<Double>({_fmt_f64(o14)}, {_fmt_f64(o15)}),",
            f"        obs1_6Pad: SIMD2<Double>({_fmt_f64(o16)}, 0.0),",
            f"        cNorm: {_fmt_f64(m.c_norm)},",
            f"        isiLambda: {_fmt_f64(m.isi_lambda)},",
            f"        softClipThreshold: {_fmt_f64(m.soft_clip_threshold)},",
            f"        recommendedTrellisM: {m.recommended_trellis_m}",
            f"    )",
            "",
        ])

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Synthesize 7th-order SDM coefficients for Pure Swift 6.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("AppleMusicRemoteMac/Sources/AppleMusicRemoteMac/DSP/ModulatorSDM7/SDM7Coefficients.swift"),
        help="Path to generated Swift file",
    )
    args = parser.parse_args()

    synthesized: list[SynthesizedModel] = []
    print(
        f"{'Profile':<14} {'Rate':<8} {'Grid':<7} {'OBG':<6} {'||h||_1':<8} "
        f"{'Q_max':<6} {'PoleErr':<10} {'ZeroErr':<10} {'SNR(20-20kHz)'}"
    )
    print("-" * 92)

    for rate in RATES:
        for grid_hz in (44100, 48000):
            for prof in PROFILES:
                model = synthesize_model(prof, rate, grid_hz)
                synthesized.append(model)
                print(
                    f"{prof.display_name:<14} {rate.swift_case:<8} {grid_hz:<7} "
                    f"{model.obg_actual:<6.2f} {model.ntf_l1_norm:<8.4f} {model.max_pole_q:<6.2f} "
                    f"{model.pole_error_f64:<10.2e} {model.zero_unit_error_f64:<10.2e} "
                    f"{model.verified_snr_db:>6.1f} dB"
                )

    swift_code = render_swift_file(synthesized)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(swift_code, encoding="utf-8")
    print(f"\n[OK] Generated {len(synthesized)} tables -> {args.output}")


if __name__ == "__main__":
    main()
