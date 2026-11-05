#!/bin/sh
# bench/workloads.sh -- the workload benchmark (DESIGN.md 6.5, 2.17.3, 2.17.4). POSIX sh, macOS.
#
# usage: sh bench/workloads.sh build|measure [--out DIR] [--quick] [--only NAMES]
#        sh bench/workloads.sh --cross [-H HOST] [--out DIR] [--quick] [--only NAMES]
#
#   build    builds build/bench/spawn_time (xcrun cc -O2 -ffp-contract=off) and each port, by the
#            command tests/accept.sh uses (`sea build NAME.sea -o build/bench/workloads/bin/NAME`
#            in PORTS, the prelude included) run through spawn_time, whose wall is the compile
#            time, kept in build/bench/workloads/compile.tsv; copies each port's `// fixture:`
#            files into build/bench/workloads/fix/NAME/. Measures nothing.
#   measure  builds nothing (a missing or stale build is a setup error); in final mode applies the
#            start condition (bench/settle.sh); runs bench/workloads/run.sh (15 runs per
#            workload; --quick: 1 + 1); then judges each run 1 with compare.py and
#            compare_report.py, keeps run 1 in build/bench/workloads/run1/, and writes
#            DIR/workloads-runs-arm64-macos.tsv, DIR/workloads-arm64-macos.tsv and
#            DIR/env-workloads-arm64-macos.txt.
#   --cross  compiles each port on the Mac with --target x86_64-linux -S, packs a bundle and runs
#            it with one `ssh -o BatchMode=yes` on HOST (-H, else $SEA_CROSS_HOST, else desktop),
#            whose remote script checks the host, builds (runtimes, links, spawn_time with gcc),
#            applies the start condition (final mode) and measures under the variants avx2 and
#            sse2. Its standard output holds exactly the three blocks of 2.17.4 (machine record,
#            TSV rows, `#sea-bench-files N` and the base64 tar of the run-1 files). Run 1 of each
#            workload and variant is judged on the Mac (compare.py, compare_report.py; and for
#            the ports without a `// cross: compare=accept` header line, W1 W4 W5 W7 W8, byte
#            equality with the Mac's kept run 1). Writes DIR/workloads-runs-x86_64-linux.tsv,
#            DIR/workloads-x86_64-linux.tsv and DIR/env-workloads-x86_64-linux.txt.
#   --out DIR      the results directory (default bench/results/p10); DIR/session.txt must exist
#                  (bench/session.sh) for measure and --cross
#   --quick        (also BENCH_QUICK=1) a smoke run: 1 + 1 runs, no start condition, records say
#                  `mode quick`; output files are overwritten. Final mode (the default) refuses
#                  an existing output file, a niced driver, battery power or Low Power Mode, a
#                  dirty Sea or Baysick tree, --only and a PORTS or KERNELS override.
#   --only NAMES   a comma-separated list of workload names (quick mode only)
#
# Build stamp (C1): build writes `sh bench/stamp.sh` into build/bench/workloads/stamp.txt;
# measure and --cross recompute it and refuse (exit 2, `stale build: ...`) when it differs.
# measure keeps run 1 with run1/stamp.txt (session and sea_commit); --cross refuses unless both
# equal DIR's session and the current commit. One attempt (C2): a final-mode measure or --cross
# creates DIR/.attempt-workloads-<target> before the start condition and refuses when it exists.
# Sessions (C3): a quick run refuses a DIR whose session.txt is a final session, a final run one
# whose session is quick. LC_ALL is C for this script, never for the measured processes (C4).
#
# Environment: PORTS (the ports, default ports/ of this repository; final mode: only the
# default), KERNELS (checked only: final mode requires the default bench/kernels), BAYSICK (the
# Baysick checkout, default the parent of this repository), SEA_CROSS_HOST.
# Exit status: 0 measured and validated (or built); 1 a validation failure (named, no file
# written); 2 a setup error (precondition, start condition, build failure, missing host, uv or
# fixture, an existing output file in final mode).

