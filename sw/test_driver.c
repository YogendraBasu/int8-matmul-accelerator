#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "matmul_driver.h"

#define NUM_MAC 4u

typedef struct {
    int8_t a[64];
    int8_t b[64];
    int32_t c[64];
    uint32_t n;
    uint32_t cycles;
    unsigned busy_polls;
    int pending;
    int stuck;
    int done;
    int err;
} model_t;

static unsigned expected_cycles(unsigned n)
{
    return n * ((n + NUM_MAC - 1u) / NUM_MAC) * (n + 1u);
}

static void finish(model_t *m)
{
    unsigned i, j, k, n = m->n;
    for (i = 0; i < n; i++)
        for (j = 0; j < n; j++) {
            int32_t acc = 0;
            for (k = 0; k < n; k++)
                acc += (int32_t)m->a[i * n + k] * (int32_t)m->b[k * n + j];
            m->c[i * n + j] = acc;
        }
    m->cycles = expected_cycles(n);
    m->pending = 0;
    m->done = 1;
}

static uint32_t model_read(void *ctx, uint32_t off)
{
    model_t *m = (model_t *)ctx;
    if (off == MATMUL_REG_STATUS) {
        if (m->pending) {
            if (m->stuck)
                return MATMUL_STATUS_BUSY;
            if (m->busy_polls > 0) {
                m->busy_polls--;
                return MATMUL_STATUS_BUSY;
            }
            finish(m);
        }
        return (m->err ? MATMUL_STATUS_ERROR : 0u) | (m->done ? MATMUL_STATUS_DONE : 0u);
    }
    if (off == MATMUL_REG_CONFIG)
        return m->n;
    if (off == MATMUL_REG_CYCLES)
        return m->cycles;
    if (off >= MATMUL_BASE_C && off < MATMUL_BASE_C + 256u)
        return (uint32_t)m->c[(off - MATMUL_BASE_C) >> 2];
    return 0u;
}

static void model_write(void *ctx, uint32_t off, uint32_t val)
{
    model_t *m = (model_t *)ctx;
    if (off == MATMUL_REG_CTRL) {
        if (val & MATMUL_CTRL_RESET) {
            m->pending = 0; m->done = 0; m->err = 0;
        } else if (val & MATMUL_CTRL_START) {
            if (m->pending || m->n < 1u || m->n > MATMUL_MAX_N) {
                m->err = 1;
            } else {
                m->pending = 1;
                m->done = 0;
                m->busy_polls = 3;
            }
        }
    } else if (off == MATMUL_REG_STATUS) {
        if (val & MATMUL_STATUS_DONE)  m->done = 0;
        if (val & MATMUL_STATUS_ERROR) m->err = 0;
    } else if (off == MATMUL_REG_CONFIG) {
        m->n = val & 0xFFu;
    } else if (off >= MATMUL_BASE_A && off < MATMUL_BASE_A + 256u) {
        m->a[(off - MATMUL_BASE_A) >> 2] = (int8_t)(val & 0xFFu);
    } else if (off >= MATMUL_BASE_B && off < MATMUL_BASE_B + 256u) {
        m->b[(off - MATMUL_BASE_B) >> 2] = (int8_t)(val & 0xFFu);
    }
}

static int failures;

static void check(int cond, const char *msg)
{
    if (!cond) {
        printf("FAIL: %s\n", msg);
        failures++;
    }
}

static void reference(const int8_t *a, const int8_t *b, int32_t *c, unsigned n)
{
    unsigned i, j, k;
    for (i = 0; i < n; i++)
        for (j = 0; j < n; j++) {
            int32_t acc = 0;
            for (k = 0; k < n; k++)
                acc += (int32_t)a[i * n + k] * (int32_t)b[k * n + j];
            c[i * n + j] = acc;
        }
}

static void run_case(unsigned n, int mode)
{
    model_t m;
    matmul_io_t io;
    int8_t a[64], b[64];
    int32_t c[64], ref[64];
    uint32_t cycles = 0;
    unsigned i;
    int rc;

    memset(&m, 0, sizeof m);
    io.read32 = model_read;
    io.write32 = model_write;
    io.ctx = &m;

    for (i = 0; i < n * n; i++) {
        if (mode == 0) { a[i] = (int8_t)(rand() % 256 - 128); b[i] = (int8_t)(rand() % 256 - 128); }
        else if (mode == 1) { a[i] = -128; b[i] = -128; }
        else { a[i] = -128; b[i] = 127; }
    }
    reference(a, b, ref, n);

    rc = matmul_run(&io, a, b, c, n, 100u, &cycles);
    check(rc == MATMUL_OK, "run returns OK");
    check(memcmp(c, ref, n * n * sizeof(int32_t)) == 0, "result matches reference");
    check(cycles == expected_cycles(n), "cycle count matches formula");
}

int main(void)
{
    model_t m;
    matmul_io_t io;
    int8_t a[64] = {0}, b[64] = {0};
    int32_t c[64];
    unsigned n;
    int t;

    srand(1);
    for (t = 0; t < 200; t++)
        run_case(1u + (unsigned)(rand() % 8), 0);
    for (n = 1; n <= 8; n++) {
        run_case(n, 1);
        run_case(n, 2);
    }

    memset(&m, 0, sizeof m);
    io.read32 = model_read;
    io.write32 = model_write;
    io.ctx = &m;

    check(matmul_run(&io, a, b, c, 0, 100u, NULL) == MATMUL_EINVAL, "n = 0 rejected");
    check(matmul_run(&io, a, b, c, 9, 100u, NULL) == MATMUL_EINVAL, "n = 9 rejected");
    check(matmul_run(&io, NULL, b, c, 4, 100u, NULL) == MATMUL_EINVAL, "null pointer rejected");

    m.stuck = 1;
    m.pending = 1;
    check(matmul_run(&io, a, b, c, 4, 100u, NULL) == MATMUL_EBUSY, "busy device detected");

    memset(&m, 0, sizeof m);
    m.stuck = 1;
    check(matmul_run(&io, a, b, c, 4, 50u, NULL) == MATMUL_ETIMEOUT, "timeout reported");

    if (failures) {
        printf("%d driver test(s) failed\n", failures);
        return 1;
    }
    printf("driver tests passed\n");
    return 0;
}
