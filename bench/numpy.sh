#!/bin/sh
# bench/numpy.sh -- the NumPy column of the workload benchmark (DESIGN.md 2.17.3, 2.17.5,
# Decision 167, L-pd). POSIX sh, macOS only.
#
# usage: sh bench/numpy.sh measure [--out DIR] [--quick]
#
# 1. checks the preconditions of 2.17.3 and reads DIR/session.txt; runs
#    `uv run --no-project --with numpy==2.5.4 python -c 'import numpy'` (any download happens
#    before measuring); in final mode applies the start condition (bench/settle.sh);
# 2. reads load_before, then runs
#        uv run --no-project --with numpy==2.5.4 python -I bench/numpy_time.py [--quick] DIR SCRATCH
#    with VECLIB_MAXIMUM_THREADS, OPENBLAS_NUM_THREADS and OMP_NUM_THREADS removed (NumPy's
#    default threads, Decision 172 (a)), SEA_HEAP_CHECK, BAYSICK_KERNELS, SEA_KERNELS and LC_ALL
#    removed and standard input /dev/null; SCRATCH is a mktemp -d directory removed on exit. numpy_time.py
#    times 5 runs of each workload's main() in one interpreter (--quick: 1), validates run 1 with
#    compare.py's NumPy mode and runs 2-5 against run 1, and writes SCRATCH/numpy-arm64-macos.tsv;
# 3. only when numpy_time.py succeeded, publishes that TSV and DIR/env-numpy-arm64-macos.txt, the
#    machine record of 2.17.3 with tools, numpy_blas, numpy_threads and load_after from
#    SCRATCH/info.txt, into DIR.
# Final mode creates DIR/.attempt-numpy-arm64-macos before the start condition and refuses when it
# exists (C2, one attempt per session); a quick run refuses a DIR holding a final session, a final
# run one holding a quick session (C3). LC_ALL is C for this script only (C4).
#
#   --out DIR  the results directory (default bench/results/p10)
#   --quick    (also BENCH_QUICK=1) 1 run per workload, no start condition, `mode quick`, files
#              overwritten. Final mode (the default) refuses an existing output file, a niced
#              driver, battery power or Low Power Mode, a dirty Sea or Baysick tree, and a PORTS
#              or KERNELS override.
# Environment: BAYSICK (default the parent of this repository); PORTS, KERNELS (checked only).
# Exit status: 0 measured, validated and written; 1 a validation failure (no file written);
# 2 a setup error.

LC_ALL=C; export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEA=$ROOT/build/sea
BAYSICK=${BAYSICK:-$(cd "$ROOT/.." && pwd)}
case $BAYSICK in /*) ;; *) BAYSICK=$(cd "$BAYSICK" 2>/dev/null && pwd) ;; esac
PIN=numpy==2.5.4
TARGET=arm64-macos

fail() { echo "numpy.sh: $1" >&2; exit 2; }
usage() { fail "usage: sh bench/numpy.sh measure [--out DIR] [--quick]"; }

CMD=
OUT=$ROOT/bench/results/p10
QUICK=
[ "${BENCH_QUICK:-}" = 1 ] && QUICK=1
while [ $# -gt 0 ]; do
    case $1 in
    measure) [ -z "$CMD" ] || usage; CMD=$1; shift ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --quick) QUICK=1; shift ;;
    *) echo "numpy.sh: unknown argument '$1'" >&2; usage ;;
    esac
done
[ "$CMD" = measure ] || usage
case $OUT in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
if [ -n "$QUICK" ]; then MODE=quick; else MODE=final; fi
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

loads() {
    uptime | sed -n 's/.*load average[s]*: *//p' | tr -d ',' | awk 'NF == 3 { print $1, $2, $3 }'
}

# ---- the output files and the session: a final-mode result file is never replaced (L-ps)
TSV_F=numpy-$TARGET.tsv
ENV_F=env-numpy-$TARGET.txt
if [ "$MODE" = final ]; then
    for f in "$TSV_F" "$ENV_F"; do
        [ ! -e "$OUT/$f" ] || fail "'$OUT/$f' exists; a final-mode result file is written once per session and never replaced"
    done
