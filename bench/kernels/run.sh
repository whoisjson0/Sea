#!/bin/sh
# bench/kernels/run.sh -- per-target runner of the Sea-level kernel benchmarks (docs/DESIGN.md
# 2.17.6). POSIX sh. Run by bench/kernels.sh on the Mac and, from the unpacked bundle, on the
# Linux host; it builds nothing.
#
# usage: sh run.sh measure TARGET DIR LOADS
#   TARGET  arm64-macos | x86_64-linux (the first TSV column)
#   DIR     holds the built executables gemm, solve, axpby (Sea), vendor, axpby_ref and expect
#   LOADS   file that receives `load_before<TAB>a b c` just before the first measured process
#           and `load_after<TAB>a b c` just after the last one (the three load averages)
#   Prints the TSV of 2.17.9 on standard output (header `target cpu kernel impl variant n reps
#   batch median_s min_s max_s unit rate pct_vendor`), progress on standard error.
#   Environment: BENCH_QUICK=1 (quick: the sizes in parentheses of 2.17.6, 0.2 s of timed calls
#   per measurement instead of 1.0 s and 1 ms per process instead of 5 ms). The runner's own
#   processing runs with LC_ALL=C; the measured processes are started without LC_ALL.
#   Exit status: 0 every row measured and validated; 1 a validation failure (no TSV printed);
#   2 setup error.
#
# usage: sh run.sh record OUT
#   Writes the machine record of 2.17.3 (one `key<TAB>value` line per item, in its order) to OUT:
#   the facts of this machine (machine_model, cpu, os, power, lowpower, tools) are read here;
#   the others come from the environment: KR_TARGET KR_MODE KR_SESSION KR_DATE KR_SEA_COMMIT
#   KR_SEA_DIRTY KR_BAYSICK_COMMIT KR_BAYSICK_DIRTY KR_NICE KR_VARIANTS KR_SETTLE_WAITED and
#   KR_LOADS (the LOADS file of `measure`).
#
# The protocol (2.17.6): each executable takes N BATCH (vendor: KERNEL N BATCH), makes the
# untimed warm-up call and BATCH timed calls, and prints `check ...` (from the last call, input
# parity P = BATCH mod 2) and `seconds %.9e`. For each kernel, size and implementation this
# runner (1) calibrates with a reference batch: b = 2, 8, 32, ... until the minimum of
# CALIBRUNS = 3 runs at BATCH = b times at least REFSECS = 10 us of calls in all (b x per-call
# seconds); then t_ref = that minimum per call, b_ref = b, and BATCH = ceil(TARGETSECS / t_ref),
# at most 100 000, where TARGETSECS = 5 ms (quick 1 ms) of timed calls per process, so that the
# 200-process cap reaches 1.0 s (quick 0.2 s); (2) repeats with that BATCH, one process per
# repetition, until at least 5 repetitions and at least 1.0 s (quick 0.2 s) of timed calls (sum
# of seconds x BATCH), at most 200; (3) validates every run's `check` line, the calibration's
# included: gemm and axpby equal to `expect KERNEL N P`, solve's maxerr at most 1e-9; and,
# whenever BATCH > b_ref, the median per-call time at least t_ref / 2 (Decision 171 (a)); (4)
# reports the median of the repetitions' seconds with their minimum and maximum. The reference
# batch, its minimum of 3 (L-qc) and the 5 ms target replace 2.17.6's single BATCH = 1 run and
# its 100 us target (review fixes of 10b; the lead amends 2.17.6): a single call below a few us
# cannot be timed against the 1 us tick of macOS's CLOCK_MONOTONIC or the cost of the two clock
# reads, and one run is noisy. The reference starts at 2 calls because the first timed call of a
# process can cost a steady 2x the later ones (gemm 64 Sea on the i7-4790: ~29 us against
# 14.5 us); with 2 calls a first-call cost up to 3x the steady one passes the guard.
# The guard's window, honestly: kernels whose BATCH is at most b_ref (calls of about 2.5 ms and
# more, BATCH 1 or 2) are not guarded; and a program that skips all but the last call escapes
# wherever its real call costs less than REFSECS, because b_ref then grows until the loop's own
# overhead fills the reference (axpby N = 1 000 for example). It is caught where its call costs
# at least REFSECS and BATCH exceeds 2 b_ref (from axpby N = 100 000 and gemm N = 64 up to calls
# of about 1 ms). Outside the window the per-call input change (no call is loop-invariant) and
# the check line (the last call ran, on its own input) still hold.
# Implementations: sea (Mac variant neon; Linux SEA_KERNELS=avx2 and =sse2), vendor (Linux axpby:
# vendor-proxy) and, for axpby, c-O2; vendor and c-O2 rows have the variant `-`. Rates: work /
# median, in 10^9 units (gemm 2N^3 flop, solve (2/3)N^3 + 2N^2 flop, axpby 24N bytes); pct_vendor
# = 100 x sea rate / vendor (or vendor-proxy) rate at the same kernel and N, on sea rows only.
# Environment of the measured processes (2.17.3): SEA_HEAP_CHECK, BAYSICK_KERNELS removed;
# SEA_KERNELS removed on the Mac, set to the variant for the sea rows on Linux (removed for the
# others); VECLIB_MAXIMUM_THREADS=1 (Mac), OPENBLAS_NUM_THREADS=1 (Linux); standard input
# /dev/null; no nice value, QoS class or affinity is set (L-oz).