LC_ALL=C; export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SEA=$ROOT/build/sea
BAYSICK=${BAYSICK:-$(cd "$ROOT/.." && pwd)}
case $BAYSICK in /*) ;; *) BAYSICK=$(cd "$BAYSICK" 2>/dev/null && pwd) ;; esac
PORTS=${PORTS:-$ROOT/ports}
case $PORTS in /*) ;; *) PORTS=$(pwd)/$PORTS ;; esac
HOST=${SEA_CROSS_HOST:-desktop}
ALL="w1_shaft_design w2_truss_fem w3_quarter_car w4_heat_plate w5_tolerance_mc w7_drivetrain w8_ev_can"
BB=$ROOT/build/bench
WB=$BB/workloads

fail() { echo "workloads.sh: $1" >&2; exit 2; }
usage() { fail "usage: sh bench/workloads.sh build|measure [--out DIR] [--quick] [--only NAMES] | --cross [-H HOST] [--out DIR] [--quick] [--only NAMES]"; }

CMD=
OUT=$ROOT/bench/results/p10
QUICK=
[ "${BENCH_QUICK:-}" = 1 ] && QUICK=1
ONLY=
while [ $# -gt 0 ]; do
    case $1 in
    build | measure) [ -z "$CMD" ] || usage; CMD=$1; shift ;;
    --cross) [ -z "$CMD" ] || usage; CMD=cross; shift ;;
    --out) [ $# -ge 2 ] || usage; OUT=$2; shift 2 ;;
    --quick) QUICK=1; shift ;;
    --only) [ $# -ge 2 ] || usage; ONLY=$2; shift 2 ;;
    -H) [ $# -ge 2 ] || usage; HOST=$2; shift 2 ;;
    *) echo "workloads.sh: unknown argument '$1'" >&2; usage ;;
    esac
done
[ -n "$CMD" ] || usage
case $OUT in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
if [ -n "$QUICK" ]; then MODE=quick; else MODE=final; fi

NAMES=$ALL
if [ -n "$ONLY" ]; then
    [ "$MODE" = quick ] || fail "--only is refused in final mode (the pass check needs all seven workloads)"
    for n in $(echo "$ONLY" | tr ',' ' '); do
        case " $ALL " in *" $n "*) ;; *) fail "--only: unknown workload '$n' (known: $ALL)" ;; esac
    done
    NAMES=
    for n in $ALL; do
        case ",$ONLY," in *",$n,"*) NAMES="$NAMES $n" ;; esac
    done
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/sea-workloads.XXXXXX") || fail "cannot create a temporary directory"
TMP=$(cd "$TMP" && pwd -P)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 2' HUP INT TERM PIPE

DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# loads : the three load averages of uptime, separated by single spaces
loads() {
    uptime | sed -n 's/.*load average[s]*: *//p' | tr -d ',' | awk 'NF == 3 { print $1, $2, $3 }'
}

# ---- the output files and the session: a final-mode result file is never replaced (L-ps)
if [ "$CMD" = cross ]; then TARGET=x86_64-linux; else TARGET=arm64-macos; fi
RUNS_F=workloads-runs-$TARGET.tsv
SUM_F=workloads-$TARGET.tsv
ENV_F=env-workloads-$TARGET.txt
if [ "$MODE" = final ]; then
    for f in "$RUNS_F" "$SUM_F" "$ENV_F"; do
        [ ! -e "$OUT/$f" ] || fail "'$OUT/$f' exists; a final-mode result file is written once per session and never replaced"
    done
fi
SESSION=
if [ "$CMD" != build ]; then
    [ -f "$OUT/session.txt" ] || fail "'$OUT/session.txt' not found; create the session first (sh bench/session.sh DIR)"
    SESSION=$(head -1 "$OUT/session.txt")
    [ -n "$SESSION" ] || fail "'$OUT/session.txt' is empty"
fi
# a quick run never touches a final session's directory (C3), and a final run needs a final session
if [ -f "$OUT/session.txt" ]; then
    case $(head -1 "$OUT/session.txt") in
    quick-*) [ "$MODE" = quick ] || fail "'$OUT/session.txt' records a quick session; final mode needs a final session (sh bench/session.sh DIR)" ;;
    *) [ "$MODE" = final ] || fail "'$OUT/session.txt' records a final session; refusing to overwrite a final session with a quick run" ;;
    esac
fi

# ---- preconditions (2.17.3), before anything is built or measured -----------------------------
[ -x "$SEA" ] || fail "driver '$SEA' not found; run 'make' first"
NICE=$(ps -o nice= -p $$ | tr -d ' ')
[ "$MODE" = quick ] || [ "$NICE" = 0 ] || fail "the driver runs with nice value $NICE; final mode measures unniced (nice 0)"
POWER=-; LOWPOWER=-
if [ "$CMD" != cross ]; then
    [ "$(uname -sm)" = "Darwin arm64" ] || fail "run on an Apple-silicon Mac (or use --cross)"
fi
if [ "$(uname -s)" = Darwin ]; then
    case $(pmset -g batt | head -1) in
    *"AC Power"*) POWER=ac ;;
    *"Battery Power"*) POWER=battery ;;
    *) POWER=- ;;
    esac
    LOWPOWER=$(pmset -g | awk '$1 == "lowpowermode" { print $2; exit }')
    [ -n "$LOWPOWER" ] || LOWPOWER=0
    if [ "$MODE" = final ]; then
        [ "$POWER" = ac ] || fail "not on AC power (pmset -g batt); final mode refuses to measure on battery"
        [ "$LOWPOWER" = 0 ] || fail "Low Power Mode is on (pmset -g: lowpowermode $LOWPOWER)"
    fi