fi
[ -f "$OUT/session.txt" ] || fail "'$OUT/session.txt' not found; create the session first (sh bench/session.sh DIR)"
SESSION=$(head -1 "$OUT/session.txt")
[ -n "$SESSION" ] || fail "'$OUT/session.txt' is empty"
case $SESSION in
quick-*) [ "$MODE" = quick ] || fail "'$OUT/session.txt' records a quick session; final mode needs a final session (sh bench/session.sh DIR)" ;;
*) [ "$MODE" = final ] || fail "'$OUT/session.txt' records a final session; refusing to overwrite a final session with a quick run" ;;
esac

# ---- preconditions (2.17.3) ----------------------------------------------------------------------
[ -x "$SEA" ] || fail "driver '$SEA' not found; run 'make' first"
[ "$(uname -sm)" = "Darwin arm64" ] || fail "the NumPy column is measured on the Mac only"
NICE=$(ps -o nice= -p $$ | tr -d ' ')
[ "$MODE" = quick ] || [ "$NICE" = 0 ] || fail "the driver runs with nice value $NICE; final mode measures unniced (nice 0)"
case $(pmset -g batt | head -1) in
*"AC Power"*) POWER=ac ;;
*"Battery Power"*) POWER=battery ;;
*) POWER=- ;;
esac
LOWPOWER=$(pmset -g | awk '$1 == "lowpowermode" { print $2; exit }')
[ -n "$LOWPOWER" ] || LOWPOWER=0
SEA_COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || fail "cannot read the Sea commit"
if [ -n "$(git -C "$ROOT" status --porcelain -- . ':(exclude)bench/results')" ]; then SEA_DIRTY=yes; else SEA_DIRTY=no; fi
BSK_COMMIT=$(git -C "$BAYSICK" rev-parse HEAD 2>/dev/null) || fail "cannot read the Baysick commit in '$BAYSICK'"
if [ -n "$(git -C "$BAYSICK" status --porcelain -- . ':(exclude)sea')" ]; then BSK_DIRTY=yes; else BSK_DIRTY=no; fi
if [ "$MODE" = final ]; then
    [ "$POWER" = ac ] || fail "not on AC power (pmset -g batt); final mode refuses to measure on battery"
    [ "$LOWPOWER" = 0 ] || fail "Low Power Mode is on (pmset -g: lowpowermode $LOWPOWER)"
    [ "$SEA_DIRTY" = no ] || fail "the Sea working tree is not clean (git status --porcelain outside bench/results)"
    [ "$BSK_DIRTY" = no ] || fail "the Baysick working tree '$BAYSICK' is not clean (outside sea)"
    if [ -n "${PORTS:-}" ]; then
        [ -d "$PORTS" ] && [ "$(cd "$PORTS" && pwd -P)" = "$(cd "$ROOT/ports" && pwd -P)" ] \
            || fail "PORTS='$PORTS' overrides the ports; final mode accepts only the default $ROOT/ports"
    fi
    if [ -n "${KERNELS:-}" ]; then
        [ -d "$KERNELS" ] && [ "$(cd "$KERNELS" && pwd -P)" = "$(cd "$ROOT/bench/kernels" 2>/dev/null && pwd -P)" ] \
            || fail "KERNELS='$KERNELS' overrides the kernels; final mode accepts only the default $ROOT/bench/kernels"
    fi
fi
command -v uv >/dev/null 2>&1 || fail "uv not found"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/sea-numpy.XXXXXX") || fail "cannot create a temporary directory"
SCRATCH=$(cd "$SCRATCH" && pwd -P)
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT
trap 'cleanup; exit 2' HUP INT TERM PIPE

# the pinned NumPy, fetched before anything is measured
uv run --no-project --with "$PIN" python -c 'import numpy' </dev/null || fail "uv cannot provide $PIN"
mkdir -p "$OUT" || fail "cannot create '$OUT'"
# one attempt per tool, target and session (C2), before the start condition
if [ "$MODE" = final ] && ! mkdir "$OUT/.attempt-numpy-$TARGET" 2>/dev/null; then
    [ -d "$OUT/.attempt-numpy-$TARGET" ] && fail "already attempted in this session ('$OUT/.attempt-numpy-$TARGET' exists)"
    fail "cannot create '$OUT/.attempt-numpy-$TARGET'"