LC_ALL=C; export LC_ALL

loads() { uptime | sed 's/.*load averages*: *//' | tr -d ','; }

if [ "$(uname -s)" = Darwin ]; then
    CPU=$(sysctl -n machdep.cpu.brand_string)
else
    CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -1)
fi

# ---------------------------------------------------------------- record
if [ "${1:-}" = record ]; then
    OUT=${2:-}
    [ -n "$OUT" ] || { echo "run.sh: usage: sh run.sh record OUT" >&2; exit 2; }
    for v in KR_TARGET KR_MODE KR_SESSION KR_DATE KR_SEA_COMMIT KR_SEA_DIRTY KR_BAYSICK_COMMIT \
        KR_BAYSICK_DIRTY KR_NICE KR_VARIANTS KR_SETTLE_WAITED KR_LOADS; do
        eval "val=\${$v:-}"
        [ -n "$val" ] || { echo "run.sh: record: $v is not set" >&2; exit 2; }
    done
    LB=$(sed -n 's/^load_before	//p' "$KR_LOADS" | head -1)
    LA=$(sed -n 's/^load_after	//p' "$KR_LOADS" | head -1)
    [ -n "$LB" ] && [ -n "$LA" ] || { echo "run.sh: record: $KR_LOADS lacks load_before or load_after" >&2; exit 2; }
    if [ "$(uname -s)" = Darwin ]; then
        MODEL=$(sysctl -n hw.model)
        OSV="macOS $(sw_vers -productVersion) ($(uname -sr))"
        if pmset -g batt | head -1 | grep 'AC Power' >/dev/null; then POWER=ac; else POWER=battery; fi
        LOWP=$(pmset -g | awk '$1 == "lowpowermode" { print $2 }')
        [ -n "$LOWP" ] || LOWP=0
        TOOLS=$(xcrun cc --version | head -1)
    else
        MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | head -1)
        [ -n "$MODEL" ] || MODEL=-
        OSV=$(uname -sr)
        POWER=-; LOWP=-
        TOOLS=$(gcc --version | head -1)
    fi
    {
        printf 'target\t%s\n' "$KR_TARGET"
        printf 'mode\t%s\n' "$KR_MODE"
        printf 'session\t%s\n' "$KR_SESSION"
        printf 'date\t%s\n' "$KR_DATE"
        printf 'machine_model\t%s\n' "$MODEL"
        printf 'cpu\t%s\n' "$CPU"
        printf 'os\t%s\n' "$OSV"
        printf 'sea_commit\t%s\n' "$KR_SEA_COMMIT"
        printf 'sea_dirty\t%s\n' "$KR_SEA_DIRTY"
        printf 'baysick_commit\t%s\n' "$KR_BAYSICK_COMMIT"
        printf 'baysick_dirty\t%s\n' "$KR_BAYSICK_DIRTY"
        printf 'nice\t%s\n' "$KR_NICE"
        printf 'power\t%s\n' "$POWER"
        printf 'lowpower\t%s\n' "$LOWP"
        printf 'variants\t%s\n' "$KR_VARIANTS"
        printf 'tools\t%s\n' "$TOOLS"
        printf 'settle_waited_s\t%s\n' "$KR_SETTLE_WAITED"
        printf 'load_before\t%s\n' "$LB"
        printf 'load_after\t%s\n' "$LA"
    } >"$OUT" || { echo "run.sh: cannot write $OUT" >&2; exit 2; }
    exit 0