fi
SEA_COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || fail "cannot read the Sea commit"
if [ -n "$(git -C "$ROOT" status --porcelain -- . ':(exclude)bench/results')" ]; then SEA_DIRTY=yes; else SEA_DIRTY=no; fi
BSK_COMMIT=$(git -C "$BAYSICK" rev-parse HEAD 2>/dev/null) || fail "cannot read the Baysick commit in '$BAYSICK'"
if [ -n "$(git -C "$BAYSICK" status --porcelain -- . ':(exclude)sea')" ]; then BSK_DIRTY=yes; else BSK_DIRTY=no; fi
if [ "$MODE" = final ]; then
    [ "$SEA_DIRTY" = no ] || fail "the Sea working tree is not clean (git status --porcelain outside bench/results)"
    [ "$BSK_DIRTY" = no ] || fail "the Baysick working tree '$BAYSICK' is not clean (outside sea)"
    [ -d "$PORTS" ] && [ "$(cd "$PORTS" && pwd -P)" = "$(cd "$ROOT/ports" && pwd -P)" ] \
        || fail "PORTS='$PORTS' overrides the ports; final mode measures only the default $ROOT/ports"
    if [ -n "${KERNELS:-}" ]; then
        [ -d "$KERNELS" ] && [ "$(cd "$KERNELS" && pwd -P)" = "$(cd "$ROOT/bench/kernels" 2>/dev/null && pwd -P)" ] \
            || fail "KERNELS='$KERNELS' overrides the kernels; final mode accepts only the default $ROOT/bench/kernels"
    fi
fi
[ -d "$PORTS" ] || fail "ports directory '$PORTS' not found"


# port_fixtures SRC NAME : print the PATH of every `// fixture: PATH` line of SRC's leading
# comment block, one per line, by tests/accept.sh's rule (L-oo); a malformed line is a setup error
port_fixtures() {
    awk -v f="$1" -v nm="$2" '
    function bad(msg) { print "workloads.sh: " f ": line " FNR ": " msg > "/dev/stderr"; err = 1; exit }
    !/^\/\// { exit }
    /^\/\/[ \t]*fixture[ \t]*:/ {
        p = $0
        if (sub(/^\/\/ fixture: /, "", p) != 1 || p !~ /^[A-Za-z0-9._+-]+(\/[A-Za-z0-9._+-]+)*$/)
            bad("malformed fixture line '\''" $0 "'\'' (expected '\''// fixture: PATH'\'', PATH relative to the sea directory)")
        nc = split(p, comp, "/")
        for (i = 1; i <= nc; i++)
            if (comp[i] == "." || comp[i] == "..")
                bad("malformed fixture line '\''" $0 "'\'' (a '\''.'\'' or '\''..'\'' component in PATH)")
        if (p in seen) bad("fixture line '\''" $0 "'\'' repeated (first at line " seen[p] ")")
        b = comp[nc]
        if (b in base) bad("fixture '\''" p "'\'' has the same base name as fixture '\''" base[b] "'\''")
        if (b == nm || b == nm ".json" || b == "output")
            bad("fixture '\''" p "'\'' has the reserved base name '\''" b "'\''")
        seen[p] = FNR; base[b] = p
        print p
    }
    END { if (err) exit 2 }' "$1"
}

# check_ports : every selected port exists and its fixture lines are well formed and name
# regular files (setup errors, before anything is built)
check_ports() {
    for nm in $NAMES; do
        [ -f "$PORTS/$nm.sea" ] || fail "port '$PORTS/$nm.sea' not found"
        fx=$(port_fixtures "$PORTS/$nm.sea" "$nm") || exit 2
        for p in $fx; do
            [ -e "$ROOT/$p" ] || fail "$PORTS/$nm.sea: fixture source '$p' not found (in $ROOT)"
            [ -f "$ROOT/$p" ] || fail "$PORTS/$nm.sea: fixture source '$p' is not a regular file"
        done
    done
}

# newer SRC BUILT : true when SRC was modified after BUILT
newer() { [ -n "$(find "$1" -prune -newer "$2")" ]; }

# judge NAME DIR OUTFILE LABEL : run 1 judged as acceptance judges it (6.3): compare.py and
# compare_report.py both exit 0 (a failure is a validation failure, exit 1)
judge() {
    (cd "$ROOT" && uv run --no-project --with numpy python workloads/reference_py/compare.py \
        --candidate "$2" "$1") >"$TMP/cmp.out" 2>&1 \
        || { sed 's/^/    /' "$TMP/cmp.out" | grep -i 'fail\|error' | head -20 >&2
             echo "workloads.sh: validation failure: $1 ($4) run 1: compare.py failed" >&2; exit 1; }
    (cd "$ROOT" && uv run --no-project --with numpy python workloads/reference_py/compare_report.py \
        "$1" "$3" "$PORTS/$1.tokens" --candidate-json "$2/$1.json") >"$TMP/rep.out" 2>&1 \
        || { sed 's/^/    /' "$TMP/rep.out" | grep -i 'fail\|error' | head -20 >&2
             echo "workloads.sh: validation failure: $1 ($4) run 1: compare_report.py failed" >&2; exit 1; }
}