fi

# the start condition (final mode), then the load before the first measured process
if [ "$MODE" = final ]; then
    sh "$ROOT/bench/settle.sh" >"$SCRATCH/settle" || exit 2
    WAITED=$(sed -n 's/^settle_waited_s	//p' "$SCRATCH/settle")
    LBEFORE=$(sed -n 's/^load_before	//p' "$SCRATCH/settle")
    [ -n "$WAITED" ] && [ -n "$LBEFORE" ] || fail "bench/settle.sh printed no record lines"
    QARG=
else
    WAITED=-
    LBEFORE=$(loads)
    QARG=--quick
fi
mkdir "$SCRATCH/runs" || exit 2
# shellcheck disable=SC2086
(
    unset VECLIB_MAXIMUM_THREADS OPENBLAS_NUM_THREADS OMP_NUM_THREADS SEA_HEAP_CHECK BAYSICK_KERNELS SEA_KERNELS LC_ALL
    cd "$ROOT" && exec uv run --no-project --with "$PIN" python -I bench/numpy_time.py $QARG "$OUT" "$SCRATCH/runs" </dev/null
)
st=$?
case $st in
0) ;;
1) exit 1 ;;
*) fail "numpy_time.py ended with status $st" ;;
esac

info() { sed -n "s/^$1	//p" "$SCRATCH/runs/info.txt"; }
[ -s "$SCRATCH/runs/$TSV_F" ] || fail "numpy_time.py wrote no $TSV_F"
for k in tools numpy_blas numpy_threads load_after; do
    [ -n "$(info $k)" ] || fail "numpy_time.py wrote no '$k' line into info.txt"
done
{
    printf 'target\t%s\n' "$TARGET"
    printf 'mode\t%s\n' "$MODE"
    printf 'session\t%s\n' "$SESSION"
    printf 'date\t%s\n' "$DATE"
    printf 'machine_model\t%s\n' "$(sysctl -n hw.model)"
    printf 'cpu\t%s\n' "$(sysctl -n machdep.cpu.brand_string)"
    printf 'os\t%s\n' "macOS $(sw_vers -productVersion) ($(uname -sr))"
    printf 'sea_commit\t%s\n' "$SEA_COMMIT"
    printf 'sea_dirty\t%s\n' "$SEA_DIRTY"
    printf 'baysick_commit\t%s\n' "$BSK_COMMIT"
    printf 'baysick_dirty\t%s\n' "$BSK_DIRTY"
    printf 'nice\t%s\n' "$NICE"
    printf 'power\t%s\n' "$POWER"
    printf 'lowpower\t%s\n' "$LOWPOWER"
    printf 'variants\t-\n'
    printf 'tools\t%s\n' "$(info tools)"
    printf 'numpy_blas\t%s\n' "$(info numpy_blas)"
    printf 'numpy_threads\t%s\n' "$(info numpy_threads)"
    printf 'settle_waited_s\t%s\n' "$WAITED"
    printf 'load_before\t%s\n' "$LBEFORE"
    printf 'load_after\t%s\n' "$(info load_after)"
} >"$SCRATCH/$ENV_F" || fail "cannot write the machine record"
# both files complete before either is published
cp "$SCRATCH/runs/$TSV_F" "$OUT/.$TSV_F.tmp" && cp "$SCRATCH/$ENV_F" "$OUT/.$ENV_F.tmp" \
    || { rm -f "$OUT/.$TSV_F.tmp" "$OUT/.$ENV_F.tmp"; fail "cannot write into '$OUT'"; }
mv -f "$OUT/.$TSV_F.tmp" "$OUT/$TSV_F" && mv -f "$OUT/.$ENV_F.tmp" "$OUT/$ENV_F" || fail "cannot write into '$OUT'"
echo "numpy.sh: wrote $OUT/$TSV_F"
echo "numpy.sh: wrote $OUT/$ENV_F"
exit 0