fi

# ---------------------------------------------------------------- measure
[ "${1:-}" = measure ] || { echo "run.sh: usage: sh run.sh measure TARGET DIR LOADS | record OUT" >&2; exit 2; }
TARGET=${2:-}; DIR=${3:-}; LOADS=${4:-}
[ -n "$TARGET" ] && [ -d "$DIR" ] && [ -n "$LOADS" ] || { echo "run.sh: usage: sh run.sh measure TARGET DIR LOADS" >&2; exit 2; }
case $TARGET in
arm64-macos) VARIANTS=neon ;;
x86_64-linux) VARIANTS="avx2 sse2" ;;
*) echo "run.sh: unknown target '$TARGET'" >&2; exit 2 ;;
esac
for e in gemm solve axpby vendor axpby_ref expect; do
    [ -x "$DIR/$e" ] || { echo "run.sh: $DIR/$e missing" >&2; exit 2; }
done
if [ "${BENCH_QUICK:-}" = 1 ]; then
    MINSECS=0.2
    TARGETSECS=0.001   # timed calls per process: 0.2 s / 200 processes
    SIZES_gemm="64 128 256 512"; SIZES_solve="100 250 500"; SIZES_axpby="1000 100000"
else
    MINSECS=1.0
    TARGETSECS=0.005   # timed calls per process: 1.0 s / 200 processes
    SIZES_gemm="64 128 256 512 1024 2048"; SIZES_solve="100 250 500 1000 2000"; SIZES_axpby="1000 100000 10000000"
fi
MINREPS=5
MAXREPS=200
CALIBRUNS=3     # runs per reference batch; t_ref is their minimum (L-qc)
MAXBATCH=100000
REFSECS=0.00001  # the reference batch times at least 10 us of calls in all