# write_env FILE TOOLS VARIANTS WAITED LOAD_BEFORE LOAD_AFTER : the Mac's machine record (2.17.3)
write_env() {
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
        printf 'variants\t%s\n' "$3"
        printf 'tools\t%s\n' "$2"
        printf 'settle_waited_s\t%s\n' "$4"
        printf 'load_before\t%s\n' "$5"
        printf 'load_after\t%s\n' "$6"
    } >"$1"
}

# publish SRC... : move the finished files (TMP/out/<name>) into OUT; every file is complete
# before the first one is moved
publish() {
    mkdir -p "$OUT" || fail "cannot create '$OUT'"
    for f in "$@"; do
        cp "$TMP/out/$f" "$OUT/.$f.tmp" || { rm -f "$OUT"/.*.tmp; fail "cannot write into '$OUT'"; }
    done
    for f in "$@"; do
        mv -f "$OUT/.$f.tmp" "$OUT/$f" || fail "cannot write '$OUT/$f'"
        echo "workloads.sh: wrote $OUT/$f"
    done
}

# ============================================================================== build ==========
if [ "$CMD" = build ]; then
    check_ports
    mkdir -p "$WB/bin" "$WB/fix" "$WB/compile" "$WB/run1" || fail "cannot create '$WB'"
    PORTS_REAL=$(cd "$PORTS" && pwd -P)
    if [ -f "$WB/ports.txt" ] && [ "$(cat "$WB/ports.txt")" != "$PORTS_REAL" ]; then
        # built from another ports directory before: nothing of that build is kept
        rm -rf "$WB/bin" "$WB/fix" "$WB/compile" "$WB/run1" "$WB/compile.tsv"
        mkdir -p "$WB/bin" "$WB/fix" "$WB/compile" "$WB/run1" || fail "cannot create '$WB'"
    fi
    printf '%s\n' "$PORTS_REAL" >"$WB/ports.txt" || fail "cannot write '$WB/ports.txt'"
    echo "workloads.sh: building $BB/spawn_time" >&2
    xcrun cc -O2 -ffp-contract=off -o "$BB/spawn_time" "$ROOT/bench/spawn_time.c" \
        || fail "building spawn_time.c failed"
    : >"$TMP/compile.tsv"
    for nm in $NAMES; do
        echo "workloads.sh: compiling $nm" >&2
        rm -f "$WB/bin/$nm" "$WB/run1/$nm.json" "$WB/run1/$nm.out"
        # the compiler runs without this script's LC_ALL (C4), as tests/accept.sh runs it
        (unset LC_ALL; exec "$BB/spawn_time" "$PORTS" "$WB/compile/$nm.out" "$WB/compile/$nm.err" -- \
            "$SEA" build "$nm.sea" -o "$WB/bin/$nm") >"$TMP/spawn" || fail "spawn_time failed compiling $nm"
        set -- $(cat "$TMP/spawn")
        if [ "${6:-}" != 0 ] || [ ! -x "$WB/bin/$nm" ]; then
            sed 's/^/    /' "$WB/compile/$nm.err" | head -20 >&2
            fail "compiling $nm failed (status ${6:-?})"
        fi
        printf '%s\t%s\n' "$nm" "$2" >>"$TMP/compile.tsv"
        rm -rf "$WB/fix/$nm"
        mkdir "$WB/fix/$nm" || fail "cannot create '$WB/fix/$nm'"
        for p in $(port_fixtures "$PORTS/$nm.sea" "$nm"); do
            cp "$ROOT/$p" "$WB/fix/$nm/" || fail "cannot copy fixture '$p'"
        done
        echo "workloads.sh: $nm compiled in $(awk -v w="$2" 'BEGIN { printf "%.3f", w }') s"
    done
    # keep the compile times of the ports not rebuilt now (--only)
    if [ -f "$WB/compile.tsv" ]; then
        awk -F '\t' 'NR == FNR { new[$1] = 1; next } !($1 in new)' "$TMP/compile.tsv" "$WB/compile.tsv" >>"$TMP/compile.tsv"
    fi
    cp "$TMP/compile.tsv" "$WB/compile.tsv" || fail "cannot write '$WB/compile.tsv'"
    # the build stamp (C1): measure and --cross refuse when the compiler pipeline changed since
    sh "$ROOT/bench/stamp.sh" >"$WB/stamp.txt" || { rm -f "$WB/stamp.txt"; fail "bench/stamp.sh failed"; }
    exit 0
fi

command -v uv >/dev/null 2>&1 || fail "uv not found (it runs compare.py and compare_report.py)"

# check_stamp : the build stamp of `build` equals the current one (C1), else a setup error
check_stamp() {
    [ -f "$WB/stamp.txt" ] || fail "stale build: '$WB/stamp.txt' missing; run 'sh bench/workloads.sh build' first"
    sh "$ROOT/bench/stamp.sh" >"$TMP/stamp.now" || fail "bench/stamp.sh failed"
    if ! cmp -s "$WB/stamp.txt" "$TMP/stamp.now"; then
        diff "$WB/stamp.txt" "$TMP/stamp.now" | sed -n 's/^[<>] /    /p' | head -10 >&2
        fail "stale build: the compiler pipeline or the trees changed since 'sh bench/workloads.sh build' (build/bench/workloads/stamp.txt differs); rebuild"
    fi
}

