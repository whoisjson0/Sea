/* vendor.c -- the vendor-library implementations of the Sea-level kernel benchmarks (DESIGN.md
 * 2.17.6, L-ph): Accelerate on the Mac (__APPLE__), OpenBLAS on Linux. A measuring tool, never
 * part of Sea; it contains no Sea logic. Built with
 *   xcrun cc -O2 -ffp-contract=off -DACCELERATE_NEW_LAPACK -o vendor vendor.c -framework Accelerate
 *   gcc -O2 -ffp-contract=off [-I<OpenBLAS's include directory>] -o vendor vendor.c -lopenblas -lm
 *
 *   vendor gemm|solve|axpby N BATCH   the protocol of 2.17.6: build the data (untimed), call 0
 *                                     (the untimed warm-up), then calls 1..BATCH timed back to
 *                                     back with CLOCK_MONOTONIC, each preceded by the input change
 *                                     of parity r mod 2; print `check ...` from the last call and
 *                                     `seconds %.9e` (batch time / BATCH; `seconds 0` if BATCH = 0)
 *   vendor config                     print the vendor library's identification; on Linux exit 3
 *                                     when the linked library is not OpenBLAS
 *
 * The calls: gemm  cblas_dgemm (CblasRowMajor, alpha 1, beta 0) into a preallocated C;
 *            solve dgesv_ (one right-hand side) on copies of a (filled column-major, the same
 *                  matrix as solve.sea) and b made inside each timed call, since dgesv
 *                  overwrites them (L-ph);
 *            axpby Mac: vDSP_vsmsmaD, w = x*0.75 + y*(-1.25), one pass, out of place;
 *                  Linux: cblas_dcopy (y -> w) then cblas_daxpby (w = 0.75 x - 1.25 w), the
 *                  two-pass proxy that kernels-x86_64-linux.tsv labels `vendor-proxy`.
 * Every timed call goes through a function declared noinline whose body ends with an empty asm
 * volatile with a "memory" clobber (L-pt), so -O2 can neither inline, hoist nor merge calls. The
 * library runs on one thread: VECLIB_MAXIMUM_THREADS=1 is set with setenv before the first
 * Accelerate call; openblas_set_num_threads(1) on Linux (Baysick BENCH.md 1, 4).
 * Exit status: 0 measured; 1 the library reported a failure (dgesv info != 0); 2 usage error or
 * out of memory; 3 (config, Linux) the library is not OpenBLAS.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef __APPLE__
#include <Accelerate/Accelerate.h>
typedef __LAPACK_int lint;
#else
#include <cblas.h>
typedef blasint lint;
extern void dgesv_(const lint *n, const lint *nrhs, double *a, const lint *lda, lint *ipiv,
                   double *b, const lint *ldb, lint *info);
#endif

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void usage(void) {
    fprintf(stderr, "vendor: usage: vendor gemm|solve|axpby N BATCH  |  vendor config\n");
    exit(2);
}

static int64_t parse_int(const char *s, int64_t lo, int64_t hi) {
    char *end;
    if (!*s) usage();
    long long v = strtoll(s, &end, 10);
    if (*end || v < lo || v > hi) usage();
    return (int64_t)v;
}

static double *alloc_f64(int64_t count) {
    double *p = malloc((size_t)count * sizeof(double));
    if (!p) { fprintf(stderr, "vendor: out of memory\n"); exit(2); }
    return p;
}

static void print_seconds(double secs, int64_t batch) {
    if (batch > 0) printf("seconds %.9e\n", secs / (double)batch);
    else printf("seconds 0\n");
}

/* ---- the timed calls (L-pt) */

__attribute__((noinline)) static void call_gemm(lint n, const double *a, const double *b, double *c) {
    cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, n, n, n, 1.0, a, n, b, n, 0.0, c, n);
    __asm__ volatile("" ::: "memory");
}

/* returns dgesv's info (0 on success); x is left in wb */
__attribute__((noinline)) static lint call_solve(lint n, const double *acm, const double *b, double *wa,
                                                 double *wb, lint *ipiv) {
    lint nrhs = 1, info = 0;
    memcpy(wa, acm, (size_t)n * (size_t)n * sizeof(double));
    memcpy(wb, b, (size_t)n * sizeof(double));
    dgesv_(&n, &nrhs, wa, &n, ipiv, wb, &n, &info);
    __asm__ volatile("" ::: "memory");
    return info;
}

__attribute__((noinline)) static void call_axpby(lint n, const double *x, const double *y, double *w) {
#ifdef __APPLE__
    const double alpha = 0.75, beta = -1.25;
    vDSP_vsmsmaD(x, 1, &alpha, y, 1, &beta, w, 1, (vDSP_Length)n);
#else
    cblas_dcopy(n, y, 1, w, 1);
    cblas_daxpby(n, 0.75, x, 1, -1.25, w, 1);
#endif
    __asm__ volatile("" ::: "memory");
}

/* ---- the three benchmarks */