T=$(mktemp -d "${TMPDIR:-/tmp}/sea-kern.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"; exit 2' HUP INT TERM PIPE

# the environment of the measured processes (2.17.3)
unset SEA_HEAP_CHECK BAYSICK_KERNELS SEA_KERNELS
if [ "$TARGET" = arm64-macos ]; then
    export VECLIB_MAXIMUM_THREADS=1
else
    export OPENBLAS_NUM_THREADS=1
fi

# the expected lines, before any measurement
for k in gemm axpby; do
    eval "sizes=\$SIZES_$k"
    for n in $sizes; do
        for p in 0 1; do
            "$DIR/expect" $k $n $p >"$T/expect.$k.$n.$p" || { echo "run.sh: expect $k $n $p failed" >&2; exit 2; }
        done
    done
done

vfail() { echo "run.sh: $1" >&2; exit 1; }

# run_one IMPL VARIANT KERNEL N BATCH : one process; leaves its output in $T/out and its
# per-call seconds in SECS; a failed run or check is a validation failure (exit 1)
run_one() {
    case $1 in
    sea) set -- "$@" "$DIR/$3" "$4" "$5" ;;
    vendor) set -- "$@" "$DIR/vendor" "$3" "$4" "$5" ;;
    c-O2) set -- "$@" "$DIR/axpby_ref" "$4" "$5" ;;
    esac
    _impl=$1; _var=$2; _k=$3; _n=$4; _b=$5
    shift 5
    if [ "$_impl" = sea ] && [ "$TARGET" = x86_64-linux ]; then
        (unset LC_ALL; SEA_KERNELS=$_var exec "$@") >"$T/out" 2>"$T/err" </dev/null
    else
        (unset LC_ALL; exec "$@") >"$T/out" 2>"$T/err" </dev/null
    fi
    _st=$?
    _what="$_k $_impl${_var:+ ($_var)} N=$_n BATCH=$_b"
    [ $_st -eq 0 ] || vfail "$_what exited with status $_st: $(head -2 "$T/err")"
    [ "$(wc -l <"$T/out" | tr -d ' ')" = 2 ] || vfail "$_what printed $(wc -l <"$T/out" | tr -d ' ') lines, want 2 (check, seconds)"
    _check=$(sed -n 1p "$T/out")
    _p=$((_b % 2))
    case $_k in
    gemm | axpby)
        _want=$(cat "$T/expect.$_k.$_n.$_p")
        [ "$_check" = "$_want" ] || vfail "$_what: '$_check', want '$_want' (expect $_k $_n $_p)" ;;
    solve)
        _e=$(printf '%s\n' "$_check" | sed -n 's/^check maxerr \([0-9]\.[0-9][0-9][0-9]e[-+][0-9][0-9]*\)$/\1/p')
        [ -n "$_e" ] || vfail "$_what: malformed check line '$_check'"
        awk -v e="$_e" 'BEGIN { exit !(e + 0 <= 1e-9) }' || vfail "$_what: maxerr $_e above 1e-9" ;;
    esac
    SECS=$(sed -n '2s/^seconds \([0-9]\.[0-9]\{9\}e[-+][0-9][0-9]*\)$/\1/p' "$T/out")
    [ -n "$SECS" ] || vfail "$_what: malformed seconds line '$(sed -n 2p "$T/out")'"
}

