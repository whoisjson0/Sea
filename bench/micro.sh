#!/bin/sh
# bench/micro.sh -- the phase-5 micro-benchmarks (docs/DESIGN.md 5.9). POSIX sh, macOS.
#
# usage: sh bench/micro.sh [--cross [-H HOST]]
#   (no option)  build and measure on this Mac; writes bench/results/micro-arm64-macos.tsv
#   --cross      compile on the Mac for x86_64-linux, pack, measure on the Linux host over ssh
#                (default $SEA_CROSS_HOST, else desktop; -H HOST); writes
#                bench/results/micro-x86_64-linux.tsv
#
# Environment:
#   SEA      the phase-5 driver (default: build/sea of this repository)
#   SEA4     the phase-4 driver, REQUIRED: build/sea of the phase-4 compiler (sea commit a6bfeb9)
#            built in a scratch directory that is not committed, e.g.
#              git archive a6bfeb9 | tar -x -C SCRATCH/sea4 && make -C SCRATCH/sea4 BAYSICK=..
#   BAYSICK  the Baysick checkout (default: the parent of this repository)
#   SEA4_SRC the phase-4 source tree (default: the parent of the directory of SEA4); its
#            Makefile.linux, include/ and runtime/x86_64_linux/ go into the cross bundle
#   BENCH_MIN_REPS, BENCH_MIN_SECONDS   forwarded to bench/micro/run.sh (5, 1.0)
#
# The C references are built with `xcrun cc -O2 -ffp-contract=off` (Mac) and `gcc -O2
# -ffp-contract=off` (host). Each run is validated before it is timed (micro/run.sh); a failed
# validation stops the script with exit status 1 and writes no results file.
# Exit status: 0 done, 1 validation failure, 2 setup error.
#
# Phase 10 (docs/DESIGN.md 2.17.7): with --current the script is a different tool (the options
# above are not read; without --current everything above is exactly the 5d behaviour):
#   sh bench/micro.sh --current build|measure [--out DIR] [--quick]
#   sh bench/micro.sh --current --cross [-H HOST] [--out DIR] [--quick]
#   build     compile lcg.sea and sor.sea with build/sea and their C references into
#             build/bench/micro/ (Mac); measures nothing
#   measure   measure what `build` built (Mac): a setup error when a file is missing or older
#             than its source or than the driver
#   --cross   compile on the Mac, measure on the host in one ssh call (build and measure)
#   --out DIR (default bench/results/p10, relative to the Sea repository) holds session.txt (read)
#             and receives micro-TARGET.tsv and env-micro-TARGET.txt, only when every
#             measurement was measured and validated
#   --quick   (or BENCH_QUICK=1) smoke run: BENCH_MIN_SECONDS 0.2, no start condition, no
#             preconditions about niceness, power or a clean tree, existing outputs overwritten
# Compilers measured: p5 (build/sea, labelled sea-p10) and c; no SEA4 needed. Final mode (no
# --quick) refuses a niced run, a dirty tree, battery or low-power mode (Mac), an existing output
# file, and applies bench/settle.sh before the measurement. Exit status: 0, 1, 2 as above.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEA=${SEA:-$ROOT/build/sea}
BAYSICK=${BAYSICK:-$(cd "$ROOT/.." && pwd)}
HOST=${SEA_CROSS_HOST:-desktop}
CROSS=

