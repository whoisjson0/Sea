#!/bin/sh
# bench/kernels.sh -- the Sea-level kernel benchmarks (docs/DESIGN.md 2.17.6, Decision 162). POSIX sh.
#
# usage: sh bench/kernels.sh build|measure [--out DIR] [--quick]        (Mac)
#        sh bench/kernels.sh --cross [-H HOST] [--out DIR] [--quick]    (Linux host over ssh)
#   build     compile gemm.sea, solve.sea, axpby.sea with build/sea and the C files vendor.c
#             (Accelerate), axpby_ref.c and expect.c with `xcrun cc -O2 -ffp-contract=off` into
#             build/bench/kernels/; measures nothing
#   measure   measure what `build` built: a setup error when a built file is missing, older than
#             its source or than build/sea, or built from another KERNELS directory; in final
#             mode bench/settle.sh first (the start condition, 2.17.3); then bench/kernels/run.sh
#   --cross   compile the Sea programs on the Mac (--target x86_64-linux -S), pack them with the
#             Sea and Baysick x86_64 runtimes, the C files and the runner, and run one
#             `ssh -o BatchMode=yes` whose remote script builds (runtimes, links, gcc with
#             OpenBLAS), checks the host's preconditions, applies the start condition (final
#             mode), measures and prints exactly two blocks on standard output: the host's
#             machine record between @@SEA-KERN-ENV-BEGIN@@ and @@SEA-KERN-ENV-END@@, then the
#             TSV between @@SEA-KERN-TSV-BEGIN@@ and @@SEA-KERN-TSV-END@@ (every validation
#             happens on the host, against expect built there); HOST: -H, else $SEA_CROSS_HOST,
#             else desktop
#   --out DIR (default bench/results/p10, relative to the Sea repository) holds session.txt (read)
#             and receives kernels-TARGET.tsv and env-kernels-TARGET.txt, only when every
#             measurement was measured and validated
#   --quick   (or BENCH_QUICK=1) smoke run: sizes gemm <= 512, solve <= 500, axpby <= 100 000,
#             0.2 s of timed calls per measurement, no start condition, no preconditions about
#             niceness, power or a clean tree, existing outputs overwritten; records `mode quick`;
#             refused when DIR holds a final session (a session.txt without the `quick-` prefix)
#
# Final mode checks every precondition of 2.17.3 before `build` as before `measure`. `build`
# writes `sh bench/stamp.sh` (commits, dirty flags, checksums of the compiler pipeline) to
# build/bench/kernels/stamp.txt; `measure` and `--cross` recompute it and stop with `stale build`
# (exit 2) when it differs, in both modes. A final-mode `measure` or `--cross` creates the marker
# directory DIR/.attempt-kernels-TARGET before the start condition and refuses (`already
# attempted in this session`) when it exists; the marker is never removed. The driver's own
# processing runs with LC_ALL=C; the measured processes get no LC_ALL (bench/kernels/run.sh).
#
# Environment:
#   KERNELS  the directory of the programs and C files (default bench/kernels of this repository;
#            in final mode only the default): an override for 10b's injected failures; the
#            runner bench/kernels/run.sh always comes from this repository
#   BAYSICK  the Baysick checkout (default: the parent of this repository)
#   SEA      the driver (default build/sea of this repository)
# Exit status: 0 measured and validated (or built); 1 a validation failure; 2 a setup error
# (precondition, start condition, build failure, missing host, `kernels: OpenBLAS not found on
# HOST`, an existing output file in final mode, a malformed remote output).

LC_ALL=C; export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAMP=$ROOT/bench/stamp.sh
SEA=${SEA:-$ROOT/build/sea}
BAYSICK=${BAYSICK:-$(cd "$ROOT/.." && pwd)}
HOST=${SEA_CROSS_HOST:-desktop}
DEFK=$ROOT/bench/kernels
K=${KERNELS:-$DEFK}
RUNNER=$ROOT/bench/kernels/run.sh
BDIR=$ROOT/build/bench/kernels
PROGS="gemm solve axpby"

