/* axpby_ref.c -- the C loop of the fused element-wise benchmark (DESIGN.md 2.17.6, the `c-O2`
 * row): w[i] = 0.75 * x[i] - 1.25 * y[i], the expression of axpby.sea written as one C loop into
 * a reused buffer, with the same data, per-call input change, check computation and output.
 * Built with `cc -O2 -ffp-contract=off`. A measuring tool, never part of Sea.
 *
 *   axpby_ref N BATCH   build x, y (untimed); call 0 (the untimed warm-up); calls 1..BATCH timed
 *                       back to back with CLOCK_MONOTONIC, each preceded by x[0] = x0 + (r mod 2);
 *                       print `check %.2f %.2f` (S1 = sum w, S2 = sum w ((i mod 17) - 8)) from the
 *                       last call and `seconds %.9e` (batch time / BATCH; `seconds 0` if BATCH = 0)
 *
 * The timed loop is a function declared noinline whose body ends with an empty asm volatile with
 * a "memory" clobber (L-pt), so -O2 can neither inline it into the timing loop nor hoist or merge
 * calls. Exit status: 0 measured; 2 usage error or out of memory.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void usage(void) {
    fprintf(stderr, "axpby_ref: usage: axpby_ref N BATCH\n");
    exit(2);
}

static int64_t parse_int(const char *s, int64_t lo, int64_t hi) {
    char *end;
    if (!*s) usage();
    long long v = strtoll(s, &end, 10);
    if (*end || v < lo || v > hi) usage();
    return (int64_t)v;
}

__attribute__((noinline)) static void call_axpby(int64_t n, const double *x, const double *y, double *w) {
    for (int64_t i = 0; i < n; i++) w[i] = 0.75 * x[i] - 1.25 * y[i];
    __asm__ volatile("" ::: "memory");
}

int main(int argc, char **argv) {
    if (argc != 3) usage();
    int64_t n = parse_int(argv[1], 1, 100000000);
    int64_t batch = parse_int(argv[2], 0, 100000000);
    double *x = malloc((size_t)n * sizeof(double));
    double *y = malloc((size_t)n * sizeof(double));
    double *w = malloc((size_t)n * sizeof(double));
    if (!x || !y || !w) { fprintf(stderr, "axpby_ref: out of memory\n"); return 2; }
    for (int64_t i = 0; i < n; i++) {
        x[i] = (double)(i % 2047 - 1023);
        y[i] = (double)(5 * i % 2039 - 1019);
    }
    const double x0 = x[0];
    call_axpby(n, x, y, w);                          /* call 0: the warm-up, untimed */
    double t0 = now_s();
    for (int64_t r = 1; r <= batch; r++) {
        x[0] = x0 + (double)(r % 2);
        call_axpby(n, x, y, w);
    }
    double secs = now_s() - t0;
    double s1 = 0.0, s2 = 0.0;
    for (int64_t i = 0; i < n; i++) {
        s1 = s1 + w[i];
        s2 = s2 + w[i] * (double)(i % 17 - 8);
    }
    printf("check %.2f %.2f\n", s1, s2);
    if (batch > 0) printf("seconds %.9e\n", secs / (double)batch);
    else printf("seconds 0\n");
    return 0;
}