# attempt : final mode, one attempt per tool, target and session (C2); before the start condition
attempt() {
    [ "$MODE" = final ] || return 0
    mkdir -p "$OUT" || fail "cannot create '$OUT'"
    if ! mkdir "$OUT/.attempt-workloads-$TARGET" 2>/dev/null; then
        [ -d "$OUT/.attempt-workloads-$TARGET" ] && fail "already attempted in this session ('$OUT/.attempt-workloads-$TARGET' exists)"
        fail "cannot create '$OUT/.attempt-workloads-$TARGET'"
    fi
}

# ============================================================================== measure ========
if [ "$CMD" = measure ]; then
    # the build must be complete and fresh: measure builds nothing
    [ -x "$BB/spawn_time" ] || fail "'$BB/spawn_time' not built; run 'sh bench/workloads.sh build' first"
    newer "$ROOT/bench/spawn_time.c" "$BB/spawn_time" && fail "'$BB/spawn_time' is older than bench/spawn_time.c; rebuild"
    newer "$SEA" "$BB/spawn_time" && fail "'$BB/spawn_time' is older than build/sea; rebuild"
    [ -f "$WB/ports.txt" ] && [ "$(cat "$WB/ports.txt")" = "$(cd "$PORTS" && pwd -P)" ] \
        || fail "the ports were built from another directory than PORTS='$PORTS'; rebuild"
    [ -f "$WB/compile.tsv" ] || fail "'$WB/compile.tsv' missing; rebuild"
    for nm in $NAMES; do
        [ -x "$WB/bin/$nm" ] || fail "'$WB/bin/$nm' not built; run 'sh bench/workloads.sh build' first"
        newer "$PORTS/$nm.sea" "$WB/bin/$nm" && fail "'$WB/bin/$nm' is older than its source; rebuild"
        newer "$SEA" "$WB/bin/$nm" && fail "'$WB/bin/$nm' is older than build/sea; rebuild"
        awk -F '\t' -v n="$nm" '$1 == n { f = 1 } END { exit !f }' "$WB/compile.tsv" \
            || fail "no compile time of $nm in '$WB/compile.tsv'; rebuild"
        fx=$(port_fixtures "$PORTS/$nm.sea" "$nm") || exit 2
        : >"$TMP/fx"
        for p in $fx; do
            b=${p##*/}
            echo "$b" >>"$TMP/fx"
            [ -f "$WB/fix/$nm/$b" ] && cmp -s "$ROOT/$p" "$WB/fix/$nm/$b" \
                || fail "fixture '$WB/fix/$nm/$b' missing or not its source's copy; rebuild"
        done
        [ -d "$WB/fix/$nm" ] && [ "$(ls "$WB/fix/$nm" | sort)" = "$(sort "$TMP/fx")" ] \
            || fail "'$WB/fix/$nm' does not hold exactly the fixtures of $nm; rebuild"
    done
    check_stamp
    attempt
    # the start condition (final mode), then the load before the first measured process
    if [ "$MODE" = final ]; then
        sh "$ROOT/bench/settle.sh" >"$TMP/settle" || exit 2
        WAITED=$(sed -n 's/^settle_waited_s	//p' "$TMP/settle")
        LBEFORE=$(sed -n 's/^load_before	//p' "$TMP/settle")
        [ -n "$WAITED" ] && [ -n "$LBEFORE" ] || fail "bench/settle.sh printed no record lines"
    else
        WAITED=-
        LBEFORE=$(loads)
    fi
    mkdir "$TMP/w" || exit 2
    QARG=; [ "$MODE" = quick ] && QARG=--quick
    # shellcheck disable=SC2086
    sh "$ROOT/bench/workloads/run.sh" $QARG -c "$WB/compile.tsv" arm64-macos "$BB/spawn_time" "$WB/bin" "$WB/fix" "$TMP/w" $NAMES
    st=$?
    [ $st -eq 0 ] || exit $st
    LAFTER=$(cat "$TMP/w/load_after")
    # run 1 of every workload, judged after all the timed runs (L-oy)
    for nm in $NAMES; do
        echo "workloads.sh: judging run 1 of $nm" >&2
        judge "$nm" "$TMP/w/neon/$nm/r1" "$TMP/w/neon/$nm/r1.out" neon
    done
    # run 1 kept for the cross comparison, tied to this session and commit (run1/stamp.txt): run-1
    # files of another session or commit are removed first, so run1/ holds one measurement only
    printf 'session\t%s\nsea_commit\t%s\n' "$SESSION" "$SEA_COMMIT" >"$TMP/run1.stamp"
    if ! cmp -s "$TMP/run1.stamp" "$WB/run1/stamp.txt"; then
        rm -rf "$WB/run1" && mkdir "$WB/run1" || fail "cannot reset '$WB/run1'"
    fi
    for nm in $NAMES; do
        cp "$TMP/w/neon/$nm/r1/$nm.json" "$WB/run1/$nm.json" && cp "$TMP/w/neon/$nm/r1.out" "$WB/run1/$nm.out" \
            || fail "cannot keep run 1 of $nm in '$WB/run1'"
    done
    cp "$TMP/run1.stamp" "$WB/run1/stamp.txt" || fail "cannot write '$WB/run1/stamp.txt'"
    mkdir "$TMP/out" || exit 2
    cp "$TMP/w/runs.tsv" "$TMP/out/$RUNS_F" && cp "$TMP/w/summary.tsv" "$TMP/out/$SUM_F" || exit 2
    write_env "$TMP/out/$ENV_F" "$(xcrun cc --version 2>/dev/null | head -1)" neon "$WAITED" "$LBEFORE" "$LAFTER"
    publish "$RUNS_F" "$SUM_F" "$ENV_F"
    exit 0
fi

# ============================================================================== --cross ========
check_ports
# the Mac's kept run 1 (the class-E comparison below) must come from this session's Mac measurement
# at the current commit, made with the current build (C1, review finding 8)
check_stamp
[ -f "$WB/run1/stamp.txt" ] \
    || fail "'$WB/run1/stamp.txt' missing (the Mac measurement runs first: sh bench/workloads.sh measure)"
R1S=$(sed -n 's/^session	//p' "$WB/run1/stamp.txt")
R1C=$(sed -n 's/^sea_commit	//p' "$WB/run1/stamp.txt")
[ "$R1S" = "$SESSION" ] \
    || fail "the Mac's kept run 1 is from session '$R1S', not this session '$SESSION' (run sh bench/workloads.sh measure into '$OUT' first)"
[ "$R1C" = "$SEA_COMMIT" ] \
    || fail "the Mac's kept run 1 is from sea commit '$R1C', not the current $SEA_COMMIT (measure on the Mac again)"
for nm in $NAMES; do
    [ -f "$WB/run1/$nm.json" ] && [ -f "$WB/run1/$nm.out" ] \
        || fail "the Mac's run 1 of $nm is not in '$WB/run1' (the Mac measurement runs first: sh bench/workloads.sh measure)"
done
B=$TMP/bundle
mkdir -p "$B/sea/include" "$B/sea/runtime/x86_64_linux" "$B/baysick/include" \
    "$B/baysick/src/runtime_x86_64_linux" "$B/progs" "$B/fix" || exit 2
cp "$ROOT/Makefile.linux" "$B/sea/" && cp "$ROOT"/include/*.inc "$B/sea/include/" \
    && cp "$ROOT"/runtime/x86_64_linux/*.s "$B/sea/runtime/x86_64_linux/" || fail "cannot pack Sea's x86_64 runtime"
cp "$BAYSICK/Makefile.linux" "$B/baysick/" && cp "$BAYSICK"/include/*.inc "$B/baysick/include/" \
    && cp "$BAYSICK"/src/runtime_x86_64_linux/*.s "$B/baysick/src/runtime_x86_64_linux/" \
    || fail "cannot pack Baysick's x86_64 runtime"
for nm in $NAMES; do
    echo "workloads.sh: compiling $nm for x86_64-linux" >&2
    (cd "$PORTS" && "$SEA" build --target x86_64-linux -S -o "$B/progs/$nm.s" "$nm.sea") \
        || fail "compiling $nm for x86_64-linux failed"
    mkdir "$B/fix/$nm" || exit 2
    for p in $(port_fixtures "$PORTS/$nm.sea" "$nm"); do
        cp "$ROOT/$p" "$B/fix/$nm/" || fail "cannot copy fixture '$p'"
    done
done
cp "$ROOT/bench/spawn_time.c" "$ROOT/bench/settle.sh" "$B/" && cp "$ROOT/bench/workloads/run.sh" "$B/run.sh" || exit 2
{
    printf 'mode\t%s\n' "$MODE"
    printf 'session\t%s\n' "$SESSION"
    printf 'sea_commit\t%s\n' "$SEA_COMMIT"
    printf 'sea_dirty\t%s\n' "$SEA_DIRTY"
    printf 'baysick_commit\t%s\n' "$BSK_COMMIT"
    printf 'baysick_dirty\t%s\n' "$BSK_DIRTY"
    printf 'names\t%s\n' "$(echo $NAMES)"
} >"$B/mac.txt"

# The remote script travels in the bundle as remote.sh. Its standard output (fd 3 below) carries
# only the three blocks of 2.17.4; everything else goes to standard error.
cat >"$B/remote.sh" <<'REMOTE_END'
LC_ALL=C; export LC_ALL
exec 3>&1 1>&2
D=$(pwd)
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
die() { echo "remote: $1" >&2; exit 2; }
mac() { sed -n "s/^$1	//p" "$D/mac.txt"; }
MODE=$(mac mode)
NAMES=$(mac names)
loads() {
    uptime | sed -n 's/.*load average[s]*: *//p' | tr -d ',' | awk 'NF == 3 { print $1, $2, $3 }'
}
# the host's preconditions
NICE=$(ps -o nice= -p $$ | tr -d ' ')
[ "$MODE" = quick ] || [ "$NICE" = 0 ] || die "the remote script runs with nice value $NICE; final mode measures unniced"
grep -qw avx2 /proc/cpuinfo 2>/dev/null || die "the host does not list avx2 in /proc/cpuinfo's flags"
for t in as gcc make; do command -v $t >/dev/null 2>&1 || die "$t not found on the host"; done
# build: both runtimes, the links, the helper
make -C baysick -f Makefile.linux all >"$D/make.log" 2>&1 || { cat "$D/make.log" >&2; die "building Baysick's x86_64 runtime failed"; }
make -C sea -f Makefile.linux all BAYSICK=../baysick >"$D/make.log" 2>&1 || { cat "$D/make.log" >&2; die "building Sea's x86_64 runtime failed"; }
mkdir bin || exit 2
for nm in $NAMES; do
    as --64 -o progs/$nm.o progs/$nm.s || die "assembling $nm failed"
    gcc -no-pie -o bin/$nm progs/$nm.o sea/build-x86_64-linux/libsea.a baysick/build-x86_64-linux/libbaysickrt.a -lm \
        || die "linking $nm failed"
