#ifndef MATMUL_REGS_H
#define MATMUL_REGS_H

#define MATMUL_REG_CTRL      0x000u
#define MATMUL_REG_STATUS    0x004u
#define MATMUL_REG_CONFIG    0x008u
#define MATMUL_REG_CYCLES    0x00Cu
#define MATMUL_BASE_A        0x400u
#define MATMUL_BASE_B        0x800u
#define MATMUL_BASE_C        0xC00u

#define MATMUL_CTRL_START    (1u << 0)
#define MATMUL_CTRL_RESET    (1u << 1)

#define MATMUL_STATUS_BUSY   (1u << 0)
#define MATMUL_STATUS_DONE   (1u << 1)
#define MATMUL_STATUS_ERROR  (1u << 2)

#define MATMUL_MAX_N         8u

#endif
