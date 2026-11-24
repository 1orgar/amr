#include <metal_stdlib>
using namespace metal;

// Эмуляция повышенной точности Double-Float (df64 = float2(hi, lo), ~48 бит мантиссы, динамический диапазон > 150 dB)
// на базе алгоритмов Деккера–Кнута с использованием аппаратной инструкции fma() GPU Apple Silicon.

typedef float2 df64;

// Запрещаем ассоциативные fast-math упрощения LLVM/Metal, иначе Кнутовские суммы ошибок
// `b - (s - a)` и `(a - (s - v)) + (b - v)` сворачиваются компилятором в тождественный `0.0f`!
inline df64 df64_quick_two_sum(float a, float b) {
    #pragma clang fp reassociate(off)
    #pragma clang fp contract(off)
    float s = a + b;
    float z = s - a;
    float e = b - z;
    return df64(s, e);
}

inline df64 df64_two_sum(float a, float b) {
    #pragma clang fp reassociate(off)
    #pragma clang fp contract(off)
    float s = a + b;
    float v = s - a;
    float e = (a - (s - v)) + (b - v);
    return df64(s, e);
}

inline df64 df64_add(df64 a, df64 b) {
    #pragma clang fp reassociate(off)
    #pragma clang fp contract(off)
    df64 s = df64_two_sum(a.x, b.x);
    s.y += a.y + b.y;
    return df64_quick_two_sum(s.x, s.y);
}

inline df64 df64_mul(df64 a, float2 b) {
    #pragma clang fp reassociate(off)
    #pragma clang fp contract(off)
    float p = a.x * b.x;
    float e = fma(a.x, b.x, -p);
    e = fma(a.x, b.y, e);
    e = fma(a.y, b.x, e);
    return df64_quick_two_sum(p, e);
}

struct PolyphaseDispatchParams {
    uint inputFrames;
    uint factor;
    uint tapsPerPhase;
};

// Вычисляет полифазную свёртку КИХ-фильтра Stage 1 (до 262 144+ тапов в сумме) в арифметике df64
// параллельно по всем выходным отсчётам и фазам на GPU Apple Silicon (Unified Memory Zero-Copy).
kernel void polyphase_fir_df64_stereo(
    device const df64* historyAndInputL [[buffer(0)]],
    device const df64* historyAndInputR [[buffer(1)]],
    device const df64* polyphaseWeights [[buffer(2)]],
    device df64* outDXDL                [[buffer(3)]],
    device df64* outDXDR                [[buffer(4)]],
    constant PolyphaseDispatchParams& params [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalOutputs = params.inputFrames * params.factor;
    if (gid >= totalOutputs) {
        return;
    }

    uint inFrame = gid / params.factor;
    uint phase = gid % params.factor;
    uint taps = params.tapsPerPhase;

    device const df64* winL = historyAndInputL + inFrame;
    device const df64* winR = historyAndInputR + inFrame;
    device const df64* weights = polyphaseWeights + (phase * taps);

    df64 accL = df64(0.0f, 0.0f);
    df64 accR = df64(0.0f, 0.0f);

    for (uint k = 0; k < taps; ++k) {
        df64 w = weights[k];
        accL = df64_add(accL, df64_mul(winL[k], w));
        accR = df64_add(accR, df64_mul(winR[k], w));
    }

    outDXDL[gid] = accL;
    outDXDR[gid] = accR;
}