# ---- --current: the phase-10 form (docs/DESIGN.md 2.17.7); exits at the end of this block
CURRENT=
for a in "$@"; do [ "$a" = --current ] && CURRENT=1; done
if [ -n "$CURRENT" ]; then
    LC_ALL=C; export LC_ALL   # for this script's own processing; measured processes get none
    cfail() { echo "micro.sh: $1" >&2; exit 2; }
    CMD=; OUTDIR=; QUICK=
    [ "${BENCH_QUICK:-}" = 1 ] && QUICK=1
    while [ $# -gt 0 ]; do
        case "$1" in
        --current) shift ;;
        --cross) CROSS=1; shift ;;
        --quick) QUICK=1; shift ;;
        -H) [ $# -ge 2 ] || cfail "missing argument for '-H'"; HOST=$2; shift 2 ;;
        --out) [ $# -ge 2 ] || cfail "missing argument for '--out'"; OUTDIR=$2; shift 2 ;;
        build | measure) [ -z "$CMD" ] || cfail "more than one command ('$CMD', '$1')"; CMD=$1; shift ;;
        *) cfail "unknown option '$1'" ;;
        esac
    done
    if [ -n "$CROSS" ]; then
        [ -z "$CMD" ] || cfail "--cross builds and measures in one run; it takes no command '$CMD'"
    else
        [ -n "$CMD" ] || cfail "usage: sh bench/micro.sh --current build|measure | --cross [options]"
    fi
    OUTDIR=${OUTDIR:-bench/results/p10}
    case $OUTDIR in /*) ;; *) OUTDIR=$ROOT/$OUTDIR ;; esac
    MODE=final; [ -n "$QUICK" ] && MODE=quick
    TARGET=arm64-macos; [ -n "$CROSS" ] && TARGET=x86_64-linux
    SRC=$ROOT/bench/micro
    BDIR=$ROOT/build/bench/micro
    TSVF=$OUTDIR/micro-$TARGET.tsv
    ENVF=$OUTDIR/env-micro-$TARGET.txt

    # ---- preconditions (2.17.3)
    [ -x "$SEA" ] || cfail "driver '$SEA' not found; run 'make' first"
    if [ -z "$CROSS" ]; then
        [ "$(uname -sm)" = "Darwin arm64" ] || cfail "run on an Apple-silicon Mac (or use --cross)"
    fi
    SEA_COMMIT=$(git -C "$ROOT" rev-parse HEAD) || cfail "cannot read the Sea commit"
    BAY_COMMIT=$(git -C "$BAYSICK" rev-parse HEAD) || cfail "cannot read the Baysick commit (BAYSICK=$BAYSICK)"
    SEA_DIRTY=no; BAY_DIRTY=no
    [ -z "$(git -C "$ROOT" status --porcelain -- . ':(exclude)bench/results')" ] || SEA_DIRTY=yes
    [ -z "$(git -C "$BAYSICK" status --porcelain -- . ':(exclude)sea')" ] || BAY_DIRTY=yes
    if [ "$MODE" = final ]; then
        for f in "$TSVF" "$ENVF"; do
            [ ! -e "$f" ] || cfail "output file '$f' already exists (final mode never replaces a result)"
        done
        [ "$(ps -o nice= -p $$ | tr -d ' ')" = 0 ] || cfail "this process is niced; the final mode needs nice value 0"
        [ "$SEA_DIRTY" = no ] || cfail "the Sea working tree is not clean (final mode)"
        [ "$BAY_DIRTY" = no ] || cfail "the Baysick working tree is not clean (final mode)"
        [ -z "${PORTS:-}" ] || [ "$PORTS" = "$ROOT/ports" ] || cfail "PORTS is set to a non-default value (final mode)"
        [ -z "${KERNELS:-}" ] || [ "$KERNELS" = "$ROOT/bench/kernels" ] || cfail "KERNELS is set to a non-default value (final mode)"
        if [ -z "$CROSS" ]; then
            pmset -g batt | head -1 | grep 'AC Power' >/dev/null || cfail "the Mac is not on AC power (final mode)"
            lp=$(pmset -g | awk '$1 == "lowpowermode" { print $2 }')
            [ -z "$lp" ] || [ "$lp" = 0 ] || cfail "Low Power Mode is on (final mode)"
        fi
    fi
    [ -f "$OUTDIR/session.txt" ] || cfail "'$OUTDIR/session.txt' not found; run 'sh bench/session.sh $OUTDIR' first"
    SESSION=$(cat "$OUTDIR/session.txt") && [ -n "$SESSION" ] || cfail "cannot read '$OUTDIR/session.txt'"
    [ -f "$ROOT/bench/stamp.sh" ] || cfail "bench/stamp.sh not found"
    if [ "$MODE" = final ]; then
        [ -f "$ROOT/bench/settle.sh" ] || cfail "bench/settle.sh not found"
        MINSECS=1.0; MINREPS=5
    else
        # a quick run never writes into a final session's directory
        case $SESSION in quick-*) ;; *) cfail "refusing to overwrite a final session ('$OUTDIR' holds session $SESSION)" ;; esac
        MINSECS=${BENCH_MIN_SECONDS:-0.2}; MINREPS=${BENCH_MIN_REPS:-5}
    fi

    # measured-process environment (2.17.3): no heap check, no forced kernel variant, one thread
    unset SEA_HEAP_CHECK BAYSICK_KERNELS SEA_KERNELS BENCH_MIN_REPS BENCH_MIN_SECONDS
    if [ -z "$CROSS" ]; then export VECLIB_MAXIMUM_THREADS=1; fi

    TMP=$(mktemp -d "${TMPDIR:-/tmp}/sea-micro.XXXXXX") || cfail "cannot create a temporary directory"
    cleanup() { rm -rf "$TMP"; }
    trap cleanup EXIT
    trap 'cleanup; exit 2' HUP INT TERM PIPE

    # settle: runs bench/settle.sh (stdout: settle_waited_s<TAB>N, load_before<TAB>a b c; progress
    # on stderr), sets WAITED
    settle() {
        sh "$ROOT/bench/settle.sh" >"$TMP/settle.out" || cfail "the start condition was not reached"
        WAITED=$(awk -F'\t' '$1 == "settle_waited_s" { print $2; exit }' "$TMP/settle.out")
        [ -n "$WAITED" ] || cfail "bench/settle.sh printed no settle_waited_s line"
    }
    # stamp FILE: the build stamp (bench/stamp.sh, C1)
    stamp() { sh "$ROOT/bench/stamp.sh" >"$1" || cfail "bench/stamp.sh failed"; }
    # attempt: one final-mode attempt per tool and session (C2)
    attempt() {
        [ "$MODE" = final ] || return 0
        mkdir "$OUTDIR/.attempt-micro-$TARGET" 2>/dev/null || cfail "already attempted in this session ('$OUTDIR/.attempt-micro-$TARGET' exists)"
    }

    # ---- Mac: build (the preconditions above apply to it as to measure)
    if [ -z "$CROSS" ] && [ "$CMD" = build ]; then
        mkdir -p "$BDIR" || cfail "cannot create $BDIR"
        for b in lcg sor; do
            "$SEA" build "$SRC/$b.sea" -o "$BDIR/$b.p5" || cfail "compile of $b.sea failed"
            xcrun cc -O2 -ffp-contract=off -o "$BDIR/$b.c" "$SRC/${b}_ref.c" -lm || cfail "C reference $b failed"
        done
        stamp "$BDIR/stamp.txt"
        exit 0
    fi

    # ---- Mac: measure
    if [ -z "$CROSS" ]; then
        for b in lcg sor; do
            for e in p5:"$b.sea" c:"${b}_ref.c"; do
                x=$BDIR/$b.${e%%:*}; s=$SRC/${e#*:}
                [ -x "$x" ] || cfail "$x not built; run 'sh bench/micro.sh --current build'"
                [ -z "$(find "$s" "$SEA" -newer "$x")" ] || cfail "$x is older than $s or the driver; run 'sh bench/micro.sh --current build'"
            done
        done
        [ -f "$BDIR/stamp.txt" ] || cfail "$BDIR/stamp.txt missing; run 'sh bench/micro.sh --current build'"
        stamp "$TMP/stamp.now"
        cmp -s "$BDIR/stamp.txt" "$TMP/stamp.now" || cfail "stale build: the compiler, runtime or commits changed since 'build'; run 'sh bench/micro.sh --current build'"
        attempt
        DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        WAITED=-
        [ "$MODE" = final ] && settle
        env -u LC_ALL MICRO_COMPILERS="p5 c" MICRO_SEA_LABEL=sea-p10 MICRO_RECORD=$TMP/env MICRO_MODE=$MODE \
            MICRO_SESSION=$SESSION MICRO_DATE=$DATE MICRO_SEA_COMMIT=$SEA_COMMIT MICRO_SEA_DIRTY=$SEA_DIRTY \
            MICRO_BAYSICK_COMMIT=$BAY_COMMIT MICRO_BAYSICK_DIRTY=$BAY_DIRTY MICRO_SETTLE_WAITED=$WAITED \
            BENCH_MIN_REPS=$MINREPS BENCH_MIN_SECONDS=$MINSECS \
            sh "$SRC/run.sh" arm64-macos "$BDIR" >"$TMP/tsv"
        st=$?
        if [ $st -ne 0 ]; then
            echo "micro.sh: the measurement ended with status $st; nothing written" >&2
            [ $st -eq 1 ] && exit 1
            exit 2
        fi
        cp "$TMP/tsv" "$TSVF" && cp "$TMP/env" "$ENVF" || cfail "cannot write the results into $OUTDIR"
        cat "$TSVF"
        exit 0
    fi

    # ---- cross: compile on the Mac, pack, one ssh call that builds, settles and measures
    attempt
    stamp "$TMP/stamp.before"
    B=$TMP/bundle
    mkdir -p "$B/progs" "$B/baysick/include" "$B/baysick/src/runtime_x86_64_linux" \
        "$B/sea/include" "$B/sea/runtime/x86_64_linux" || exit 2
    cp "$ROOT/Makefile.linux" "$B/sea/" && cp "$ROOT"/include/*.inc "$B/sea/include/" \
        && cp "$ROOT"/runtime/x86_64_linux/*.s "$B/sea/runtime/x86_64_linux/" || cfail "cannot pack the Sea runtime"
    cp "$BAYSICK/Makefile.linux" "$B/baysick/" && cp "$BAYSICK"/include/*.inc "$B/baysick/include/" \
        && cp "$BAYSICK"/src/runtime_x86_64_linux/*.s "$B/baysick/src/runtime_x86_64_linux/" \
        || cfail "cannot pack Baysick's runtime"
    for b in lcg sor; do
        "$SEA" build --target x86_64-linux -S -o "$B/progs/$b.p5.s" "$SRC/$b.sea" || cfail "compile of $b.sea failed"
        cp "$SRC/${b}_ref.c" "$B/progs/" || exit 2
    done
    cp "$SRC/run.sh" "$B/run.sh" || exit 2
    stamp "$TMP/stamp.after"
    cmp -s "$TMP/stamp.before" "$TMP/stamp.after" || cfail "stale build: the compiler or its inputs changed during the cross run"
    [ "$MODE" = final ] && { cp "$ROOT/bench/settle.sh" "$B/settle.sh" || exit 2; }
    DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat >"$B/vars.sh" <<VARS_END
MODE=$MODE
export MICRO_MODE=$MODE MICRO_SESSION=$SESSION MICRO_DATE=$DATE
export MICRO_SEA_COMMIT=$SEA_COMMIT MICRO_SEA_DIRTY=$SEA_DIRTY
export MICRO_BAYSICK_COMMIT=$BAY_COMMIT MICRO_BAYSICK_DIRTY=$BAY_DIRTY
export BENCH_MIN_REPS=$MINREPS BENCH_MIN_SECONDS=$MINSECS
VARS_END
    cat >"$B/remote.sh" <<'REMOTE_END'
. ./vars.sh
if [ "$MODE" = final ]; then
    [ "$(ps -o nice= -p $$ | tr -d ' ')" = 0 ] || { echo "remote: the remote script is niced (final mode)" >&2; exit 2; }
fi
for t in as gcc make; do
    command -v $t >/dev/null 2>&1 || { echo "remote: '$t' not found on the host" >&2; exit 2; }
done
grep -qw avx2 /proc/cpuinfo 2>/dev/null || { echo "remote: the host does not list avx2 in /proc/cpuinfo flags" >&2; exit 2; }
unset SEA_HEAP_CHECK BAYSICK_KERNELS SEA_KERNELS
export OPENBLAS_NUM_THREADS=1
make -C baysick -f Makefile.linux all >&2 || exit 2
make -C sea -f Makefile.linux all BAYSICK=../baysick >&2 || exit 2
mkdir bin || exit 2
for b in lcg sor; do
    as --64 -o progs/$b.p5.o progs/$b.p5.s || exit 2
    gcc -no-pie -o bin/$b.p5 progs/$b.p5.o sea/build-x86_64-linux/libsea.a baysick/build-x86_64-linux/libbaysickrt.a -lm || exit 2
    gcc -O2 -ffp-contract=off -o bin/$b.c progs/${b}_ref.c -lm || exit 2
done
WAITED=-
if [ "$MODE" = final ]; then
    sh settle.sh >settle.out 2>&1 || { cat settle.out >&2; exit 2; }
    cat settle.out >&2
    WAITED=$(sed -n 's/^settle_waited_s[[:space:]=]*//p' settle.out | head -1)
    [ -n "$WAITED" ] || { echo "remote: settle.sh printed no settle_waited_s line" >&2; exit 2; }