done
gcc -O2 -ffp-contract=off -o spawn_time spawn_time.c || die "building spawn_time.c failed"
# the start condition, then the measurement
if [ "$MODE" = final ]; then
    sh settle.sh >"$D/settle" || exit 2
    WAITED=$(sed -n 's/^settle_waited_s	//p' "$D/settle")
    LBEFORE=$(sed -n 's/^load_before	//p' "$D/settle")
    QARG=
else
    WAITED=-
    LBEFORE=$(loads)
    QARG=--quick
fi
mkdir w || exit 2
sh run.sh $QARG x86_64-linux "$D/spawn_time" "$D/bin" "$D/fix" "$D/w" $NAMES
st=$?
[ $st -eq 0 ] || exit $st
MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
[ -n "$MODEL" ] || MODEL=-
CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -1)
[ -n "$CPU" ] || CPU=-
{
    echo "@@SEA-BENCH-ENV-BEGIN@@"
    printf 'target\tx86_64-linux\n'
    printf 'mode\t%s\n' "$MODE"
    printf 'session\t%s\n' "$(mac session)"
    printf 'date\t%s\n' "$DATE"
    printf 'machine_model\t%s\n' "$MODEL"
    printf 'cpu\t%s\n' "$CPU"
    printf 'os\t%s\n' "$(uname -sr)"
    printf 'sea_commit\t%s\n' "$(mac sea_commit)"
    printf 'sea_dirty\t%s\n' "$(mac sea_dirty)"
    printf 'baysick_commit\t%s\n' "$(mac baysick_commit)"
    printf 'baysick_dirty\t%s\n' "$(mac baysick_dirty)"
    printf 'nice\t%s\n' "$NICE"
    printf 'power\t-\n'
    printf 'lowpower\t-\n'
    printf 'variants\tavx2 sse2\n'
    printf 'tools\t%s\n' "$(gcc --version | head -1)"
    printf 'settle_waited_s\t%s\n' "$WAITED"
    printf 'load_before\t%s\n' "$LBEFORE"
    printf 'load_after\t%s\n' "$(cat w/load_after)"
    echo "@@SEA-BENCH-ENV-END@@"
    echo "@@SEA-BENCH-TSV-BEGIN@@"
    cat w/runs.tsv w/summary.tsv
    echo "@@SEA-BENCH-TSV-END@@"
} >"$D/blocks" || exit 2
mkdir ret || exit 2
for v in avx2 sse2; do
    mkdir ret/$v || exit 2
    for nm in $NAMES; do
        cp w/$v/$nm/r1/$nm.json ret/$v/$nm.json && cp w/$v/$nm/r1.out ret/$v/$nm.out || die "cannot pack run 1 of $nm ($v)"
    done
