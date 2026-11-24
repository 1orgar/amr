#ifndef AMR_ATOMICS_H
#define AMR_ATOMICS_H

#include <stdint.h>

static inline __attribute__((always_inline)) int64_t amr_atomic_load_i64_acquire(const int64_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_ACQUIRE);
}

static inline __attribute__((always_inline)) int64_t amr_atomic_load_i64_relaxed(const int64_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_RELAXED);
}

static inline __attribute__((always_inline)) void amr_atomic_store_i64_release(int64_t *ptr, int64_t val) {
    __atomic_store_n(ptr, val, __ATOMIC_RELEASE);
}

static inline __attribute__((always_inline)) void amr_atomic_store_i64_relaxed(int64_t *ptr, int64_t val) {
    __atomic_store_n(ptr, val, __ATOMIC_RELAXED);
}

static inline __attribute__((always_inline)) uint64_t amr_atomic_load_u64_relaxed(const uint64_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_RELAXED);
}

static inline __attribute__((always_inline)) void amr_atomic_store_u64_relaxed(uint64_t *ptr, uint64_t val) {
    __atomic_store_n(ptr, val, __ATOMIC_RELAXED);
}

static inline __attribute__((always_inline)) uint64_t amr_atomic_inc_u64_relaxed(uint64_t *ptr) {
    return __atomic_fetch_add(ptr, 1ULL, __ATOMIC_RELAXED);
}

static inline __attribute__((always_inline)) uint32_t amr_atomic_load_u32_acquire(const uint32_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_ACQUIRE);
}

static inline __attribute__((always_inline)) void amr_atomic_store_u32_release(uint32_t *ptr, uint32_t val) {
    __atomic_store_n(ptr, val, __ATOMIC_RELEASE);
}

#endif /* AMR_ATOMICS_H */