fail() { echo "kernels.sh: $1" >&2; exit 2; }

CMD=; CROSS=; OUTDIR=; QUICK=
[ "${BENCH_QUICK:-}" = 1 ] && QUICK=1
while [ $# -gt 0 ]; do
    case "$1" in
    --cross) CROSS=1; shift ;;
    --quick) QUICK=1; shift ;;
    -H) [ $# -ge 2 ] || fail "missing argument for '-H'"; HOST=$2; shift 2 ;;
    --out) [ $# -ge 2 ] || fail "missing argument for '--out'"; OUTDIR=$2; shift 2 ;;
    build | measure) [ -z "$CMD" ] || fail "more than one command ('$CMD', '$1')"; CMD=$1; shift ;;
    *) fail "unknown option '$1'" ;;
    esac
done
if [ -n "$CROSS" ]; then
    [ -z "$CMD" ] || fail "--cross builds and measures in one run; it takes no command '$CMD'"
else
    [ -n "$CMD" ] || fail "usage: sh bench/kernels.sh build|measure [--out DIR] [--quick] | --cross [-H HOST] [--out DIR] [--quick]"
fi
OUTDIR=${OUTDIR:-bench/results/p10}
case $OUTDIR in /*) ;; *) OUTDIR=$ROOT/$OUTDIR ;; esac
case $K in /*) ;; *) K=$(pwd)/$K ;; esac
MODE=final; [ -n "$QUICK" ] && MODE=quick
TARGET=arm64-macos; [ -n "$CROSS" ] && TARGET=x86_64-linux
TSVF=$OUTDIR/kernels-$TARGET.tsv
ENVF=$OUTDIR/env-kernels-$TARGET.txt

# ---- preconditions (2.17.3), before anything is built or measured
[ -x "$SEA" ] || fail "driver '$SEA' not found; run 'make' first"
if [ -z "$CROSS" ]; then
    [ "$(uname -sm)" = "Darwin arm64" ] || fail "run on an Apple-silicon Mac (or use --cross)"
fi
for f in $PROGS; do [ -f "$K/$f.sea" ] || fail "'$K/$f.sea' not found (KERNELS=$K)"; done
for f in vendor axpby_ref expect; do [ -f "$K/$f.c" ] || fail "'$K/$f.c' not found (KERNELS=$K)"; done
[ -f "$RUNNER" ] || fail "'$RUNNER' not found"
NICE=$(ps -o nice= -p $$ | tr -d ' ')
SEA_COMMIT=$(git -C "$ROOT" rev-parse HEAD) || fail "cannot read the Sea commit"
BAY_COMMIT=$(git -C "$BAYSICK" rev-parse HEAD) || fail "cannot read the Baysick commit (BAYSICK=$BAYSICK)"
SEA_DIRTY=no; BAY_DIRTY=no
[ -z "$(git -C "$ROOT" status --porcelain -- . ':(exclude)bench/results')" ] || SEA_DIRTY=yes
[ -z "$(git -C "$BAYSICK" status --porcelain -- . ':(exclude)sea')" ] || BAY_DIRTY=yes
# quick mode never touches a final session's directory (a final session id has no `quick-` prefix)
if [ "$MODE" = quick ] && [ -f "$OUTDIR/session.txt" ]; then
    case $(head -1 "$OUTDIR/session.txt") in
    quick-*) ;;
    *) fail "refusing to overwrite a final session ('$OUTDIR' holds a final session; quick mode)" ;;
    esac
fi
# final mode: every precondition before building (C6) as before measuring; quick build needs none
if [ "$MODE" = final ] || [ "$CMD" != build ]; then
    if [ "$MODE" = final ]; then
        for f in "$TSVF" "$ENVF"; do
            [ ! -e "$f" ] || fail "output file '$f' already exists (final mode never replaces a result)"
        done
        [ "$NICE" = 0 ] || fail "this process is niced ($NICE); the final mode needs nice value 0"
        [ "$SEA_DIRTY" = no ] || fail "the Sea working tree is not clean (final mode)"
        [ "$BAY_DIRTY" = no ] || fail "the Baysick working tree is not clean (final mode)"
        [ -z "${PORTS:-}" ] || [ "$PORTS" = "$ROOT/ports" ] || fail "PORTS is set to a non-default value (final mode)"
        [ "$K" = "$DEFK" ] || fail "KERNELS is set to a non-default value (final mode)"
        if [ -z "$CROSS" ]; then
            pmset -g batt | head -1 | grep 'AC Power' >/dev/null || fail "the Mac is not on AC power (final mode)"
            lp=$(pmset -g | awk '$1 == "lowpowermode" { print $2 }')
            [ -z "$lp" ] || [ "$lp" = 0 ] || fail "Low Power Mode is on (final mode)"
        fi
        [ -f "$ROOT/bench/settle.sh" ] || fail "bench/settle.sh not found"
    fi
    [ -f "$OUTDIR/session.txt" ] || fail "'$OUTDIR/session.txt' not found; run 'sh bench/session.sh $OUTDIR' first"
    SESSION=$(head -1 "$OUTDIR/session.txt") && [ -n "$SESSION" ] || fail "cannot read '$OUTDIR/session.txt'"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/sea-kern.XXXXXX") || fail "cannot create a temporary directory"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 2' HUP INT TERM PIPE

# ---------------------------------------------------------------- Mac: build
if [ "$CMD" = build ]; then
    mkdir -p "$BDIR" || fail "cannot create $BDIR"
    rm -f "$BDIR/KERNELS" "$BDIR/stamp.txt"
    for p in $PROGS; do
        "$SEA" build "$K/$p.sea" -o "$BDIR/$p" || fail "compile of $p.sea failed"
    done
    xcrun cc -O2 -ffp-contract=off -DACCELERATE_NEW_LAPACK -o "$BDIR/vendor" "$K/vendor.c" -framework Accelerate ||
        fail "build of vendor.c failed"
    xcrun cc -O2 -ffp-contract=off -o "$BDIR/axpby_ref" "$K/axpby_ref.c" || fail "build of axpby_ref.c failed"
    xcrun cc -O2 -ffp-contract=off -o "$BDIR/expect" "$K/expect.c" || fail "build of expect.c failed"
    # the source directory of this build, so `measure` never measures another directory's programs
    printf '%s\n' "$K" >"$BDIR/KERNELS" || fail "cannot write $BDIR/KERNELS"
    # the build stamp (C1): commits, dirty flags and checksums of the compiler pipeline
    sh "$STAMP" >"$BDIR/stamp.txt" || { rm -f "$BDIR/stamp.txt"; fail "bench/stamp.sh failed"; }
    echo "kernels.sh: built into $BDIR" >&2
    exit 0
fi

# check_stamp: the build stamp of `build` must equal the current one (C1), in both modes
check_stamp() {
    [ -f "$BDIR/stamp.txt" ] || fail "stale build: $BDIR/stamp.txt missing; run 'sh bench/kernels.sh build'"
    sh "$STAMP" >"$TMP/stamp.now" || fail "bench/stamp.sh failed"
    cmp -s "$BDIR/stamp.txt" "$TMP/stamp.now" ||
        fail "stale build: the compiler, runtimes or commits changed since 'sh bench/kernels.sh build'"
}

# attempt: one final-mode attempt per tool, target and session (C2); the marker is never removed
attempt() {
    [ "$MODE" = final ] || return 0
    mkdir "$OUTDIR/.attempt-kernels-$1" 2>/dev/null ||
        fail "already attempted in this session ($OUTDIR/.attempt-kernels-$1 exists)"
}

# settle: the start condition (final mode); sets WAITED
settle() {
    sh "$1" >"$TMP/settle.out" 2>&1 || { cat "$TMP/settle.out" >&2; fail "the start condition was not reached"; }
    cat "$TMP/settle.out" >&2
    WAITED=$(sed -n 's/^settle_waited_s[[:space:]=]*//p' "$TMP/settle.out" | head -1)
    [ -n "$WAITED" ] || fail "bench/settle.sh printed no settle_waited_s line"
}

