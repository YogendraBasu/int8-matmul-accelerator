import random
import unittest

from golden_model import CoreModel, expected_cycles, matmul_ref, rand_mat


class GoldenModelTests(unittest.TestCase):
    def run_model(self, n, m, a, b):
        dut = CoreModel(num_mac=m, max_n=16)
        dut.a[:n * n] = a
        dut.b[:n * n] = b
        cycles, _ = dut.run(n)
        return dut.c[:n * n], cycles

    def test_results_match_reference(self):
        random.seed(3)
        for m in (1, 2, 4, 8):
            for n in range(1, 17):
                a, b = rand_mat(n, "rand"), rand_mat(n, "rand")
                c, _ = self.run_model(n, m, a, b)
                self.assertEqual(c, matmul_ref(a, b, n))

    def test_cycle_formula(self):
        for m in (1, 2, 4, 8):
            for n in range(1, 17):
                a, b = rand_mat(n, "zero"), rand_mat(n, "zero")
                _, cycles = self.run_model(n, m, a, b)
                self.assertEqual(cycles, expected_cycles(n, m))

    def test_extreme_values(self):
        for n in (1, 5, 8):
            a, b = rand_mat(n, "min"), rand_mat(n, "min")
            c, _ = self.run_model(n, 4, a, b)
            self.assertTrue(all(x == n * 128 * 128 for x in c))

    def test_latency_reduction_at_eight(self):
        self.assertEqual(expected_cycles(8, 1), 576)
        self.assertEqual(expected_cycles(8, 4), 144)

    def test_accumulator_fits_in_32_bits(self):
        self.assertLess(16 * 128 * 128, 2 ** 31)


if __name__ == "__main__":
    unittest.main()
