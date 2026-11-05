/* expect.c -- the exact expected `check` lines of the Sea-level kernel benchmarks (DESIGN.md
 * 2.17.6, L-pe). A measuring tool, never part of Sea. Built with `cc -O2 -ffp-contract=off`.
 *
 *   expect gemm N P     the line `check S1 S2` of gemm.sea (and vendor gemm) after a last call
 *                       of input parity P (0 or 1), S1 and S2 printed as `%.0f` prints them
 *   expect axpby N P    the line `check S1 S2` of axpby.sea (vendor, axpby_ref), as `%.2f`
 *
 * Everything is computed in int64_t from the formulas of 2.17.6, independently of the order of
 * operations of any implementation (indices from 0):
 *
 *   gemm   a[i,k] = ((3i + 5k) mod 17) - 8, with P added to a[0,0]; b[k,j] = ((7k + 2j) mod 13) - 6;
 *          c = a b; S1 = sum c[i,j]; S2 = sum c[i,j] * (((7i + 13j) mod 17) - 8).
 *          S1 = sum_k (sum_i a[i,k]) (sum_j b[k,j]). The weight depends on i only through
 *          i mod 17, so with G[m][k] = sum_j b[k,j] * (((7m + 13j) mod 17) - 8) for m = 0..16,
 *          S2 = sum_i sum_k a[i,k] G[i mod 17][k]: O(17 N^2) instead of N^3, exact.
 *   axpby  x[i] = (i mod 2047) - 1023, with P added to x[0]; y[i] = (5i mod 2039) - 1019;
 *          w = 0.75 x - 1.25 y, so 4w = 3x - 5y is an integer; S1 = sum w, S2 = sum w ((i mod 17) - 8)
 *          are multiples of 0.25 and printed exactly with two decimals from 4 S1 and 4 S2.
 *
 * Every magnitude stays far below 2^53 at the sizes of 2.17.6 (|c[i,j]| <= 64 N, |S| < 2^43 for
 * N = 2048; |4 S| < 2^40 for N = 10^7), so the double results of a correct implementation are these
 * integers exactly, and `%.0f` of an integer-valued double prints its decimal digits.
 * Exit status: 0 printed, 2 usage error or out of memory.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(void) {
    fprintf(stderr, "expect: usage: expect gemm|axpby N P\n");
    exit(2);
}

/* parse a decimal integer in [lo, hi]; anything else is a usage error */
static int64_t parse_int(const char *s, int64_t lo, int64_t hi) {
    char *end;
    if (!*s) usage();
    long long v = strtoll(s, &end, 10);
    if (*end || v < lo || v > hi) usage();
    return (int64_t)v;
}

/* m mod k for m >= 0 (every argument here is non-negative) */
static int64_t md(int64_t m, int64_t k) { return m % k; }

/* print q/4 with exactly two decimals, as printf("%.2f") prints the double q/4 */
static void print_quarters(int64_t q) {
    int64_t a = q < 0 ? -q : q;
    printf("%s%lld.%02lld", q < 0 ? "-" : "", (long long)(a / 4), (long long)((a % 4) * 25));
}

static void gemm(int64_t n, int64_t p) {
    int64_t *colA = calloc((size_t)n, sizeof *colA);   /* sum_i a[i,k] */
    int64_t *rowB = calloc((size_t)n, sizeof *rowB);   /* sum_j b[k,j] */
    int64_t *g = calloc((size_t)(17 * n), sizeof *g);  /* G[m][k] at g[m*n + k] */
    if (!colA || !rowB || !g) { fprintf(stderr, "expect: out of memory\n"); exit(2); }
    for (int64_t k = 0; k < n; k++) {
        for (int64_t j = 0; j < n; j++) {
            int64_t bkj = md(7 * k + 2 * j, 13) - 6;
            rowB[k] += bkj;
            for (int64_t m = 0; m < 17; m++) g[m * n + k] += bkj * (md(7 * m + 13 * j, 17) - 8);
        }
    }
    int64_t s1 = 0, s2 = 0;
    for (int64_t i = 0; i < n; i++) {
        const int64_t *gi = g + md(i, 17) * n;
        for (int64_t k = 0; k < n; k++) {
            int64_t aik = md(3 * i + 5 * k, 17) - 8 + ((i == 0 && k == 0) ? p : 0);
            colA[k] += aik;
            s2 += aik * gi[k];
        }
    }
    for (int64_t k = 0; k < n; k++) s1 += colA[k] * rowB[k];
    printf("check %lld %lld\n", (long long)s1, (long long)s2);
    free(colA); free(rowB); free(g);
}

static void axpby(int64_t n, int64_t p) {
    int64_t t1 = 0, t2 = 0;   /* 4 S1 and 4 S2 */
    for (int64_t i = 0; i < n; i++) {
        int64_t x = md(i, 2047) - 1023 + (i == 0 ? p : 0);
        int64_t y = md(5 * i, 2039) - 1019;
        int64_t w4 = 3 * x - 5 * y;
        t1 += w4;
        t2 += w4 * (md(i, 17) - 8);
    }
    printf("check ");
    print_quarters(t1);
    printf(" ");
    print_quarters(t2);
    printf("\n");
}

int main(int argc, char **argv) {
    if (argc != 4) usage();
    int64_t n = parse_int(argv[2], 1, 100000000);
    int64_t p = parse_int(argv[3], 0, 1);
    if (!strcmp(argv[1], "gemm")) {
        if (n > 65536) usage();
        gemm(n, p);
    } else if (!strcmp(argv[1], "axpby")) {
        axpby(n, p);
    } else {
        usage();
    }
    return 0;
}
