#!/usr/bin/env python3
import os, random, sys

def s8(x):
    x &= 0xFF
    return x - 256 if x & 0x80 else x

def s32(x):
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x

def matmul_ref(a, b, n):
    return [sum(a[i*n+k] * b[k*n+j] for k in range(n)) for i in range(n) for j in range(n)]

class CoreModel:
    IDLE, COMPUTE, WRITE, DONE = range(4)

    def __init__(self, num_mac=4, max_n=8):
        self.M, self.max_n = num_mac, max_n
        self.a = [0] * (max_n * max_n)
        self.b = [0] * (max_n * max_n)
        self.c = [0] * (max_n * max_n)

    def run(self, n):
        M = self.M
        state, i, j, k = self.COMPUTE, 0, 0, 0
        acc = [0] * M
        cycles = 0
        busy_clocks = 1
        while state != self.IDLE:
            busy_clocks += 1
            if state == self.COMPUTE:
                for m in range(M):
                    if j + m < n:
                        acc[m] = s32(acc[m] + self.a[i*n+k] * self.b[k*n+j+m])
                cycles += 1
                if k == n - 1: k, state = 0, self.WRITE
                else:          k += 1
            elif state == self.WRITE:
                for m in range(M):
                    if j + m < n:
                        self.c[i*n+j+m] = acc[m]
                acc = [0] * M
                cycles += 1
                if j + M >= n:
                    j = 0
                    if i == n - 1: state = self.DONE
                    else:          i += 1; state = self.COMPUTE
                else:
                    j += M; state = self.COMPUTE
            elif state == self.DONE:
                state = self.IDLE
        return cycles, busy_clocks

def expected_cycles(n, m):
    return n * ((n + m - 1) // m) * (n + 1)

def rand_mat(n, mode):
    if mode == "rand": return [random.randint(-128, 127) for _ in range(n*n)]
    if mode == "min":  return [-128] * (n*n)
    if mode == "max":  return [127] * (n*n)
    if mode == "zero": return [0] * (n*n)
    raise ValueError(mode)

def self_test():
    random.seed(1)
    runs = 0
    for m in (1, 2, 4, 8):
        for n in range(1, 17):
            for ma, mb in [("rand","rand"), ("min","min"), ("min","max"), ("max","max"), ("zero","rand")]:
                dut = CoreModel(num_mac=m, max_n=16)
                a, b = rand_mat(n, ma), rand_mat(n, mb)
                dut.a[:n*n], dut.b[:n*n] = a, b
                cyc, _ = dut.run(n)
                assert dut.c[:n*n] == matmul_ref(a, b, n), f"RESULT MISMATCH n={n} M={m} {ma}/{mb}"
                assert cyc == expected_cycles(n, m),       f"CYCLE MISMATCH n={n} M={m}: {cyc} vs {expected_cycles(n,m)}"
                runs += 1

    worst = 16 * 128 * 128
    assert worst < 2**31
    print(f"self-test OK : {runs} runs, results and cycle counts match")
    for n in (5, 8):
        c1, c4 = expected_cycles(n, 1), expected_cycles(n, 4)
        print(f"  N={n}: 1-MAC {c1} cycles, 4-MAC {c4} cycles -> {100*(1-c4/c1):.1f}% fewer")

def gen_vectors(count, outdir="vectors", max_n=8):
    os.makedirs(outdir, exist_ok=True)
    random.seed(7)
    for t in range(count):
        n = random.randint(1, max_n)
        a, b = rand_mat(n, "rand"), rand_mat(n, "rand")
        c = matmul_ref(a, b, n)
        with open(f"{outdir}/a_{t}.hex", "w") as fa, open(f"{outdir}/b_{t}.hex", "w") as fb, \
             open(f"{outdir}/c_{t}.hex", "w") as fc, open(f"{outdir}/n_{t}.hex", "w") as fn:
            fn.write(f"{n:02x}\n")
            for x in a: fa.write(f"{x & 0xFF:02x}\n")
            for x in b: fb.write(f"{x & 0xFF:02x}\n")
            for x in c: fc.write(f"{x & 0xFFFFFFFF:08x}\n")
    print(f"wrote {count} vector sets to ./{outdir}")

if __name__ == "__main__":
    self_test()
    if len(sys.argv) >= 3 and sys.argv[1] == "vectors":
        gen_vectors(int(sys.argv[2]))