# ---------------------------------------------------------------- Mac: measure
if [ -z "$CROSS" ]; then
    [ -f "$BDIR/KERNELS" ] && [ "$(cat "$BDIR/KERNELS")" = "$K" ] ||
        fail "$BDIR was not built from $K; run 'sh bench/kernels.sh build'"
    for e in gemm:gemm.sea solve:solve.sea axpby:axpby.sea vendor:vendor.c axpby_ref:axpby_ref.c expect:expect.c; do
        x=$BDIR/${e%%:*}; s=$K/${e#*:}
        [ -x "$x" ] || fail "$x not built; run 'sh bench/kernels.sh build'"
        [ -z "$(find "$s" "$SEA" -newer "$x")" ] || fail "$x is older than $s or the driver; run 'sh bench/kernels.sh build'"
    done
    check_stamp
    attempt arm64-macos
    DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    WAITED=-
    [ "$MODE" = final ] && settle "$ROOT/bench/settle.sh"
    BENCH_QUICK= ; [ "$MODE" = quick ] && BENCH_QUICK=1
    export BENCH_QUICK
    sh "$RUNNER" measure arm64-macos "$BDIR" "$TMP/loads" >"$TMP/tsv"
    st=$?
    if [ $st -ne 0 ]; then
        echo "kernels.sh: the measurement ended with status $st; nothing written" >&2
        [ $st -eq 1 ] && exit 1
        exit 2
    fi
    KR_TARGET=arm64-macos KR_MODE=$MODE KR_SESSION=$SESSION KR_DATE=$DATE KR_SEA_COMMIT=$SEA_COMMIT \
        KR_SEA_DIRTY=$SEA_DIRTY KR_BAYSICK_COMMIT=$BAY_COMMIT KR_BAYSICK_DIRTY=$BAY_DIRTY KR_NICE=$NICE \
        KR_VARIANTS=neon KR_SETTLE_WAITED=$WAITED KR_LOADS=$TMP/loads \
        sh "$RUNNER" record "$TMP/env" || fail "cannot write the machine record"
    if [ "$MODE" = final ]; then
        for f in "$TSVF" "$ENVF"; do
            [ ! -e "$f" ] || fail "output file '$f' appeared during the measurement; nothing written"
        done
    fi
    cp "$TMP/tsv" "$TSVF" && cp "$TMP/env" "$ENVF" || { rm -f "$TSVF" "$ENVF"; fail "cannot write the results into $OUTDIR"; }
    cat "$TSVF"
    exit 0
fi

# ---------------------------------------------------------------- cross
for f in "$BAYSICK/Makefile.linux" "$ROOT/Makefile.linux"; do [ -f "$f" ] || fail "'$f' not found"; done
check_stamp
attempt x86_64-linux
B=$TMP/bundle
mkdir -p "$B/progs" "$B/baysick/include" "$B/baysick/src/runtime_x86_64_linux" \
    "$B/sea/include" "$B/sea/runtime/x86_64_linux" || exit 2
cp "$ROOT/Makefile.linux" "$B/sea/" && cp "$ROOT"/include/*.inc "$B/sea/include/" \
    && cp "$ROOT"/runtime/x86_64_linux/*.s "$B/sea/runtime/x86_64_linux/" || fail "cannot pack the Sea runtime"
cp "$BAYSICK/Makefile.linux" "$B/baysick/" && cp "$BAYSICK"/include/*.inc "$B/baysick/include/" \
    && cp "$BAYSICK"/src/runtime_x86_64_linux/*.s "$B/baysick/src/runtime_x86_64_linux/" \
    || fail "cannot pack Baysick's runtime"
for p in $PROGS; do
    "$SEA" build --target x86_64-linux -S -o "$B/progs/$p.s" "$K/$p.sea" || fail "compile of $p.sea failed"
done
cp "$K/vendor.c" "$K/axpby_ref.c" "$K/expect.c" "$B/progs/" && cp "$RUNNER" "$B/run.sh" || fail "cannot pack the C files"
if [ "$MODE" = final ]; then cp "$ROOT/bench/settle.sh" "$B/settle.sh" || fail "cannot pack settle.sh"; fi
{
    printf 'KR_TARGET=x86_64-linux\nKR_MODE=%s\nKR_SESSION=%s\nKR_SEA_COMMIT=%s\nKR_SEA_DIRTY=%s\n' \
        "$MODE" "$SESSION" "$SEA_COMMIT" "$SEA_DIRTY"
    printf 'KR_BAYSICK_COMMIT=%s\nKR_BAYSICK_DIRTY=%s\n' "$BAY_COMMIT" "$BAY_DIRTY"
} >"$B/facts" || exit 2

# The remote script travels in the bundle; ssh is given only the short command below (no single
# quote in it), which unpacks into a mktemp -d directory removed on exit. Its progress goes to
# standard error; its standard output is exactly the two blocks. Exit 3 = OpenBLAS not found.
cat >"$B/remote.sh" <<'REMOTE_END'
LC_ALL=C; export LC_ALL
. ./facts
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NICE=$(ps -o nice= -p $$ | tr -d ' ')
rfail() { echo "remote: $1" >&2; exit 2; }
if [ "$KR_MODE" = final ]; then
    [ "$NICE" = 0 ] || rfail "the remote script is niced ($NICE); the final mode needs nice value 0"
fi
grep -q '^flags.* avx2' /proc/cpuinfo || rfail "this host does not offer AVX2"
for t in as gcc make; do command -v $t >/dev/null 2>&1 || rfail "'$t' not found"; done
make -C baysick -f Makefile.linux all >&2 || rfail "build of Baysick's runtime failed"
make -C sea -f Makefile.linux all BAYSICK=../baysick >&2 || rfail "build of Sea's runtime failed"
mkdir bin || exit 2
for p in gemm solve axpby; do
    as --64 -o progs/$p.o progs/$p.s || rfail "assembly of $p failed"
    gcc -no-pie -o bin/$p progs/$p.o sea/build-x86_64-linux/libsea.a baysick/build-x86_64-linux/libbaysickrt.a -lm ||
        rfail "link of $p failed"
done
# OpenBLAS with its own cblas.h (openblas_get_config); never the reference BLAS
OK=
for cand in "$(pkg-config --cflags-only-I openblas 2>/dev/null)" /usr/include/openblas \
    /usr/include/x86_64-linux-gnu/openblas-pthread /usr/include/openblas-base ""; do
    case "$cand" in -I*) flag=$cand ;; "") flag= ;; *) [ -d "$cand" ] && flag="-I$cand" || continue ;; esac
    if gcc -O2 -ffp-contract=off $flag -o bin/vendor progs/vendor.c -lopenblas -lm >&2 2>&1 && ./bin/vendor config >&2; then
        OK=1; break
    fi
done
[ -n "$OK" ] || { echo "remote: no usable OpenBLAS" >&2; exit 3; }
gcc -O2 -ffp-contract=off -o bin/axpby_ref progs/axpby_ref.c || rfail "build of axpby_ref.c failed"
gcc -O2 -ffp-contract=off -o bin/expect progs/expect.c || rfail "build of expect.c failed"
WAITED=-
if [ "$KR_MODE" = final ]; then
    sh settle.sh >settle.out 2>&1 || { cat settle.out >&2; rfail "the start condition was not reached"; }
    cat settle.out >&2
    WAITED=$(sed -n 's/^settle_waited_s[[:space:]=]*//p' settle.out | head -1)
    [ -n "$WAITED" ] || rfail "settle.sh printed no settle_waited_s line"
fi
BENCH_QUICK=; [ "$KR_MODE" = quick ] && BENCH_QUICK=1
export BENCH_QUICK
sh run.sh measure x86_64-linux bin loads >tsv
st=$?
[ $st -eq 0 ] || exit $st
KR_DATE=$DATE KR_NICE=$NICE KR_VARIANTS="avx2 sse2" KR_SETTLE_WAITED=$WAITED KR_LOADS=loads \
    KR_TARGET=$KR_TARGET KR_MODE=$KR_MODE KR_SESSION=$KR_SESSION KR_SEA_COMMIT=$KR_SEA_COMMIT \
    KR_SEA_DIRTY=$KR_SEA_DIRTY KR_BAYSICK_COMMIT=$KR_BAYSICK_COMMIT KR_BAYSICK_DIRTY=$KR_BAYSICK_DIRTY \
    sh run.sh record env || exit 2
echo @@SEA-KERN-ENV-BEGIN@@
cat env
echo @@SEA-KERN-ENV-END@@
echo @@SEA-KERN-TSV-BEGIN@@
cat tsv
echo @@SEA-KERN-TSV-END@@
exit 0
REMOTE_END
REMOTE='d=$(mktemp -d "${TMPDIR:-/tmp}/sea-kern.XXXXXX") || exit 2; trap "rm -rf $d" EXIT; trap "rm -rf $d; exit 2" HUP INT TERM PIPE; tar -C $d -xf - || exit 2; cd $d || exit 2; sh remote.sh'
COPYFILE_DISABLE=1 tar --no-xattrs -C "$B" -cf - . | ssh -o BatchMode=yes -- "$HOST" "$REMOTE" >"$TMP/remote.out"
st=$?
case $st in
0) ;;
1) echo "kernels.sh: validation failure on $HOST; nothing written" >&2; exit 1 ;;
3) fail "OpenBLAS not found on $HOST" ;;
*) fail "remote run on $HOST ended with status $st; nothing written" ;;
esac