static void bench_gemm(int64_t n, int64_t batch) {
    double *a = alloc_f64(n * n), *b = alloc_f64(n * n), *c = alloc_f64(n * n);
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < n; j++) {
            a[i * n + j] = (double)((3 * i + 5 * j) % 17 - 8);
            b[i * n + j] = (double)((7 * i + 2 * j) % 13 - 6);
        }
    const double a00 = a[0];
    call_gemm((lint)n, a, b, c);                     /* call 0: the warm-up, untimed */
    double t0 = now_s();
    for (int64_t r = 1; r <= batch; r++) {
        a[0] = a00 + (double)(r % 2);
        call_gemm((lint)n, a, b, c);
    }
    double secs = now_s() - t0;
    double s1 = 0.0, s2 = 0.0;
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < n; j++) {
            s1 = s1 + c[i * n + j];
            s2 = s2 + c[i * n + j] * (double)((7 * i + 13 * j) % 17 - 8);
        }
    printf("check %.0f %.0f\n", s1, s2);
    print_seconds(secs, batch);
}

static void bench_solve(int64_t n, int64_t batch) {
    double *acm = alloc_f64(n * n);                  /* a, column-major: a[i,j] at acm[i + j*n] */
    double *xt = alloc_f64(n), *b0 = alloc_f64(n), *b = alloc_f64(n);
    double *wa = alloc_f64(n * n), *wb = alloc_f64(n);
    lint *ipiv = malloc((size_t)n * sizeof(lint));
    if (!ipiv) { fprintf(stderr, "vendor: out of memory\n"); exit(2); }
    for (int64_t i = 0; i < n; i++) {
        for (int64_t j = 0; j < n; j++) acm[i + j * n] = (double)((3 * i + 5 * j) % 17 - 8);
        acm[i + i * n] = acm[i + i * n] + (double)(9 * n);
        xt[i] = (double)(i % 9 - 4);
    }
    for (int64_t i = 0; i < n; i++) {                /* b0 = a @ xt, exact (integers far below 2^53) */
        double s = 0.0;
        for (int64_t j = 0; j < n; j++) s = s + acm[i + j * n] * xt[j];
        b0[i] = s;
        b[i] = s;
    }
    if (call_solve((lint)n, acm, b, wa, wb, ipiv) != 0) {   /* call 0: the warm-up, untimed */
        fprintf(stderr, "vendor: dgesv reported a singular matrix\n");
        exit(1);
    }
    lint info = 0;
    double t0 = now_s();
    for (int64_t r = 1; r <= batch; r++) {
        for (int64_t i = 0; i < n; i++) b[i] = b0[i] + (double)(r % 2) * acm[i];
        info |= call_solve((lint)n, acm, b, wa, wb, ipiv);
    }
    double secs = now_s() - t0;
    if (info != 0) { fprintf(stderr, "vendor: dgesv reported a singular matrix\n"); exit(1); }
    double e = 0.0;
    for (int64_t i = 0; i < n; i++) {
        double want = xt[i];
        if (i == 0) want = want + (double)(batch % 2);
        double d = wb[i] - want;
        if (d < 0) d = -d;
        if (d > e) e = d;
    }
    printf("check maxerr %.3e\n", e);
    print_seconds(secs, batch);
}

static void bench_axpby(int64_t n, int64_t batch) {
    double *x = alloc_f64(n), *y = alloc_f64(n), *w = alloc_f64(n);
    for (int64_t i = 0; i < n; i++) {
        x[i] = (double)(i % 2047 - 1023);
        y[i] = (double)(5 * i % 2039 - 1019);
    }
    const double x0 = x[0];
    call_axpby((lint)n, x, y, w);                    /* call 0: the warm-up, untimed */
    double t0 = now_s();
    for (int64_t r = 1; r <= batch; r++) {
        x[0] = x0 + (double)(r % 2);
        call_axpby((lint)n, x, y, w);
    }
    double secs = now_s() - t0;
    double s1 = 0.0, s2 = 0.0;
    for (int64_t i = 0; i < n; i++) {
        s1 = s1 + w[i];
        s2 = s2 + w[i] * (double)(i % 17 - 8);
    }
    printf("check %.2f %.2f\n", s1, s2);
    print_seconds(secs, batch);
}

int main(int argc, char **argv) {
    /* one thread, before the first library call */
#ifdef __APPLE__
    setenv("VECLIB_MAXIMUM_THREADS", "1", 1);
#else
    const char *cfg = openblas_get_config();
    if (!cfg || !strstr(cfg, "OpenBLAS")) {
        fprintf(stderr, "vendor: the linked BLAS is not OpenBLAS\n");
        return 3;
    }
    openblas_set_num_threads(1);
    if (openblas_get_num_threads() != 1) { fprintf(stderr, "vendor: could not force OpenBLAS to one thread\n"); return 2; }
#endif
    if (argc == 2 && !strcmp(argv[1], "config")) {
#ifdef __APPLE__
        printf("Accelerate (VECLIB_MAXIMUM_THREADS=1)\n");
#else
        printf("%s (threads %d)\n", cfg, openblas_get_num_threads());
#endif
        return 0;
    }
    if (argc != 4) usage();
    int64_t n = parse_int(argv[2], 1, 100000000);
    int64_t batch = parse_int(argv[3], 0, 100000000);
    if (!strcmp(argv[1], "gemm")) {
        if (n > 46340) usage();                      /* n*n in a lint */
        bench_gemm(n, batch);
    } else if (!strcmp(argv[1], "solve")) {
        if (n > 46340) usage();
        bench_solve(n, batch);
    } else if (!strcmp(argv[1], "axpby")) {
        bench_axpby(n, batch);
    } else {
        usage();
    }
    return 0;
}
