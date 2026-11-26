#include "matmul_driver.h"

static uint32_t mmio_read32(void *ctx, uint32_t offset)
{
    volatile uint32_t *base = (volatile uint32_t *)ctx;
    return base[offset >> 2];
}

static void mmio_write32(void *ctx, uint32_t offset, uint32_t value)
{
    volatile uint32_t *base = (volatile uint32_t *)ctx;
    base[offset >> 2] = value;
}

matmul_io_t matmul_mmio(volatile void *base)
{
    matmul_io_t io;
    io.read32 = mmio_read32;
    io.write32 = mmio_write32;
    io.ctx = (void *)base;
    return io;
}

void matmul_reset(const matmul_io_t *io)
{
    io->write32(io->ctx, MATMUL_REG_CTRL, MATMUL_CTRL_RESET);
}

int matmul_run(const matmul_io_t *io,
               const int8_t *a, const int8_t *b, int32_t *c,
               unsigned n, uint32_t max_polls, uint32_t *cycles)
{
    unsigned i, count;
    uint32_t status, polls;

    if (!io || !a || !b || !c || n < 1u || n > MATMUL_MAX_N)
        return MATMUL_EINVAL;

    status = io->read32(io->ctx, MATMUL_REG_STATUS);
    if (status & MATMUL_STATUS_BUSY)
        return MATMUL_EBUSY;

    io->write32(io->ctx, MATMUL_REG_STATUS, MATMUL_STATUS_DONE | MATMUL_STATUS_ERROR);
    io->write32(io->ctx, MATMUL_REG_CONFIG, n);

    count = n * n;
    for (i = 0; i < count; i++) {
        io->write32(io->ctx, MATMUL_BASE_A + 4u * i, (uint32_t)(uint8_t)a[i]);
        io->write32(io->ctx, MATMUL_BASE_B + 4u * i, (uint32_t)(uint8_t)b[i]);
    }

    io->write32(io->ctx, MATMUL_REG_CTRL, MATMUL_CTRL_START);

    for (polls = 0; polls < max_polls; polls++) {
        status = io->read32(io->ctx, MATMUL_REG_STATUS);
        if (status & MATMUL_STATUS_ERROR) {
            io->write32(io->ctx, MATMUL_REG_STATUS, MATMUL_STATUS_ERROR);
            return MATMUL_EHW;
        }
        if (status & MATMUL_STATUS_DONE)
            break;
    }
    if (polls == max_polls)
        return MATMUL_ETIMEOUT;

    for (i = 0; i < count; i++)
        c[i] = (int32_t)io->read32(io->ctx, MATMUL_BASE_C + 4u * i);

    if (cycles)
        *cycles = io->read32(io->ctx, MATMUL_REG_CYCLES);

    io->write32(io->ctx, MATMUL_REG_STATUS, MATMUL_STATUS_DONE);
    return MATMUL_OK;
}