fi
MICRO_COMPILERS="p5 c" MICRO_SEA_LABEL=sea-p10 MICRO_RECORD=env.txt MICRO_SETTLE_WAITED=$WAITED \
    sh run.sh x86_64-linux bin >tsv.txt
st=$?
[ $st -eq 0 ] || exit $st
echo @@SEA-MICRO-ENV-BEGIN@@
cat env.txt
echo @@SEA-MICRO-ENV-END@@
echo @@SEA-MICRO-TSV-BEGIN@@
cat tsv.txt
echo @@SEA-MICRO-TSV-END@@
exit 0
REMOTE_END
    REMOTE='d=$(mktemp -d "${TMPDIR:-/tmp}/sea-micro.XXXXXX") || exit 2; trap "rm -rf $d" EXIT; trap "rm -rf $d; exit 2" HUP INT TERM PIPE; tar -C $d -xf - || exit 2; cd $d || exit 2; sh remote.sh'
    COPYFILE_DISABLE=1 tar --no-xattrs -C "$B" -cf - . | ssh -o BatchMode=yes -- "$HOST" "$REMOTE" >"$TMP/remote.out"
    st=$?
    if [ $st -ne 0 ]; then
        echo "micro.sh: remote run ended with status $st; nothing written" >&2
        [ $st -eq 1 ] && exit 1
        exit 2
    fi
    # exactly the two blocks, in order, and nothing else
    awk -v e="$TMP/env" -v t="$TMP/tsv" '
        s == 0 && $0 == "@@SEA-MICRO-ENV-BEGIN@@" { s = 1; next }
        s == 1 && $0 == "@@SEA-MICRO-ENV-END@@" { s = 2; next }
        s == 1 && /^@@/ { exit 1 }
        s == 1 { print > e; next }
        s == 2 && $0 == "@@SEA-MICRO-TSV-BEGIN@@" { s = 3; next }
        s == 3 && $0 == "@@SEA-MICRO-TSV-END@@" { s = 4; next }
        s == 3 && /^@@/ { exit 1 }
        s == 3 { print > t; next }
        { exit 1 }
        END { if (s != 4) exit 1 }' "$TMP/remote.out" || cfail "the remote output is not the ENV block then the TSV block"
    [ -s "$TMP/env" ] && [ -s "$TMP/tsv" ] || cfail "the remote ENV or TSV block is empty"
    [ "$(sed -n 1p "$TMP/tsv")" = "$(printf 'target\tcpu\tbench\tcompiler\treps\tmedian_s\tmin_s\tmax_s\tunit\trate')" ] \
        || cfail "the remote TSV has an unexpected header"
    [ "$(sed -n '2,$p' "$TMP/tsv" | wc -l | tr -d ' ')" = 4 ] || cfail "the remote TSV does not hold 4 rows"
    cp "$TMP/tsv" "$TSVF" && cp "$TMP/env" "$ENVF" || cfail "cannot write the results into $OUTDIR"
    cat "$TSVF"
    exit 0