# split the remote output: exactly the two blocks, in order, and nothing else
awk -v env="$TMP/env" -v tsv="$TMP/tsv" '
    function bad(m) { print "kernels.sh: malformed remote output: " m > "/dev/stderr"; err = 1; exit 2 }
    {
        if (st == 0) { if ($0 != "@@SEA-KERN-ENV-BEGIN@@") bad("line " NR " is not @@SEA-KERN-ENV-BEGIN@@"); st = 1; next }
        if (st == 1) { if ($0 == "@@SEA-KERN-ENV-END@@") { st = 2; next }
                       if ($0 ~ /^@@/) bad("unexpected marker in the ENV block"); print > env; ne++; next }
        if (st == 2) { if ($0 != "@@SEA-KERN-TSV-BEGIN@@") bad("line " NR " is not @@SEA-KERN-TSV-BEGIN@@"); st = 3; next }
        if (st == 3) { if ($0 == "@@SEA-KERN-TSV-END@@") { st = 4; next }
                       if ($0 ~ /^@@/) bad("unexpected marker in the TSV block"); print > tsv; nt++; next }
        bad("text after @@SEA-KERN-TSV-END@@")
    }
    END {
        if (err) exit 2
        if (st != 4) bad("missing block (state " st ")")
        if (ne < 1 || nt < 2) bad("empty block")
    }' "$TMP/remote.out" || exit 2
head -1 "$TMP/tsv" | grep -q '^target	cpu	kernel	impl	variant	n	reps	batch	median_s	min_s	max_s	unit	rate	pct_vendor$' ||
    fail "the remote TSV has another header"
[ "$(sed -n 's/^target	//p' "$TMP/env")" = x86_64-linux ] || fail "the remote machine record names another target"
if [ "$MODE" = final ]; then
    for f in "$TSVF" "$ENVF"; do
        [ ! -e "$f" ] || fail "output file '$f' appeared during the measurement; nothing written"
    done
fi
cp "$TMP/tsv" "$TSVF" && cp "$TMP/env" "$ENVF" || { rm -f "$TSVF" "$ENVF"; fail "cannot write the results into $OUTDIR"; }
cat "$TSVF"
exit 0