done
tar -C ret -cf - . | base64 >"$D/files.b64" || die "cannot pack the run-1 files"
n=$(wc -c <"$D/files.b64" | tr -d ' ')
cat "$D/blocks" >&3 || exit 2
echo "#sea-bench-files $n" >&3
cat "$D/files.b64" >&3 || exit 2
exit 0
REMOTE_END

attempt
echo "workloads.sh: running on $HOST" >&2
REMOTE='d=$(mktemp -d "${TMPDIR:-/tmp}/sea-bench.XXXXXX") || exit 2; trap "rm -rf $d" EXIT; trap "rm -rf $d; exit 2" HUP INT TERM PIPE; tar -C $d -xf - || exit 2; cd $d || exit 2; sh remote.sh'
COPYFILE_DISABLE=1 tar --no-xattrs -C "$B" -cf - . | ssh -o BatchMode=yes -- "$HOST" "$REMOTE" >"$TMP/remote.out"
st=$?
case $st in
0) ;;
1) echo "workloads.sh: validation failure on $HOST" >&2; exit 1 ;;
255) fail "ssh to '$HOST' failed" ;;
2) fail "the remote run on $HOST stopped with a setup error" ;;
*) fail "the remote run on $HOST ended with status $st" ;;
esac

# the three blocks, in order, and nothing else
awk -v env="$TMP/env" -v tsv="$TMP/tsv" -v nf="$TMP/n" -v b64="$TMP/b64" '
function bad(m) { print "workloads.sh: remote output: " m > "/dev/stderr"; err = 1; exit 2 }
BEGIN { s = 0; printf "" > env; printf "" > tsv; printf "" > b64 }
s == 5 { print > b64; next }
$0 == "@@SEA-BENCH-ENV-BEGIN@@" { if (s != 0) bad("misplaced " $0); s = 1; next }
$0 == "@@SEA-BENCH-ENV-END@@" { if (s != 1) bad("misplaced " $0); s = 2; next }
$0 == "@@SEA-BENCH-TSV-BEGIN@@" { if (s != 2) bad("misplaced " $0); s = 3; next }
$0 == "@@SEA-BENCH-TSV-END@@" { if (s != 3) bad("misplaced " $0); s = 4; next }
/^#sea-bench-files [0-9]+$/ { if (s != 4) bad("misplaced " $0); print $2 > nf; s = 5; next }
s == 1 { print > env; next }
s == 3 { print > tsv; next }
{ bad("a line outside the blocks: " substr($0, 1, 80)) }
END { if (err) exit 2; if (s != 5) bad("missing block (stopped in state " s ")") }' "$TMP/remote.out" || exit 2
N=$(cat "$TMP/n")
GOT=$(wc -c <"$TMP/b64" | tr -d ' ')
[ "$GOT" = "$N" ] || fail "the run-1 files are $GOT bytes of base64, the host announced $N"
[ -s "$TMP/env" ] || fail "the host's machine record is empty"
awk -F '\t' '$1 == "target" { t = $2 } END { exit !(t == "x86_64-linux") }' "$TMP/env" \
    || fail "the host's machine record does not name the target x86_64-linux"