# measure IMPL VARIANT KERNEL N : calibration, repetitions, validation; appends one row to $T/rows
measure() {
    _mi=$1; _mv=$2; _mk=$3; _mn=$4
    # calibration (reference batch): b = 2, 8, 32, ... until the minimum of CALIBRUNS runs at
    # BATCH = b (each validated) times at least REFSECS of calls in all; t_ref = that minimum
    # per call, b_ref = b (L-qc applied to the reference batch)
    bref=2
    while :; do
        run_one "$_mi" "$_mv" "$_mk" "$_mn" "$bref"
        tref=$SECS
        _c=1
        while [ $_c -lt $CALIBRUNS ]; do
            run_one "$_mi" "$_mv" "$_mk" "$_mn" "$bref"
            tref=$(awk -v a="$tref" -v b="$SECS" 'BEGIN { print (b + 0 < a + 0) ? b : a }')
            _c=$((_c + 1))
        done
        awk -v t="$tref" -v b="$bref" -v r="$REFSECS" 'BEGIN { exit !(t * b < r) }' || break
        [ "$bref" -lt "$MAXBATCH" ] || vfail "$_mk $_mi${_mv:+ ($_mv)} N=$_mn: $bref calls take less than $REFSECS s"
        bref=$((bref * 4))
        [ "$bref" -le "$MAXBATCH" ] || bref=$MAXBATCH
    done
    # BATCH: the per-process target of timed calls / t_ref, rounded up, at most MAXBATCH
    batch=$(awk -v t="$tref" -v g="$TARGETSECS" -v cap="$MAXBATCH" 'BEGIN {
        b = g / t; c = int(b); if (c < b) c++
        if (c < 1) c = 1
        if (c > cap) c = cap
        print c }')
    : >"$T/secs"
    reps=0; tot=0
    while :; do
        run_one "$_mi" "$_mv" "$_mk" "$_mn" "$batch"
        echo "$SECS" >>"$T/secs"
        reps=$((reps + 1))
        tot=$(awk -v a="$tot" -v s="$SECS" -v b="$batch" 'BEGIN { printf "%.9f", a + s * b }')
        [ "$reps" -lt "$MAXREPS" ] || break
        if [ "$reps" -ge "$MINREPS" ] && awk -v t="$tot" -v m="$MINSECS" 'BEGIN { exit !(t >= m) }'; then break; fi
    done
    # median, minimum, maximum of the repetitions' seconds
    stats=$(awk '{ v[NR] = $1 + 0 }
        END {
            for (i = 2; i <= NR; i++) { x = v[i]; j = i - 1; while (j >= 1 && v[j] > x) { v[j + 1] = v[j]; j-- } v[j + 1] = x }
            med = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
            printf "%.9e %.9e %.9e\n", med, v[1], v[NR] }' "$T/secs")
    set -- $stats
    med=$1; mn=$2; mx=$3
    # the factor-2 guard (Decision 171 (a)) against the reference batch, whenever BATCH > b_ref
    if [ "$batch" -gt "$bref" ]; then
        awk -v m="$med" -v t="$tref" 'BEGIN { exit !(m >= t / 2) }' ||
            vfail "$_mk $_mi${_mv:+ ($_mv)} N=$_mn: the median per-call time $med with BATCH=$batch is below half the per-call time $tref of the reference batch BATCH=$bref: work skipped or merged"
    fi
    case $_mk in
    gemm) unit=GFLOP/s; rate=$(awk -v n="$_mn" -v m="$med" 'BEGIN { printf "%.3f", 2 * n * n * n / m / 1e9 }') ;;
    solve) unit=GFLOP/s; rate=$(awk -v n="$_mn" -v m="$med" 'BEGIN { printf "%.3f", (2 / 3 * n * n * n + 2 * n * n) / m / 1e9 }') ;;
    axpby) unit=GB/s; rate=$(awk -v n="$_mn" -v m="$med" 'BEGIN { printf "%.3f", 24 * n / m / 1e9 }') ;;
    esac
    label=$_mi
    [ "$_mi" = vendor ] && [ "$_mk" = axpby ] && [ "$TARGET" = x86_64-linux ] && label=vendor-proxy
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TARGET" "$CPU" "$_mk" "$label" \
        "${_mv:--}" "$_mn" "$reps" "$batch" "$med" "$mn" "$mx" "$unit" "$rate" >>"$T/rows"
    echo "run.sh: $_mk $label ${_mv:--} N=$_mn: $reps x BATCH=$batch (b_ref $bref, t_ref $tref), median $med s, $rate $unit" >&2
}

: >"$T/rows"
printf 'load_before\t%s\n' "$(loads)" >"$LOADS" || { echo "run.sh: cannot write $LOADS" >&2; exit 2; }
for k in gemm solve axpby; do
    eval "sizes=\$SIZES_$k"
    for n in $sizes; do
        for v in $VARIANTS; do measure sea "$v" "$k" "$n"; done
        measure vendor "" "$k" "$n"
        [ "$k" = axpby ] && measure c-O2 "" "$k" "$n"
    done
done
printf 'load_after\t%s\n' "$(loads)" >>"$LOADS" || { echo "run.sh: cannot write $LOADS" >&2; exit 2; }

# the TSV, pct_vendor filled in on the sea rows from the vendor (or proxy) row of the same kernel and N
printf 'target\tcpu\tkernel\timpl\tvariant\tn\treps\tbatch\tmedian_s\tmin_s\tmax_s\tunit\trate\tpct_vendor\n'
awk -F '\t' 'BEGIN { OFS = "\t" }
    { row[NR] = $0; k[NR] = $3; im[NR] = $4; n[NR] = $6; r[NR] = $13
      if ($4 == "vendor" || $4 == "vendor-proxy") vr[$3 SUBSEP $6] = $13 }
    END {
        for (i = 1; i <= NR; i++) {
            p = ""
            if (im[i] == "sea") {
                key = k[i] SUBSEP n[i]
                if (!(key in vr) || vr[key] + 0 <= 0) { print "run.sh: no vendor rate for " k[i] " N=" n[i] > "/dev/stderr"; exit 2 }
                p = sprintf("%.2f", 100 * r[i] / vr[key])
            }
            print row[i], p
        }
    }' "$T/rows" || exit 2
exit 0