fi
while [ $# -gt 0 ]; do
    case "$1" in
    --cross) CROSS=1; shift ;;
    -H) [ $# -ge 2 ] || { echo "micro.sh: missing argument for '-H'" >&2; exit 2; }; HOST=$2; shift 2 ;;
    *) echo "micro.sh: unknown option '$1'" >&2; exit 2 ;;
    esac
done
fail() { echo "micro.sh: $1" >&2; exit 2; }
[ -x "$SEA" ] || fail "driver '$SEA' not found; run 'make' first"
[ -n "${SEA4:-}" ] && [ -x "$SEA4" ] || fail "SEA4 (the phase-4 driver, see the header) is not set or not executable"
SEA4_SRC=${SEA4_SRC:-$(cd "$(dirname "$SEA4")/.." && pwd)}
SRC=$ROOT/bench/micro
OUT=$ROOT/bench/results
mkdir -p "$OUT" || fail "cannot create $OUT"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/sea-micro.XXXXXX") || fail "cannot create a temporary directory"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 2' HUP INT TERM PIPE

if [ -z "$CROSS" ]; then
    [ "$(uname -sm)" = "Darwin arm64" ] || fail "run on an Apple-silicon Mac (or use --cross)"
    mkdir "$TMP/bin" || exit 2
    for b in lcg sor; do
        "$SEA" build "$SRC/$b.sea" -o "$TMP/bin/$b.p5" || fail "phase-5 compile of $b.sea failed"
        "$SEA4" build "$SRC/$b.sea" -o "$TMP/bin/$b.p4" || fail "phase-4 compile of $b.sea failed"
        xcrun cc -O2 -ffp-contract=off -o "$TMP/bin/$b.c" "$SRC/${b}_ref.c" -lm || fail "C reference $b failed"
    done
    sh "$SRC/run.sh" arm64-macos "$TMP/bin" >"$TMP/tsv"
    st=$?
    [ $st -eq 0 ] || exit $st
    cp "$TMP/tsv" "$OUT/micro-arm64-macos.tsv" || fail "cannot write the results file"
    cat "$OUT/micro-arm64-macos.tsv"
    exit 0