# the TSV block: the runs rows with their header, then the summary rows with theirs
RH=$(printf 'target\tvariant\tworkload\trun\twall_s\tcpu_s\tcompute_s\tstatus')
SH=$(printf 'target\tcpu\tvariant\tworkload\tcompile_s\tfirst_wall_s\tbest5_wall_s\tmedian5_wall_s\tmedian10_wall_s\tmin10_wall_s\tmax10_wall_s\tfirst_compute_s\tbest5_compute_s\tmedian5_compute_s\tmedian10_compute_s\tmin10_compute_s\tmax10_compute_s')
[ "$(head -1 "$TMP/tsv")" = "$RH" ] || fail "the TSV block does not start with the runs header"
[ "$(grep -c -x -F "$SH" "$TMP/tsv")" = 1 ] || fail "the TSV block does not hold exactly one summary header"
mkdir "$TMP/out" || exit 2
awk -v sh="$SH" -v r="$TMP/out/$RUNS_F" -v s="$TMP/out/$SUM_F" '$0 == sh { f = 1 } { print > (f ? s : r) }' "$TMP/tsv"
cp "$TMP/env" "$TMP/out/$ENV_F" || exit 2

# run 1 of each workload and variant, judged here
mkdir "$TMP/files" || exit 2
base64 -D <"$TMP/b64" >"$TMP/files.tar" || fail "cannot decode the run-1 files"
tar -C "$TMP/files" -xf "$TMP/files.tar" || fail "cannot unpack the run-1 files"
for nm in $NAMES; do
    classr=
    awk '!/^\/\// { exit } /^\/\/ cross: compare=accept( |$)/ { f = 1 } END { exit !f }' "$PORTS/$nm.sea" && classr=1
    for v in avx2 sse2; do
        R=$TMP/files/$v
        [ -f "$R/$nm.json" ] && [ -f "$R/$nm.out" ] || fail "the host returned no run 1 of $nm ($v)"
        echo "workloads.sh: judging run 1 of $nm ($v)" >&2
        judge "$nm" "$R" "$R/$nm.out" "$v"
        if [ -z "$classr" ]; then
            cmp -s "$R/$nm.json" "$WB/run1/$nm.json" \
                || { echo "workloads.sh: validation failure: $nm ($v) run 1: $nm.json differs from the Mac's run 1" >&2; exit 1; }
            grep -Ev '^Compute time: [0-9]+\.[0-9]{3} s$' "$R/$nm.out" >"$TMP/h.out"
            grep -Ev '^Compute time: [0-9]+\.[0-9]{3} s$' "$WB/run1/$nm.out" >"$TMP/m.out"
            cmp -s "$TMP/h.out" "$TMP/m.out" \
                || { echo "workloads.sh: validation failure: $nm ($v) run 1: standard output differs from the Mac's run 1 (Compute time line aside)" >&2; exit 1; }
        fi
    done
done
publish "$RUNS_F" "$SUM_F" "$ENV_F"
exit 0
