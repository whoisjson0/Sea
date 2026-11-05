#!/bin/sh
# bench/micro/run.sh -- measure built micro-benchmark executables (docs/DESIGN.md 5.9). POSIX sh.
# Run by bench/micro.sh on the Mac and, from the unpacked bundle, on the Linux host.
#
# usage: sh run.sh TARGET DIR
#   TARGET  arm64-macos | x86_64-linux (the first TSV column)
#   DIR     holds the executables  lcg.p5 lcg.p4 lcg.c sor.p5 sor.p4 sor.c  (p5 = Sea compiled by
#           the phase-5 compiler, p4 = by the phase-4 compiler, c = the C reference)
#
# Per executable: validation first (every output checked; a failing check is an error, exit 1,
# no row), one untimed warm-up run, then repetitions (one process each; the program times its
# own kernel with a monotonic clock and prints `seconds`) until at least 5 repetitions and 1.0 s
# of total timed seconds, at most 200. Output on stdout: the TSV (header
# `target cpu bench compiler reps median_s min_s max_s unit rate`); the machine record on stderr.
# Environment: BENCH_MIN_REPS (5), BENCH_MIN_SECONDS (1.0).
# Exit status: 0 all rows written, 1 a validation failure, 2 setup error.
#
# Phase 10 (docs/DESIGN.md 2.17.7), all optional; unset, the behaviour above is unchanged:
#   MICRO_COMPILERS   the compilers measured, in order, from p5 p4 c (default "p5 p4 c"); DIR need
#                     hold only those executables
#   MICRO_SEA_LABEL   the `compiler` column of the p5 rows (default sea-phase5)
#   MICRO_RECORD      a file to write the machine record of 2.17.3 into (key<TAB>value lines), at
#                     the end of a run in which every row was written. It needs MICRO_MODE (final
#                     or quick), MICRO_SESSION, MICRO_DATE, MICRO_SEA_COMMIT, MICRO_SEA_DIRTY,
#                     MICRO_BAYSICK_COMMIT, MICRO_BAYSICK_DIRTY and MICRO_SETTLE_WAITED (seconds,
#                     or - when no start condition ran), all set by bench/micro.sh --current; the
#                     rest (nice, power, loads before the first and after the last measured process,
#                     compiler, ...) is read here.

TARGET=${1:-}; DIR=${2:-}
[ -n "$TARGET" ] && [ -d "$DIR" ] || { echo "run.sh: usage: sh run.sh TARGET DIR" >&2; exit 2; }
MINREPS=${BENCH_MIN_REPS:-5}
MINSECS=${BENCH_MIN_SECONDS:-1.0}
MAXREPS=200
COMPILERS=${MICRO_COMPILERS:-p5 p4 c}
SEALABEL=${MICRO_SEA_LABEL:-sea-phase5}
RECORD=${MICRO_RECORD:-}
# the compiler list: only p5, p4 and c, at least one
[ -n "$COMPILERS" ] || { echo "run.sh: MICRO_COMPILERS is empty" >&2; exit 2; }
for comp in $COMPILERS; do
    case $comp in p5 | p4 | c) ;; *) echo "run.sh: MICRO_COMPILERS: unknown compiler '$comp'" >&2; exit 2 ;; esac
done
if [ -n "$RECORD" ]; then
    for v in MICRO_MODE MICRO_SESSION MICRO_DATE MICRO_SEA_COMMIT MICRO_SEA_DIRTY MICRO_BAYSICK_COMMIT \
        MICRO_BAYSICK_DIRTY MICRO_SETTLE_WAITED; do
        eval "[ -n \"\${$v:-}\" ]" || { echo "run.sh: MICRO_RECORD needs $v" >&2; exit 2; }
    done
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/sea-micro.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"; exit 2' HUP INT TERM PIPE

if [ "$(uname -s)" = Darwin ]; then
    CPU=$(sysctl -n machdep.cpu.brand_string)
    OSV="macOS $(sw_vers -productVersion) ($(uname -sr))"
else
    CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -1)
    OSV="$(uname -sr)"
fi
LOAD=$(uptime | sed 's/.*load averages*: *//')
{
    echo "machine: $CPU"
    echo "os: $OSV"
    echo "load average at start: $LOAD"
    echo "kernel variant: none (the benchmarks call no matrix kernel; SEA_KERNELS=${SEA_KERNELS:-unset})"
} >&2

printf 'target\tcpu\tbench\tcompiler\treps\tmedian_s\tmin_s\tmax_s\tunit\trate\n'

# get KEY FILE : the value of the output line `KEY value`
get() { sed -n "s/^$1 //p" "$2" | head -1; }

# check BENCH FILE : validate one run's output; prints the reason and returns 1 on failure
check() {
    case $1 in
    lcg)
        [ "$(get lcg_final "$2")" = 2145635252 ] || { echo "lcg_final is '$(get lcg_final "$2")', want 2145635252"; return 1; }
        [ "$(get u_last "$2")" = 0.99913927400444602 ] || { echo "u_last is '$(get u_last "$2")'"; return 1; } ;;
    sor)
        awk -v it="$(get it_sor "$2")" -v tm="$(get T_max "$2")" 'BEGIN {
            if (it == "" || it < 831 || it > 833) { print "it_sor is " it ", want 832 +- 1"; exit 1 }
            d = tm - 160.76267159277148; if (d < 0) d = -d
            if (tm == "" || d > 1e-6) { print "T_max is " tm ", want 160.76267159277148 within 1e-6"; exit 1 }
            exit 0 }' || return 1
        [ "$(get npts "$2")" = 37662 ] || { echo "npts is '$(get npts "$2")', want 37662"; return 1; } ;;
    esac
    [ -n "$(get seconds "$2")" ] || { echo "no seconds line"; return 1; }
    return 0
}