fi

# ---- cross: compile on the Mac, pack, one ssh call that builds and measures on the host
B=$TMP/bundle
mkdir -p "$B/progs" "$B/baysick/include" "$B/baysick/src/runtime_x86_64_linux" || exit 2
for v in sea5:"$ROOT" sea4:"$SEA4_SRC"; do
    d=${v%%:*}; s=${v#*:}
    mkdir -p "$B/$d/include" "$B/$d/runtime/x86_64_linux" || exit 2
    cp "$s/Makefile.linux" "$B/$d/" && cp "$s"/include/*.inc "$B/$d/include/" \
        && cp "$s"/runtime/x86_64_linux/*.s "$B/$d/runtime/x86_64_linux/" || fail "cannot pack $s"
done
cp "$BAYSICK/Makefile.linux" "$B/baysick/" && cp "$BAYSICK"/include/*.inc "$B/baysick/include/" \
    && cp "$BAYSICK"/src/runtime_x86_64_linux/*.s "$B/baysick/src/runtime_x86_64_linux/" \
    || fail "cannot pack Baysick's runtime"
for b in lcg sor; do
    "$SEA" build --target x86_64-linux -S -o "$B/progs/$b.p5.s" "$SRC/$b.sea" || fail "phase-5 compile of $b.sea failed"
    "$SEA4" build --target x86_64-linux -S -o "$B/progs/$b.p4.s" "$SRC/$b.sea" || fail "phase-4 compile of $b.sea failed"
    cp "$SRC/${b}_ref.c" "$B/progs/" || exit 2
done
cp "$SRC/run.sh" "$B/run.sh" || exit 2

# The remote build-and-measure script travels in the bundle as remote.sh. The only command
# given to ssh is the short one below (no single quote in it); the directory it unpacks into
# is a mktemp -d directory removed on exit, so nothing is left on the host.
cat >"$B/remote.sh" <<'REMOTE_END'
set -e
make -C baysick -f Makefile.linux all >&2
for v in sea5 sea4; do
    make -C $v -f Makefile.linux all BAYSICK=../baysick >&2
done
mkdir bin
for b in lcg sor; do
    for c in p5 p4; do
        v=sea5; if [ $c = p4 ]; then v=sea4; fi
        as --64 -o progs/$b.$c.o progs/$b.$c.s
        gcc -no-pie -o bin/$b.$c progs/$b.$c.o $v/build-x86_64-linux/libsea.a baysick/build-x86_64-linux/libbaysickrt.a -lm
    done
    gcc -O2 -ffp-contract=off -o bin/$b.c progs/${b}_ref.c -lm
done
set +e
sh run.sh x86_64-linux bin
exit $?
REMOTE_END
REMOTE='d=$(mktemp -d "${TMPDIR:-/tmp}/sea-micro.XXXXXX") || exit 2; trap "rm -rf $d" EXIT; tar -C $d -xf - || exit 2; cd $d || exit 2; sh remote.sh'
COPYFILE_DISABLE=1 tar --no-xattrs -C "$B" -cf - . | ssh -o BatchMode=yes -- "$HOST" "$REMOTE" >"$TMP/tsv"
st=$?
if [ $st -ne 0 ]; then
    echo "micro.sh: remote run ended with status $st" >&2
    [ $st -eq 1 ] && exit 1
    exit 2
fi
cp "$TMP/tsv" "$OUT/micro-x86_64-linux.tsv" || fail "cannot write the results file"
cat "$OUT/micro-x86_64-linux.tsv"
exit 0
