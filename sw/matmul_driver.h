#ifndef MATMUL_DRIVER_H
#define MATMUL_DRIVER_H

#include <stdint.h>
#include "matmul_regs.h"

typedef struct {
    uint32_t (*read32)(void *ctx, uint32_t offset);
    void (*write32)(void *ctx, uint32_t offset, uint32_t value);
    void *ctx;
} matmul_io_t;

enum {
    MATMUL_OK = 0,
    MATMUL_EINVAL = -1,
    MATMUL_EBUSY = -2,
    MATMUL_ETIMEOUT = -3,
    MATMUL_EHW = -4
};

matmul_io_t matmul_mmio(volatile void *base);

void matmul_reset(const matmul_io_t *io);

int matmul_run(const matmul_io_t *io,
               const int8_t *a, const int8_t *b, int32_t *c,
               unsigned n, uint32_t max_polls, uint32_t *cycles);

#endif