STATUS=0
# the three load averages just before the first measured process (the record of 2.17.3)
LOAD_BEFORE=$(uptime | sed 's/.*load averages*: *//; s/,/ /g' | tr -s ' ')
for bench in lcg sor; do
    for comp in $COMPILERS; do
        exe=$DIR/$bench.$comp
        [ -x "$exe" ] || { echo "run.sh: $exe missing" >&2; exit 2; }
        case $comp in p5) cname=$SEALABEL ;; p4) cname=sea-phase4 ;; c) cname=c-O2 ;; esac
        # validation + warm-up: the first run, untimed
        "$exe" >"$T/out" 2>"$T/err" </dev/null || { echo "run.sh: $bench.$comp failed: $(head -2 "$T/err")" >&2; exit 1; }
        if ! why=$(check "$bench" "$T/out"); then
            echo "run.sh: $bench $cname: validation failed: $why" >&2
            STATUS=1; continue
        fi
        : >"$T/secs"
        n=0; tot=0
        while :; do
            "$exe" >"$T/out" 2>"$T/err" </dev/null || { echo "run.sh: $bench.$comp failed: $(head -2 "$T/err")" >&2; exit 1; }
            if ! why=$(check "$bench" "$T/out"); then
                echo "run.sh: $bench $cname: validation failed in repetition $n: $why" >&2
                STATUS=1; n=-1; break
            fi
            s=$(get seconds "$T/out")
            echo "$s" >>"$T/secs"
            n=$((n + 1))
            tot=$(awk -v a="$tot" -v b="$s" 'BEGIN { printf "%.9f", a + b }')
            if [ "$n" -ge "$MAXREPS" ]; then break; fi
            if [ "$n" -ge "$MINREPS" ] && awk -v t="$tot" -v m="$MINSECS" 'BEGIN { exit !(t >= m) }'; then break; fi
        done
        [ "$n" -gt 0 ] || continue
        if [ "$bench" = lcg ]; then
            work=11000000; unit=ns/step
        else
            work=$(awk -v i="$(get it_sor "$T/out")" -v p="$(get npts "$T/out")" 'BEGIN { printf "%d", i * p }')
            unit=ns/point
        fi
        sort -n "$T/secs" | awk -v tg="$TARGET" -v cpu="$CPU" -v b="$bench" -v c="$cname" -v w="$work" -v u="$unit" '
            { v[NR] = $1 }
            END {
                med = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
                printf "%s\t%s\t%s\t%s\t%d\t%.6f\t%.6f\t%.6f\t%s\t%.3f\n", tg, cpu, b, c, NR, med, v[1], v[NR], u, med * 1e9 / w
            }'
    done
done

# ---- the machine record of 2.17.3 (MICRO_RECORD only); every row was written when STATUS is 0
if [ -n "$RECORD" ] && [ $STATUS -eq 0 ]; then
    LOAD_AFTER=$(uptime | sed 's/.*load averages*: *//; s/,/ /g' | tr -s ' ')
    NICE=$(ps -o nice= -p $$ | tr -d ' ')
    if [ "$(uname -s)" = Darwin ]; then
        MODEL=$(sysctl -n hw.model)
        if pmset -g batt | head -1 | grep 'AC Power' >/dev/null; then POWER=ac; else POWER=battery; fi
        LOWP=$(pmset -g | awk '$1 == "lowpowermode" { print $2 }')
        LOWP=${LOWP:-0}
        TOOLS=$(xcrun cc --version 2>&1 | head -1)
    else
        MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null) || MODEL=-
        [ -n "$MODEL" ] || MODEL=-
        POWER=-; LOWP=-
        TOOLS=$(gcc --version 2>&1 | head -1)
    fi
    {
        printf 'target\t%s\n' "$TARGET"
        printf 'mode\t%s\n' "$MICRO_MODE"
        printf 'session\t%s\n' "$MICRO_SESSION"
        printf 'date\t%s\n' "$MICRO_DATE"
        printf 'machine_model\t%s\n' "$MODEL"
        printf 'cpu\t%s\n' "$CPU"
        printf 'os\t%s\n' "$OSV"
        printf 'sea_commit\t%s\n' "$MICRO_SEA_COMMIT"
        printf 'sea_dirty\t%s\n' "$MICRO_SEA_DIRTY"
        printf 'baysick_commit\t%s\n' "$MICRO_BAYSICK_COMMIT"
        printf 'baysick_dirty\t%s\n' "$MICRO_BAYSICK_DIRTY"
        printf 'nice\t%s\n' "$NICE"
        printf 'power\t%s\n' "$POWER"
        printf 'lowpower\t%s\n' "$LOWP"
        printf 'variants\tnone\n'
        printf 'tools\t%s\n' "$TOOLS"
        printf 'settle_waited_s\t%s\n' "$MICRO_SETTLE_WAITED"
        printf 'load_before\t%s\n' "$LOAD_BEFORE"
        printf 'load_after\t%s\n' "$LOAD_AFTER"
    } >"$RECORD" || { echo "run.sh: cannot write $RECORD" >&2; exit 2; }
fi
exit $STATUS
